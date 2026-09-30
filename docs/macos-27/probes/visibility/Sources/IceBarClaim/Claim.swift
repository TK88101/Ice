// Rule 4, the claim (pre-registration section 4; claim plan R17): granted
// only with an accepted baseline, the frozen fold `.absent`, and `RegionClear`
// clear in the same attempt.
import IceCore

public enum ClaimReason: Equatable, Sendable {
    case noBaseline(BaselineRefusal)
    case fold(Fold)
    case notClear
}

public struct ClaimOutcome: Equatable, Sendable {
    /// Why the claim is not granted, every cause (section 4 splits by cause).
    public let reasons: [ClaimReason]
    /// nil when there was no baseline: `RegionClear` is never evaluated then.
    public let regionClear: RegionClearOutcome?

    public var granted: Bool { reasons.isEmpty }
}

public enum Claim {
    /// `fold`: the frozen `StripAssessor.observe` reading of the attempt;
    /// `captures`: the attempt's 6 captures. `RegionClear` is evaluated here,
    /// once; part 3 does not call it separately.
    public static func decide(fold: Fold, baseline: BaselineOutcome, captures: [StripImage],
                              parameters: ClaimParameters = .preRegistered) -> ClaimOutcome {
        switch baseline {
        case let .refused(refusal):
            return ClaimOutcome(reasons: [.noBaseline(refusal)], regionClear: nil)
        case let .accepted(hidden):
            let clear = RegionClear.evaluate(baseline: hidden, captures: captures, parameters: parameters)
            var reasons = [ClaimReason]()
            if fold != .absent { reasons.append(.fold(fold)) }
            if case .notClear = clear { reasons.append(.notClear) }
            return ClaimOutcome(reasons: reasons, regionClear: clear)
        }
    }
}
