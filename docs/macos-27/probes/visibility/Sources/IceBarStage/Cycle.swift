// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q2-Q8): one hidden-
// state baseline, one observation of up to three attempts, a member control,
// and the S0/S1 cycle that strings them together. Every decision is
// `IceBarRunCore`'s or part 2's (`HiddenBaseline.evaluate`, `Claim.decide`, which
// evaluates `RegionClear` once); this file only sequences captures.
//
// Captures are taken on the cadence and judged by the oracle afterwards, in
// capture order: the stop rule reads the claim only (Q3), and the oracle's
// time must never stretch a baseline or an observation past its cadence.
import IceBarClaim
import IceBarOracle
import IceBarRunCore
import IceCore

struct BaselineRun {
    let taken: [Taken]
    let status: BaselineStatus
    /// What `Claim.decide` is given.
    let outcome: BaselineOutcome
    let frozen: BaselineResult
    /// The first kept read's on-bar frames (Q4), accepted or refused.
    let canonical: [AgentFrame]
    let measurements: BaselineMeasurements?
    let leftmost: Double?
    /// The hold's state: the first kept sample's.
    let holdState: BarState
}

/// One attempt as taken: its samples, its claim, its cadence.
struct RawAttempt {
    let taken: [Taken]
    let claim: ClaimOutcome
    let cadence: CadenceRefusal?
}

struct RawObservation {
    let attempts: [RawAttempt]
    let timedOut: Bool
}

struct ObservationRun {
    let record: ObservationRecord
    let attempts: [AttemptRecord]
    let judged: [Judged]
}

struct ControlRun {
    let judged: Judged
    let passed: Bool
}

struct CycleRun {
    let record: CycleRecord
    let claimGranted: Bool
    let controlsPassed: Bool
    let measurements: BaselineMeasurements?
    /// A NO-GO in any attempt, or (S1) a member seen left of the notch in any capture.
    let noGo: Bool

    /// Q19: in band iff conclusive, no NO-GO, and some observation granted and clean.
    var inBand: Bool { controlsPassed && !noGo && record.observations.contains { $0.outcome == .granted } }
}

extension IceBarStep {
    func onBar(_ frames: [AgentFrame]) -> [AgentFrame] {
        frames.filter { $0.minY >= 0 && $0.minY < environment.geometry.heightPt }
    }

    /// Q2: five samples, the first settled after the last change, >= 1.0 s apart.
    func takeBaseline() -> BaselineRun? {
        var taken = [Taken]()
        for i in 0..<cadence.baselineSamples {
            let notBefore = i == 0 ? lastChange + cadence.settle : taken[i - 1].timed.start + cadence.baselineSpacing
            guard let sample = probe.take("baseline", notBefore: notBefore) else { return nil }
            taken.append(sample)
        }
        let all = taken.map(\.timed.sample)
        let frozen = StripAssessor.baseline(samples: all, geometry: environment.geometry, parameters: .preRegistered)
        let status: BaselineStatus
        let outcome: BaselineOutcome
        var measurements: BaselineMeasurements?
        switch Cadence.baseline(taken.map(\.timed), lastChange: lastChange, parameters: cadence) {
        case .success(let selection):
            let verdict = HiddenBaseline.evaluate(kept: selection.kept, frozen: frozen, references: probe.visible,
                                                  visible: probe.visible.compactMap { templates.helpers[$0] })
            outcome = verdict.outcome
            measurements = verdict.measurements
            if case .refused(let refusal) = verdict.outcome { status = .refused(refusal) } else { status = .accepted }
        case .failure(let refusal):
            status = .cadence(refusal)
            // No baseline: the cadence refusal has no `BaselineRefusal` of its own.
            outcome = .refused(.keptCount(0))
        }
        environment.evidence.record("baseline", ["status": "\(status)", "fold": "\(frozen.foldAtBaseline)",
                                                  "measurements": "\(String(describing: measurements))"])
        return BaselineRun(taken: taken, status: status, outcome: outcome, frozen: frozen, canonical: onBar(all[1].agentFrames),
                           measurements: measurements, leftmost: probe.visible.compactMap { frozen.templates[$0]?.originXPt }.min(),
                           holdState: probe.state(of: taken[1]))
    }

    /// Q3: up to three attempts, stopping after the first granted claim; not yet judged.
    func observe(_ baseline: BaselineRun, firstStart: Double) -> RawObservation? {
        var attempts = [RawAttempt]()
        var notBefore = firstStart
        while AttemptJudge.needsAnotherAttempt(claims: attempts.map(\.claim), parameters: cadence) {
            var taken = [Taken]()
            for i in 0..<cadence.observationSamples {
                let start = i == 0 ? notBefore : taken[i - 1].timed.start + cadence.observationSpacing
                guard let sample = probe.take("attempt", notBefore: start) else { return nil }
                taken.append(sample)
            }
            let timed = taken.map(\.timed)
            let fold = StripAssessor.observe(baseline: baseline.frozen, targets: [], references: probe.visible,
                                             samples: timed.map(\.sample), parameters: .preRegistered).fold
            let claim = Claim.decide(fold: fold, baseline: baseline.outcome, captures: timed.flatMap { [$0.sample.before, $0.sample.after] })
            attempts.append(RawAttempt(taken: taken, claim: claim, cadence: Cadence.attempt(timed, notBefore: notBefore, parameters: cadence)))
            environment.evidence.record("attempt", ["fold": "\(fold)", "claim": "\(claim.reasons)", "regionClear": "\(String(describing: claim.regionClear))"])
            notBefore = Cadence.nextAttemptStart(after: timed, parameters: cadence)
        }
        return RawObservation(attempts: attempts, timedOut: Cadence.observationTimedOut(attempts.map { $0.taken.map(\.timed) }, parameters: cadence))
    }

