/// The verifier's shared vocabulary (plan section 4.1.7, task T4b): frame
/// trimming (D15), a result per checked item, every reason a check can be
/// skipped instead, and the counts a status line shows.

/// D15's AX padding correction: every item frame handed to the detector is
/// trimmed by 1 pt on each side, the measured 2 pt adjacent overlap at rest
/// (plan section 0's MEASURED table). Agent frames are never passed here --
/// that is a caller discipline (`CheckPlan`), not something `trim` enforces,
/// so the 17.5 pt chevron rule stays unaffected.
public enum CheckFrames {
    public static let axPaddingTrim: Double = 1.0

    public static func trim(_ r: BarRect, by: Double = axPaddingTrim) -> BarRect {
        let width = max(0, r.width - 2 * by)
        return BarRect(minX: r.minX + by, minY: r.minY, width: width, height: r.height)
    }
}

/// Why the verifier declined to check a section, a divider, or one item
/// within a section (D14, D16, D17).
public enum CheckSkipReason: Equatable, Sendable {
    /// No reference candidate survived `CheckPlan`'s geometry filter.
    case noReference
    /// The section's divider is missing, unusable, or the own read failed.
    case dividerUnavailable
    /// No baseline has been captured yet for this section; shown for this
    /// many seconds so far.
    case noBaseline(shownSeconds: Double)
    /// A baseline exists but is older than `BaselineReuse.maxAge`.
    case baselineStale
    /// `RoomGuard.hasRoom` said no.
    case noRoom
    /// The screen, geometry, or display origin could not be resolved.
    case noGeometry
    /// `Preflight.run` failed, with its reason.
    case preflight(String)
    /// Ice is in IceBar mode -- dividers are re-assigned on every show.
    case iceBarMode
    /// The system is hiding the bar (e.g. a fullscreen app).
    case barHiddenBySystem
    /// The item's position is `.stacked`.
    case stacked
    /// The item's basis is `.positional`.
    case positional
    /// The item's current section is not one of the sections being checked.
    case notInSection
    /// The own process's read failed this pass.
    case ownReadFailed
    /// The job was cancelled before it produced a result.
    case cancelled
    /// Every attempt failed to produce a sample -- a capture or its AX read
    /// failed -- while nothing had cancelled the job (plan Deviation 5).
    case captureFailed
}

/// One item's result from one verification pass (D17).
public enum SectionItemCheck: Equatable, Sendable {
    case checked(Hiding)
    case refusedAtBaseline(Rejection)
    case skipped(CheckSkipReason)
}

/// Counts of a verification pass's results, keyed by each case's bare name
/// (no associated values) so a status line can display them without IceCore
/// knowing anything about presentation.
public struct VerificationSummary: Equatable, Sendable {
    public let hidden: Int
    public let stillDrawn: Int
    public let unverifiable: [String: Int]
    public let refused: [String: Int]
    public let skipped: [String: Int]

    public init(hidden: Int, stillDrawn: Int, unverifiable: [String: Int], refused: [String: Int], skipped: [String: Int]) {
        self.hidden = hidden
        self.stillDrawn = stillDrawn
        self.unverifiable = unverifiable
        self.refused = refused
        self.skipped = skipped
    }

    public static func make(_ results: [ItemKey: SectionItemCheck]) -> VerificationSummary {
        var hidden = 0
        var stillDrawn = 0
        var unverifiable = [String: Int]()
        var refused = [String: Int]()
        var skipped = [String: Int]()

        for check in results.values {
            switch check {
            case .checked(let hiding):
                switch hiding {
                case .hidden: hidden += 1
                case .stillDrawn: stillDrawn += 1
                case .unverifiable(let reason): unverifiable[caseName(reason), default: 0] += 1
                }
            case .refusedAtBaseline(let rejection):
                refused[caseName(rejection), default: 0] += 1
            case .skipped(let reason):
                skipped[caseName(reason), default: 0] += 1
            }
        }

        return VerificationSummary(hidden: hidden, stillDrawn: stillDrawn, unverifiable: unverifiable, refused: refused, skipped: skipped)
    }

    // Explicit switches, not a Mirror-based reflection: every case is named
    // once, deliberately, so a new case that forgets to update this file
    // fails to compile rather than silently missing from the summary.

    private static func caseName(_ reason: Unverifiable) -> String {
        switch reason {
        case .captureUnstable: return "captureUnstable"
        case .appearanceChanged: return "appearanceChanged"
        case .contradictsAccessibility: return "contradictsAccessibility"
        case .foldAlreadyUp: return "foldAlreadyUp"
        case .ambiguousMatch: return "ambiguousMatch"
        case .weakMatch: return "weakMatch"
        case .foldUnreadable: return "foldUnreadable"
        case .notObserved: return "notObserved"
        }
    }

    private static func caseName(_ rejection: Rejection) -> String {
        switch rejection {
        case .nonFiniteFrame: return "nonFiniteFrame"
        case .outsideStrip: return "outsideStrip"
        case .offBar: return "offBar"
        case .tooNarrow: return "tooNarrow"
        case .overlapsAnotherItem: return "overlapsAnotherItem"
        case .overlapsAgentItem: return "overlapsAgentItem"
        case .noInk: return "noInk"
        case .tooLittleInk: return "tooLittleInk"
        case .tooLittleBackground: return "tooLittleBackground"
        case .notUniqueAtBaseline: return "notUniqueAtBaseline"
        case .foldNotAbsentAtBaseline: return "foldNotAbsentAtBaseline"
        case .readsDisagree: return "readsDisagree"
        case .notInEveryRead: return "notInEveryRead"
        case .baselineTooShort: return "baselineTooShort"
        case .capturesDiffer: return "capturesDiffer"
        case .inkUnknown: return "inkUnknown"
        }
    }

    private static func caseName(_ reason: CheckSkipReason) -> String {
        switch reason {
        case .noReference: return "noReference"
        case .dividerUnavailable: return "dividerUnavailable"
        case .noBaseline: return "noBaseline"
        case .baselineStale: return "baselineStale"
        case .noRoom: return "noRoom"
        case .noGeometry: return "noGeometry"
        case .preflight: return "preflight"
        case .iceBarMode: return "iceBarMode"
        case .barHiddenBySystem: return "barHiddenBySystem"
        case .stacked: return "stacked"
        case .positional: return "positional"
        case .notInSection: return "notInSection"
        case .ownReadFailed: return "ownReadFailed"
        case .cancelled: return "cancelled"
        case .captureFailed: return "captureFailed"
        }
    }
}
