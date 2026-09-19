/// One bracketed observation of the bar: a capture, an Accessibility read, a
/// capture. The adapter produces these; nothing here touches a screen.
public struct ObservationSample: Equatable, Sendable {
    public let time: Double
    public let before: StripImage
    public let after: StripImage
    public let agentFrames: [AgentFrame]
    public let itemFrames: [String: ItemFrame]

    public init(time: Double, before: StripImage, after: StripImage, agentFrames: [AgentFrame], itemFrames: [String: ItemFrame]) {
        self.time = time
        self.before = before
        self.after = after
        self.agentFrames = agentFrames
        self.itemFrames = itemFrames
    }
}

/// What a baseline established: a template per item that passed every check, a
/// reason for each that did not, the ink those templates were cut with, and the
/// state of the fold at the time.
public struct BaselineResult: Equatable, Sendable {
    public let templates: [String: ItemTemplate]
    public let rejections: [String: Rejection]
    public let ink: Ink?
    public let agentFrames: [AgentFrame]
    public let foldAtBaseline: Fold
    public let geometry: BarGeometry

    public init(templates: [String: ItemTemplate], rejections: [String: Rejection], ink: Ink?, agentFrames: [AgentFrame], foldAtBaseline: Fold, geometry: BarGeometry) {
        self.templates = templates
        self.rejections = rejections
        self.ink = ink
        self.agentFrames = agentFrames
        self.foldAtBaseline = foldAtBaseline
        self.geometry = geometry
    }

    public var acceptedIDs: [String] { templates.keys.sorted() }
}

/// Turns samples into the facts the decision layer reads.
///
/// The split is deliberate: the adapter gathers pixels and frames, this decides
/// what they are allowed to mean, and `MenuBarItemVisibility` decides what to
/// call the result.
public enum StripAssessor {
    // MARK: - Baseline

