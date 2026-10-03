// T0, spike A: one profile -- launch, a rest control, every length as a jump
// from rest (two brackets, collapse, a restore control), the band, teardown.
import SpikeCore

extension SpikeStage {
    func measure(_ profile: SpikeProfile) -> ProfileResult {
        let result = sweep(profile)
        if let problem = teardown(), result.problem == nil {
            return ProfileResult(profile: profile, records: result.records, band: result.band, problem: "teardown: \(problem)")
        }
        return result
    }

    private func sweep(_ profile: SpikeProfile) -> ProfileResult {
        if let problem = launch(profile, memberMenu: false) {
            return ProfileResult(profile: profile, records: [], band: nil, problem: problem)
        }
        guard restControl() else { return ProfileResult(profile: profile, records: [], band: nil, problem: "rest control failed") }
        var records = [StepRecord]()
        for length in plan.lengths.values {
            records.append(step(length))
        }
        return ProfileResult(profile: profile, records: records, band: SpikeBand.widest(records), problem: nil)
    }

    /// Up to three brackets at rest, a settle apart, until one shows every member and visible helper.
    func restControl() -> Bool {
        var notBefore = lastChange + plan.settle
        for _ in 0..<Self.restControlAttempts {
            if let read = bracket("rest-control", notBefore: notBefore), read.controlPassed { return true }
            notBefore = clock.now() + plan.settle
        }
        return false
    }

    func step(_ length: Double) -> StepRecord {
        let name = "L\(Band.format(length))"
        setLength(length)
        var brackets = [StepObservation]()
        for i in 1...2 {
            let notBefore = i == 1 ? lastChange + plan.settle : clock.now() + plan.bracketGap
            if let read = bracket("\(name)-\(i)", notBefore: notBefore) { brackets.append(read.observation) }
        }
        rest()
        let control = bracket("\(name)-restore", notBefore: lastChange + plan.settle)?.controlPassed ?? false
        let outcome = SpikeRules.outcome(brackets, controlPassed: control)
        evidence.record("step", ["length": length, "outcome": "\(outcome)"])
        return StepRecord(length: length, outcome: outcome)
    }
}