    func judgeBaseline(_ baseline: BaselineRun) -> [Judged] {
        baseline.taken.map { probe.judge($0, canonical: baseline.canonical, leftmost: baseline.leftmost) }
    }

    /// Q4-Q6: the oracle on every attempt's captures, then section 4's judgement.
    func judgeObservation(_ raw: RawObservation, baseline: BaselineRun) -> ObservationRun {
        var records = [AttemptRecord]()
        var judged = [Judged]()
        for attempt in raw.attempts {
            let attemptJudged = attempt.taken.map { probe.judge($0, canonical: baseline.canonical, leftmost: baseline.leftmost) }
            let record = AttemptRecord(claim: attempt.claim, oracle: OracleSummary.combine(attemptJudged.map(\.verdict)),
                                       cadence: attempt.cadence, memberLeftOfNotch: s1Rules && leftOfNotch(attemptJudged))
            environment.evidence.record("attempt.judged", ["oracle": "\(record.oracle)", "class": AttemptJudge.classify(record).rawValue])
            records.append(record)
            judged += attemptJudged
        }
        let record = AttemptJudge.observation(records, timedOut: raw.timedOut, baseline: baseline.status)
        environment.evidence.record("observation", ["outcome": record.outcome.rawValue, "cause": record.cause?.rawValue ?? "", "attempts": record.attempts])
        return ObservationRun(record: record, attempts: records, judged: judged)
    }

    /// Q8: one sample with every member and visible helper `drawn(full)`; judged at once.
    func control(_ phase: String) -> ControlRun? {
        guard let taken = takeControl(phase) else { return nil }
        return judgeControl(taken)
    }

    func takeControl(_ phase: String) -> Taken? {
        probe.take(phase, notBefore: max(environment.clock.now(), lastChange + cadence.settle))
    }

    func judgeControl(_ taken: Taken) -> ControlRun {
        let leftmost = probe.visible.compactMap { taken.timed.sample.itemFrames[$0]?.minX }.min()
        let judged = probe.judge(taken, canonical: [], leftmost: leftmost)
        return ControlRun(judged: judged, passed: probe.controlPassed(judged))
    }

    func leftOfNotch(_ judged: [Judged]) -> Bool {
        OracleSummary.memberLeftOfNotch(judged.flatMap(\.labels), members: Set(probe.members),
                                        notch: environment.geometry.notch, scale: environment.geometry.scale)
    }

    func setLength(_ length: Double) {
        spacer?.send("length \(length)")
        lastChange = environment.clock.now()
    }

    func rest() {
        spacer?.send("rest")
        lastChange = environment.clock.now()
    }

    /// Q8: rest control, push to `length`, baseline, 4 observations 5 s apart,
    /// collapse, restore control; then every capture judged in order.
    func cycle(_ length: Double) -> CycleRun? {
        guard environment.menus.stillInPlace(), let restTaken = takeControl("rest control") else { return nil }
        setLength(length)
        guard let baseline = takeBaseline() else { return nil }
        let first = max(environment.clock.now(), lastChange + cadence.settle)
        var raws = [RawObservation]()
        for i in 0..<cadence.observationsPerCycle {
            let start = max(environment.clock.now(), Cadence.observationStart(i, first: first, parameters: cadence))
            guard let raw = observe(baseline, firstStart: start) else { return nil }
            raws.append(raw)
        }
        rest()
        guard let restoreTaken = takeControl("restore control") else { return nil }

        let restControl = judgeControl(restTaken)
        let baselineJudged = judgeBaseline(baseline)
        let observations = raws.map { judgeObservation($0, baseline: baseline) }
        let restoreControl = judgeControl(restoreTaken)
        let hold = baseline.holdState
        let controlsPassed = restControl.passed && restoreControl.passed
            && restControl.judged.state == hold && restoreControl.judged.state == hold
        let records = observations.map(\.record)
        let anyLeft = s1Rules && leftOfNotch([restControl.judged, restoreControl.judged] + baselineJudged)
        let run = CycleRun(record: CycleRecord(observations: records, controlMiss: !controlsPassed),
                           claimGranted: raws.contains { $0.attempts.contains { $0.claim.granted } },
                           controlsPassed: controlsPassed, measurements: baseline.measurements,
                           noGo: anyLeft || records.contains { $0.outcome == .noGo })
        environment.evidence.record("cycle", ["length": length, "controlsPassed": controlsPassed, "noGo": run.noGo,
                                              "observations": records.map { $0.outcome.rawValue }])
        return run
    }
}