    /// `ink` overrides the calibration for callers whose glyphs are not drawn
    /// in the bar's own ink — the replay of the 2026-09-18 runs, whose helpers
    /// drew in marker colours. Live callers pass nothing and the bar decides.
    public static func baseline(samples: [ObservationSample], geometry: BarGeometry, parameters: DetectorParameters, ink overrideInk: Ink? = nil) -> BaselineResult {
        precondition(parameters.isValid, "detector parameters violate their own invariants")

        let ids = Set(samples.flatMap(\.itemFrames.keys))
        func rejectAll(_ reason: Rejection) -> BaselineResult {
            BaselineResult(
                templates: [:],
                rejections: Dictionary(uniqueKeysWithValues: ids.map { ($0, reason) }),
                ink: nil,
                agentFrames: samples.last?.agentFrames ?? [],
                foldAtBaseline: .unreadable,
                geometry: geometry
            )
        }

        let ordered = samples.sorted { $0.time < $1.time }
        guard ordered.count >= parameters.baselineMinSamples,
              let first = ordered.first, let last = ordered.last,
              last.time - first.time >= parameters.baselineMinSpan
        else {
            return rejectAll(.baselineTooShort)
        }

        // The first samples are dropped: the first capture of a session moved
        // the clock's frame by 3 pt on 2026-09-19, so what it shows is not what
        // the rest of the run shows.
        let kept = Array(ordered.dropFirst(parameters.baselineDroppedSamples))
        let captures = kept.flatMap { [$0.before, $0.after] }
        guard let reference = captures.first,
              captures.allSatisfy({ $0.width == reference.width && $0.height == reference.height && $0.scale == reference.scale })
        else {
            return rejectAll(.capturesDiffer)
        }

        var rejections = [String: Rejection]()
        var frames = [String: ItemFrame]()
        for id in ids {
            let readings = kept.compactMap { $0.itemFrames[id] }
            guard readings.count == kept.count else {
                rejections[id] = .notInEveryRead
                continue
            }
            guard let firstReading = readings.first,
                  readings.allSatisfy({ agree(firstReading, $0, tolerance: parameters.readAgreementTolerancePt) })
            else {
                rejections[id] = .readsDisagree
                continue
            }
            frames[id] = firstReading
        }

        // Every frame that was read, including items rejected for other
        // reasons: their ink is still theirs, and counting it as unexplained
        // would make the fold unreadable and take the rest of the bar with it.
        let readSpans = kept.flatMap { $0.itemFrames.values.map(\.span) }

        guard let ink = overrideInk ?? Ink.calibrated(from: reference, geometry: geometry, glyphFrames: frames.values.map(\.span), parameters: parameters) else {
            for id in ids where rejections[id] == nil { rejections[id] = .inkUnknown }
            return BaselineResult(templates: [:], rejections: rejections, ink: nil, agentFrames: kept.last?.agentFrames ?? [], foldAtBaseline: .unreadable, geometry: geometry)
        }

        let maps = captures.map { ink.map($0) }
        let region = foldRegion(upTo: kept.flatMap { $0.itemFrames.values.map(\.minX) }.min(), geometry: geometry)
        let foldSamples = kept.enumerated().map { index, sample in
            FoldSample(
                time: sample.time,
                before: maps[index * 2],
                after: maps[index * 2 + 1],
                agentFrames: sample.agentFrames,
                // Nothing on the bar is claimed stable yet; the templates' own
                // static check below is what vouches for the baseline.
                referencesStable: true,
                explained: readSpans
            )
        }
        let fold = FoldWitness.derive(samples: foldSamples, baselineFrames: nil, region: region, geometry: geometry, parameters: parameters)
        guard fold == .absent else {
            for id in ids where rejections[id] == nil { rejections[id] = .foldNotAbsentAtBaseline }
            return BaselineResult(templates: [:], rejections: rejections, ink: ink, agentFrames: kept.last?.agentFrames ?? [], foldAtBaseline: fold, geometry: geometry)
        }

        let agentFrames = kept.last?.agentFrames ?? []
        for (id, frame) in frames {
            if frames.contains(where: { $0.key != id && $0.value.span.overlaps(frame.span) }) {
                rejections[id] = .overlapsAnotherItem
            } else if agentFrames.contains(where: { $0.span.overlaps(frame.span) }) {
                rejections[id] = .overlapsAgentItem
            }
        }

        var templates = [String: ItemTemplate]()
        for (id, frame) in frames where rejections[id] == nil {
            let cut = ItemTemplate.cut(frame, from: reference, ink: ink, geometry: geometry, parameters: parameters)
            guard let template = cut.template else {
                rejections[id] = cut.rejection ?? .noInk
                continue
            }
            let originPx = Int((template.originXPt * reference.scale).rounded())
            let allowed = Int((parameters.maxMismatch * Double(template.caredCount)).rounded(.down))
            let isStatic = maps.allSatisfy {
                TemplateMatcher.mismatchCount(template, in: $0, atPx: originPx, ceiling: allowed) <= allowed
            }
            guard case .unique(let x, _) = TemplateMatcher.match(template, in: maps[0], geometry: geometry, parameters: parameters),
                  abs(x - template.originXPt) <= parameters.sightingTolerancePt
            else {
                rejections[id] = .notUniqueAtBaseline
                continue
            }
            templates[id] = isStatic ? template : template.markedDynamic()
        }

        // Decided against a snapshot, then applied: removing as we go would
        // let the third of three overlapping templates survive, because the
        // ones it overlapped are gone by the time its turn comes.
        let overlapping = templates.filter { id, template in
            templates.contains { $0.key != id && $0.value.span.overlaps(template.span) }
        }
        for id in overlapping.keys {
            templates[id] = nil
            rejections[id] = .overlapsAnotherItem
        }

        return BaselineResult(templates: templates, rejections: rejections, ink: ink, agentFrames: agentFrames, foldAtBaseline: fold, geometry: geometry)
    }

    // MARK: - Observation

    public static func observe(
        baseline: BaselineResult,
        targets: [String],
        references: [String],
        samples: [ObservationSample],
        parameters: DetectorParameters
    ) -> StripReading {
        precondition(parameters.isValid, "detector parameters violate their own invariants")

        let geometry = baseline.geometry
        func refusal() -> StripReading {
            StripReading(sightings: [], fold: .unreadable, foldAtBaseline: baseline.foldAtBaseline, captureStable: false)
        }

        guard let ink = baseline.ink, samples.count >= parameters.minSamples else { return refusal() }
        let ordered = samples.sorted { $0.time < $1.time }
        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            guard next.time - previous.time >= parameters.minSampleSpacing else { return refusal() }
        }
        guard let lastSample = ordered.last else { return refusal() }

        let wanted = Array(Set(targets + references)).sorted()
        var matchesByCapture = [[String: Match]]()
        var mapsBySample = [(before: InkMap, after: InkMap)]()
        for sample in ordered {
            let before = ink.map(sample.before)
            let after = ink.map(sample.after)
            mapsBySample.append((before, after))
            for map in [before, after] {
                var matches = [String: Match]()
                for id in wanted {
                    guard let template = baseline.templates[id] else { continue }
                    matches[id] = TemplateMatcher.match(template, in: map, geometry: geometry, parameters: parameters)
                }
                matchesByCapture.append(matches)
            }
        }

