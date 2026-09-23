// Guard: the safety guard that protects the user's real menu bar items during
// experiments. It never sees pixels itself; callers hand it TemplateResults
// (from template matching) and a presence callback. See the doc comments
// below for the exact rule each piece encodes.

/// Whether two point measurements moved further apart than `tolerance` allows.
///
/// Rule: a room reading drifted iff `|after - before| > tolerance`. Equal to
/// `tolerance` counts as not drifted.
public enum RoomCheck {
    public static func drifted(before: Double, after: Double, tolerance: Double) -> Bool {
        abs(after - before) > tolerance
    }
}

/// A time-since-last-known-good watchdog for the spacer.
///
/// Rule: `lastClean` starts at `start` and only ever moves forward, via
/// `noteClean(at:)`. `expired(at:spacerAtRest:)` is never true while the
/// spacer is at rest, and otherwise is true once more than `limit` seconds
/// have passed since the last clean reading.
public struct Deadman: Sendable {
    private let limit: Double
    private var lastClean: Double

    public init(limit: Double, start: Double) {
        precondition(limit.isFinite && limit >= 0, "limit must be finite and non-negative")
        precondition(start.isFinite, "start must be finite")
        self.limit = limit
        self.lastClean = start
    }

    /// Records a clean reading at `time`. Never moves `lastClean` backwards.
    public mutating func noteClean(at time: Double) {
        precondition(time.isFinite, "time must be finite")
        lastClean = max(lastClean, time)
    }

    /// True iff the spacer is not at rest and more than `limit` seconds have
    /// passed since the last clean reading.
    public func expired(at now: Double, spacerAtRest: Bool) -> Bool {
        guard !spacerAtRest else { return false }
        precondition(now.isFinite, "now must be finite")
        return now - lastClean > limit
    }
}

/// How a `GuardFinding` counts towards the persistence counters in rule I.
private enum FindingClass {
    case harm
    case unknown
    case info
}

extension GuardFinding {
    /// Rule H: protectedLost, itemLost and pillHidden are harm; itemUnverifiable
    /// is unknown; appearanceChanged and shifted are informational only.
    fileprivate var findingClass: FindingClass {
        switch self {
        case .protectedLost, .itemLost, .pillHidden:
            return .harm
        case .itemUnverifiable:
            return .unknown
        case .appearanceChanged, .shifted:
            return .info
        }
    }
}

/// The safety guard that decides, capture by capture, whether the spacer must
/// be put back to rest. It never touches pixels: it only reasons over
/// `TemplateResult`s already computed by template matching, plus a presence
/// callback the caller supplies.
public struct SafetyGuard: Sendable {
    /// The user's items in left-to-right baseline order. A `.static` item that
    /// changed its look in place while its anchors still agreed is reclassified
    /// to `.dynamic` here, after the capture that observed the change.
    public private(set) var baselines: [UserItemBaseline]

    private let protectedExpected: Span
    private let protectedTolerance: Double
    private let anchorTolerance: Double
    private let persistence: Int

    /// Consecutive captures, up to and including the most recent one, that
    /// contained at least one harm finding.
    private var harmStreak = 0
    /// Consecutive captures, up to and including the most recent one, that
    /// contained at least one unknown finding.
    private var unknownStreak = 0

    public init(
        baselines: [UserItemBaseline],
        protectedExpected: Span,
        protectedTolerance: Double,
        anchorTolerance: Double,
        persistence: Int = 2
    ) {
        precondition(persistence >= 1, "persistence must be at least 1")
        precondition(protectedTolerance.isFinite && protectedTolerance >= 0, "protectedTolerance must be finite and non-negative")
        precondition(anchorTolerance.isFinite && anchorTolerance >= 0, "anchorTolerance must be finite and non-negative")
        precondition(Set(baselines.map(\.id)).count == baselines.count, "baseline ids must be unique")
        // Force every baseline's span to be computed now, so a bad width or
        // originX (negative, NaN, ...) crashes here at setup instead of later,
        // mid-experiment, inside assess.
        _ = baselines.map(\.span)
        self.baselines = baselines
        self.protectedExpected = protectedExpected
        self.protectedTolerance = protectedTolerance
        self.anchorTolerance = anchorTolerance
        self.persistence = persistence
    }

