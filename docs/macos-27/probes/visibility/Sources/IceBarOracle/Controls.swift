// Positive and member controls, and the verdict per attempt
// (pre-registration section 5, "Positive controls" and "Verdict per attempt").
import IceCore

public struct VisibleHelper: Equatable, Sendable {
    public let id: String
    public let axMinX: Double

    public init(id: String, axMinX: Double) {
        self.id = id
        self.axMinX = axMinX
    }
}

public enum Controls {
    /// Visible helpers not `drawn(full)` within 2 pt of AX `minX` plus the
    /// glyph's inset; one miss makes the attempt inconclusive.
    public static func positiveMisses(_ capture: CaptureLabels, visible: [VisibleHelper], parameters: OracleParameters = .preRegistered) -> [String] {
        visible.filter { helper in
            guard case let .drawn(.full, x, _)? = capture.labels[helper.id] else { return true }
            return abs(x - (helper.axMinX + parameters.glyphInsetPt)) > parameters.positionTolerancePt
        }.map(\.id)
    }

    /// Members not `drawn(full)` in a rest capture.
    public static func memberMisses(_ capture: CaptureLabels, members: [String]) -> [String] {
        members.filter { id in
            guard case .drawn(.full, _, _)? = capture.labels[id] else { return true }
            return false
        }
    }

    /// A member missed at rest (before the push or after the collapse) makes
    /// the whole cycle inconclusive.
    public static func cycleInconclusive(restCaptures: [CaptureLabels], members: [String]) -> Bool {
        restCaptures.contains { !memberMisses($0, members: members).isEmpty }
    }
}

public struct AttemptVerdict: Equatable, Sendable {
    /// Any capture has a member identified `full`, or any unexplained
    /// sighting (deviation 2 C1, fail-closed).
    public let seesMember: Bool
    /// (a) in any read or (b) in any capture.
    public let seesChevron: Bool
    /// Some capture had no chevron template at its scale (never certifies).
    public let chevronNotEvaluable: Bool
    public let controlMisses: [String]
    /// Deviation 2 C3: the window-server overlap guard over every helper.
    public let overlap: OverlapOutcome
    public let inconclusive: Bool

    public static func evaluate(
        captures: [CaptureLabels],
        reads: [[AgentFrame]],
        barHeightPt: Double,
        members: Set<String>,
        visible: [VisibleHelper],
        overlap: OverlapOutcome
    ) -> AttemptVerdict {
        let seesMember = captures.contains { capture in
            capture.hasUnexplainedSighting || members.contains { id in
                if case .drawn(.full, _, _)? = capture.labels[id] { return true }
                return false
            }
        }
        let seesChevron = ChevronRule.fromAX(reads: reads, barHeightPt: barHeightPt) || captures.contains { $0.chevron == .present }
        var misses = [String]()
        for capture in captures {
            for id in Controls.positiveMisses(capture, visible: visible) where !misses.contains(id) {
                misses.append(id)
            }
        }
        return AttemptVerdict(
            seesMember: seesMember,
            seesChevron: seesChevron,
            chevronNotEvaluable: captures.contains { $0.chevron == .notEvaluable },
            controlMisses: misses,
            overlap: overlap,
            inconclusive: !misses.isEmpty || overlap != .clear || captures.contains(where: \.isInconclusive)
        )
    }
}