        let referencesStable = CaptureStability.isStable(
            references: references,
            templates: baseline.templates,
            captures: matchesByCapture,
            parameters: parameters
        )
        let captureStable = referencesStable && settled(targets, in: matchesByCapture, parameters: parameters)

        let region = foldRegion(upTo: references.compactMap { baseline.templates[$0]?.originXPt }.min(), geometry: geometry)
        let foldSamples = ordered.enumerated().map { index, sample -> FoldSample in
            let explained = wanted.compactMap { id -> PtSpan? in
                guard let template = baseline.templates[id],
                      case .unique(let x, _)? = matchesByCapture[index * 2 + 1][id]
                else { return nil }
                return PtSpan(lo: x, hi: x + template.widthPt)
            }
            // Stability is decided per capture, so when every capture of the
            // observation held still, each sample's pair did too; the
            // per-sample check only says anything new when the whole does not.
            let stable = referencesStable || CaptureStability.isStable(
                references: references,
                templates: baseline.templates,
                captures: [matchesByCapture[index * 2], matchesByCapture[index * 2 + 1]],
                parameters: parameters
            )
            return FoldSample(
                time: sample.time,
                before: mapsBySample[index].before,
                after: mapsBySample[index].after,
                agentFrames: sample.agentFrames,
                referencesStable: stable,
                explained: explained
            )
        }
        let fold = FoldWitness.derive(
            samples: foldSamples,
            baselineFrames: baseline.agentFrames,
            region: region,
            geometry: geometry,
            parameters: parameters
        )

        let lastMatches = matchesByCapture[matchesByCapture.count - 1]
        let sightings = wanted.compactMap { id -> ItemSighting? in
            guard let template = baseline.templates[id], let match = lastMatches[id] else { return nil }
            let placement: Placement
            if case .unique(let x, _) = match {
                placement = Placement.assess(
                    frame: lastSample.itemFrames[id],
                    matchX: x,
                    matchWidthPt: template.widthPt,
                    geometry: geometry,
                    parameters: parameters
                )
            } else {
                placement = .unavailable
            }
            return ItemSighting(
                id: id,
                appearance: template.isDynamic ? .changedSinceBaseline : .asBaselined,
                match: match,
                placement: placement
            )
        }

        return StripReading(sightings: sightings, fold: fold, foldAtBaseline: baseline.foldAtBaseline, captureStable: captureStable)
    }

    // MARK: - Helpers

    /// Whether every target says the same thing in every capture. A capture
    /// taken mid-animation says something different from the one beside it, and
    /// the recorded runs hold such frames (items at quarter-point x values).
    public static func settled(_ targets: [String], in captures: [[String: Match]], parameters: DetectorParameters) -> Bool {
        guard !captures.isEmpty else { return false }
        for id in targets {
            // An item with no template is not unsettled, it is unobserved: the
            // decision layer says so by name, and calling the whole capture
            // unstable would hide which item is missing.
            guard let first = captures[0][id] else { continue }
            for capture in captures.dropFirst() {
                guard let match = capture[id], sameVerdict(first, match, tolerance: parameters.sightingTolerancePt) else { return false }
            }
        }
        return true
    }

    public static func sameVerdict(_ lhs: Match, _ rhs: Match, tolerance: Double) -> Bool {
        switch (lhs, rhs) {
        case let (.unique(x1, _), .unique(x2, _)): return abs(x1 - x2) <= tolerance
        case let (.ambiguous(c1), .ambiguous(c2)): return c1 == c2
        case (.absent, .absent): return true
        default: return false
        }
    }

    private static func agree(_ lhs: ItemFrame, _ rhs: ItemFrame, tolerance: Double) -> Bool {
        guard lhs.isFinite, rhs.isFinite else { return false }
        return abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
    }

    /// From the notch's right edge to the leftmost thing that vouches for the
    /// capture — the span `«` is drawn in.
    private static func foldRegion(upTo rightEdge: Double?, geometry: BarGeometry) -> PtSpan {
        let lo = geometry.notch?.hi ?? 0
        let hi = max(lo, rightEdge ?? geometry.widthPt)
        return PtSpan(lo: lo, hi: hi)
    }
}
