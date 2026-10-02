// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q2, Q8, Q17, Q19):
// the decisions inside one cycle or S-adv step, so the stage only gathers
// their inputs.
import C2Core
import IceBarClaim
import IceCore

public struct BaselineResolution: Equatable, Sendable {
    public let status: BaselineStatus
    /// What `Claim.decide` is given.
    public let claimInput: BaselineOutcome
    public let measurements: BaselineMeasurements?
}

public enum BaselineJudge {
    /// Q2: the cadence first; then the hidden-state baseline over the kept samples.
    /// A cadence refusal is "no baseline": it has no `BaselineRefusal` of its own,
    /// so the claim is given `.refused(.keptCount(0))` (never granted) and the
    /// cause is read from `status` (Q6). This is the only place that mapping lives.
    public static func resolve(_ selection: Result<BaselineSelection, CadenceRefusal>,
                               evaluate: ([ObservationSample]) -> BaselineVerdict) -> BaselineResolution {
        switch selection {
        case .failure(let refusal):
            return BaselineResolution(status: .cadence(refusal), claimInput: .refused(.keptCount(0)), measurements: nil)
        case .success(let kept):
            let verdict = evaluate(kept.kept)
            let status: BaselineStatus
            if case .refused(let refusal) = verdict.outcome { status = .refused(refusal) } else { status = .accepted }
            return BaselineResolution(status: status, claimInput: verdict.outcome, measurements: verdict.measurements)
        }
    }
}

public enum CycleRules {
    /// Q8: both member controls passed, in the state of every hold between them.
    public static func controlsHeld(rest: (passed: Bool, state: BarState), restore: (passed: Bool, state: BarState)?, holds: [BarState]) -> Bool {
        guard let restore, rest.passed, restore.passed else { return false }
        return holds.allSatisfy { $0 == rest.state && $0 == restore.state }
    }

    /// Q19: a band-scan cycle's reading; `nil` (inconclusive, retried) when its controls did not hold.
    public static func bandReading(controlsPassed: Bool, outcomes: [ObservationOutcome]) -> C2Reading? {
        guard controlsPassed else { return nil }
        return outcomes.contains(.granted) ? .hiddenNoFold : .stillDrawn
    }

    /// Q17-Q18: one S-adv step.
    public static func sAdvStep(noGo: Bool, appearanceMatches: Bool, anyInconclusive: Bool, seesMember: Bool) -> SAdvStepResult {
        if noGo { return .noGo }
        if !appearanceMatches || anyInconclusive { return .inconclusive }
        return seesMember ? .membersSeen : .membersGone
    }

    /// Q17: a sweep passes only when done with its controls held.
    public static func sweepResult(_ status: SAdvSweepStatus, controlsHeld: Bool) -> RepeatResult {
        switch status {
        case .noGo: .noGo
        case .done where controlsHeld: .pass
        default: .inconclusive
        }
    }
}