    /// Assesses one capture against the baselines and returns what the caller
    /// should do. See the module doc for the full rule set (A through J).
    public mutating func assess(_ reading: CaptureReading, presence: (String, Span) -> Bool) -> GuardDecision {
        let protectedOffset = Self.protectedAnchorOffset(
            protected: reading.protected,
            expected: protectedExpected,
            tolerance: protectedTolerance
        )

        var resultsById: [String: TemplateResult] = [:]
        // Rule B assumes exactly one reading per baseline id. More than one
        // reading for the same id makes that item's state ambiguous, which
        // this guard treats the same as no reading at all, and its offset is
        // never trusted as a neighbour's anchor either.
        var duplicateIds: Set<String> = []
        resultsById.reserveCapacity(reading.items.count)
        for itemReading in reading.items {
            if resultsById[itemReading.id] != nil {
                duplicateIds.insert(itemReading.id)
            }
            resultsById[itemReading.id] = itemReading.template
        }

        var findings: [GuardFinding] = []
        if protectedOffset == nil {
            findings.append(.protectedLost)
        }

        // Reclassifications are collected here and applied only after every
        // item in this capture has been assessed, so a change triggered by
        // one item never shifts another item's anchors within this capture
        // (rule E).
        var reclassifyToDynamic: Set<String> = []

        for index in baselines.indices {
            let baseline = baselines[index]
            guard !duplicateIds.contains(baseline.id),
                  let templateResult = resultsById[baseline.id] else {
                // Rule B: no reading (or an ambiguous, duplicated one) for
                // this baseline item.
                findings.append(.itemUnverifiable(id: baseline.id))
                continue
            }

            switch baseline.kind {
            case .static:
                if let finding = assessStaticItem(
                    at: index,
                    templateResult: templateResult,
                    resultsById: resultsById,
                    duplicateIds: duplicateIds,
                    protectedOffset: protectedOffset,
                    presence: presence
                ) {
                    findings.append(finding)
                    if case .appearanceChanged = finding {
                        reclassifyToDynamic.insert(baseline.id)
                    }
                }
            case .dynamic:
                if let finding = assessDynamicItem(
                    at: index,
                    resultsById: resultsById,
                    duplicateIds: duplicateIds,
                    protectedOffset: protectedOffset,
                    presence: presence
                ) {
                    findings.append(finding)
                }
            }
        }

        if let pill = reading.pill, pill.axPresent, !pill.pixelPresent {
            findings.append(.pillHidden)
        }

        for index in baselines.indices where reclassifyToDynamic.contains(baselines[index].id) {
            baselines[index].kind = .dynamic
        }

        return decide(findings: findings)
    }

    /// Rules D and E: a `.static` item is checked by its own template result.
    /// `found` items are visible and never harm; `notFound` items fall back to
    /// their anchors and presence.
    private func assessStaticItem(
        at index: Int,
        templateResult: TemplateResult,
        resultsById: [String: TemplateResult],
        duplicateIds: Set<String>,
        protectedOffset: Double?,
        presence: (String, Span) -> Bool
    ) -> GuardFinding? {
        let baseline = baselines[index]
        switch templateResult {
        case .found(let offset):
            guard abs(offset) > anchorTolerance else { return nil }
            return .shifted(id: baseline.id, offset: offset)
        case .notFound:
            let anchors = anchorOffsets(
                around: index,
                resultsById: resultsById,
                duplicateIds: duplicateIds,
                protectedOffset: protectedOffset
            )
            if let common = agreeingOffset(anchors), presence(baseline.id, shift(baseline.span, by: common)) {
                return .appearanceChanged(id: baseline.id)
            }
            return .itemLost(id: baseline.id)
        }
    }

    /// Rule F: a `.dynamic` item is checked entirely by its anchors and
    /// presence; its own template result is irrelevant.
    private func assessDynamicItem(
        at index: Int,
        resultsById: [String: TemplateResult],
        duplicateIds: Set<String>,
        protectedOffset: Double?,
        presence: (String, Span) -> Bool
    ) -> GuardFinding? {
        let baseline = baselines[index]
        let anchors = anchorOffsets(
            around: index,
            resultsById: resultsById,
            duplicateIds: duplicateIds,
            protectedOffset: protectedOffset
        )
        guard let common = agreeingOffset(anchors) else {
            return .itemUnverifiable(id: baseline.id)
        }
        guard presence(baseline.id, shift(baseline.span, by: common)) else {
            return .itemLost(id: baseline.id)
        }
        return nil
    }

    /// Rule C: the left and right anchor offsets for the baseline item at
    /// `index`, using each baseline's kind as it stood before this capture.
    private func anchorOffsets(
        around index: Int,
        resultsById: [String: TemplateResult],
        duplicateIds: Set<String>,
        protectedOffset: Double?
    ) -> (left: Double?, right: Double?) {
        (leftAnchorOffset(before: index, resultsById: resultsById, duplicateIds: duplicateIds, protectedOffset: protectedOffset),
         rightAnchorOffset(after: index, resultsById: resultsById, duplicateIds: duplicateIds))
    }

    private func leftAnchorOffset(
        before index: Int,
        resultsById: [String: TemplateResult],
        duplicateIds: Set<String>,
        protectedOffset: Double?
    ) -> Double? {
        var i = index - 1
        while i >= 0 {
            if baselines[i].kind == .static {
                return staticOffset(id: baselines[i].id, resultsById: resultsById, duplicateIds: duplicateIds)
            }
            i -= 1
        }
        // No static item to the left: the virtual anchor is P itself.
        return protectedOffset
    }

    private func rightAnchorOffset(
        after index: Int,
        resultsById: [String: TemplateResult],
        duplicateIds: Set<String>
    ) -> Double? {
        var i = index + 1
        while i < baselines.count {
            if baselines[i].kind == .static {
                return staticOffset(id: baselines[i].id, resultsById: resultsById, duplicateIds: duplicateIds)
            }
            i += 1
        }
        // No static item to the right: the virtual anchor is the screen edge,
        // always available with offset 0.
        return 0
    }

    /// A static item's anchor offset is its template offset when found, and
    /// unavailable (nil) when not found or when its reading was ambiguous
    /// (duplicated).
    private func staticOffset(id: String, resultsById: [String: TemplateResult], duplicateIds: Set<String>) -> Double? {
        guard !duplicateIds.contains(id), case .found(let offset) = resultsById[id] else { return nil }
        return offset
    }

    /// Rule C: two anchors agree iff both have an offset and those offsets are
    /// within `anchorTolerance` of each other; their common offset is the
    /// right anchor's.
    private func agreeingOffset(_ anchors: (left: Double?, right: Double?)) -> Double? {
        guard let left = anchors.left, let right = anchors.right else { return nil }
        guard abs(left - right) <= anchorTolerance else { return nil }
        return right
    }

    /// Rule A: P is ok iff its marker is uniquely found within
    /// `protectedTolerance` of where it should be; the offset is only ever
    /// returned when P is ok, matching "available iff rule A says ok".
    private static func protectedAnchorOffset(protected: MarkerResult, expected: Span, tolerance: Double) -> Double? {
        guard case .unique(let span) = protected else { return nil }
        let offset = span.mid - expected.mid
        guard abs(offset) <= tolerance else { return nil }
        return offset
    }

    /// Rule I: advances the persistence counters for this capture's findings
    /// and turns them into a decision.
    private mutating func decide(findings: [GuardFinding]) -> GuardDecision {
        let hasHarm = findings.contains { $0.findingClass == .harm }
        let hasUnknown = findings.contains { $0.findingClass == .unknown }

        guard hasHarm || hasUnknown else {
            harmStreak = 0
            unknownStreak = 0
            let info = findings.filter { $0.findingClass == .info }
            return .clean(info: info)
        }

        harmStreak = hasHarm ? harmStreak + 1 : 0
        unknownStreak = hasUnknown ? unknownStreak + 1 : 0

        let reasons = findings.filter { $0.findingClass == .harm || $0.findingClass == .unknown }

        if unknownStreak >= persistence {
            return .stop(reasons: reasons)
        }
        if harmStreak >= persistence {
            return .restore(reasons: reasons)
        }
        return .suspect(reasons: reasons)
    }
}

/// Rule J: shifts a span by an offset.
private func shift(_ span: Span, by offset: Double) -> Span {
    Span(lo: span.lo + offset, hi: span.hi + offset)
}
