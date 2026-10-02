// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q2-Q8): one hidden-
// state baseline and its observations (a measurement), a member control, and
// the S0/S1 cycle. Every decision is `IceBarRunCore`'s or part 2's
// (`HiddenBaseline.evaluate`, `Claim.decide`, which evaluates `RegionClear`
// once); this file only sequences captures.
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
    let resolution: BaselineResolution
    let frozen: BaselineResult
    /// The first kept read's on-bar frames (Q4), accepted or refused.
    let canonical: [AgentFrame]
    let leftmost: Double?
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

/// A baseline and its observations, taken but not yet judged.
struct Measurement {
    let baseline: BaselineRun
    let observations: [RawObservation]
}

struct ObservationRun {
    let record: ObservationRecord
    let judged: [Judged]
}

/// A measurement after the oracle.
struct JudgedMeasurement {
    let baseline: [Judged]
    let observations: [ObservationRun]

    /// The hold's state: the first kept sample's (Q8).
    var holdState: BarState { baseline[1].state }
    var all: [Judged] { baseline + observations.flatMap(\.judged) }
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
}

extension IceBarStep {
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
        let resolution = BaselineJudge.resolve(Cadence.baseline(taken.map(\.timed), lastChange: lastChange, parameters: cadence)) { kept in
            HiddenBaseline.evaluate(kept: kept, frozen: frozen, references: probe.visible, visible: probe.visible.compactMap { templates.helpers[$0] })
        }
        environment.evidence.record("baseline", ["status": "\(resolution.status)", "fold": "\(frozen.foldAtBaseline)",
                                                  "measurements": "\(String(describing: resolution.measurements))"])
        return BaselineRun(taken: taken, resolution: resolution, frozen: frozen,
                           canonical: OnBar.frames(all[1].agentFrames, heightPt: environment.geometry.heightPt),
                           leftmost: probe.visible.compactMap { frozen.templates[$0]?.originXPt }.min())
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
            let claim = Claim.decide(fold: fold, baseline: baseline.resolution.claimInput, captures: timed.flatMap { [$0.sample.before, $0.sample.after] })
            attempts.append(RawAttempt(taken: taken, claim: claim, cadence: Cadence.attempt(timed, notBefore: notBefore, parameters: cadence)))
            environment.evidence.record("attempt", ["fold": "\(fold)", "claim": "\(claim.reasons)", "regionClear": "\(String(describing: claim.regionClear))"])
            notBefore = Cadence.nextAttemptStart(after: timed, parameters: cadence)
        }
        return RawObservation(attempts: attempts, timedOut: Cadence.observationTimedOut(attempts.map { $0.taken.map(\.timed) }, parameters: cadence))
    }

    /// Q2-Q3, Q8: a baseline and `count` observations nominally 5 s apart (4 in a cycle, 1 per S-adv step).
    func measure(observations count: Int) -> Measurement? {
        guard let baseline = takeBaseline() else { return nil }
        let first = max(environment.clock.now(), Cadence.firstAttemptStart(lastChange: lastChange, parameters: cadence))
        var observations = [RawObservation]()
        for i in 0..<count {
            let start = max(environment.clock.now(), Cadence.observationStart(i, first: first, parameters: cadence))
            guard let observation = observe(baseline, firstStart: start) else { return nil }
            observations.append(observation)
        }
        return Measurement(baseline: baseline, observations: observations)
    }

    /// Q4-Q6: the oracle on every capture of a measurement, in capture order, then section 4's judgement.
    func judge(_ measurement: Measurement) -> JudgedMeasurement {
        let baseline = measurement.baseline
        let attempts = measurement.observations.flatMap(\.attempts)
        let judged = probe.judge(baseline.taken + attempts.flatMap(\.taken), canonical: baseline.canonical, leftmost: baseline.leftmost)
        var cursor = baseline.taken.count
        let observations = measurement.observations.map { raw -> ObservationRun in
            var records = [AttemptRecord]()
            var observationJudged = [Judged]()
            for attempt in raw.attempts {
                let attemptJudged = Array(judged[cursor..<cursor + attempt.taken.count])
                cursor += attempt.taken.count
                let record = AttemptRecord(claim: attempt.claim, oracle: OracleSummary.combine(attemptJudged.map(\.verdict)),
                                           cadence: attempt.cadence, memberLeftOfNotch: plan.kind.s1Rules && leftOfNotch(attemptJudged))
                environment.evidence.record("attempt.judged", ["oracle": "\(record.oracle)", "class": AttemptJudge.classify(record).rawValue])
                records.append(record)
                observationJudged += attemptJudged
            }
            let record = AttemptJudge.observation(records, timedOut: raw.timedOut, baseline: baseline.resolution.status)
            environment.evidence.record("observation", ["outcome": record.outcome.rawValue, "cause": record.cause?.rawValue ?? "", "attempts": record.attempts])
            return ObservationRun(record: record, judged: observationJudged)
        }
        return JudgedMeasurement(baseline: Array(judged.prefix(baseline.taken.count)), observations: observations)
    }

    /// Q8: one sample with every member and visible helper `drawn(full)`.
    func takeControl(_ phase: String) -> Taken? {
        probe.take(phase, notBefore: max(environment.clock.now(), lastChange + cadence.settle))
    }

    func judgeControl(_ taken: Taken) -> ControlRun {
        let leftmost = probe.visible.compactMap { taken.timed.sample.itemFrames[$0]?.minX }.min()
        let judged = probe.judge([taken], canonical: [], leftmost: leftmost)[0]
        return ControlRun(judged: judged, passed: probe.controlPassed(judged))
    }

    func control(_ phase: String) -> ControlRun? {
        takeControl(phase).map(judgeControl)
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

    /// Q8: rest control, push to `length`, a measurement, collapse, restore control; then everything judged in order.
    func cycle(_ length: Double) -> CycleRun? {
        guard environment.menus.stillInPlace(), let restTaken = takeControl("rest control") else { return nil }
        setLength(length)
        guard let measurement = measure(observations: cadence.observationsPerCycle) else { return nil }
        rest()
        guard let restoreTaken = takeControl("restore control") else { return nil }

        let restControl = judgeControl(restTaken)
        let judged = judge(measurement)
        let restoreControl = judgeControl(restoreTaken)
        let controlsPassed = CycleRules.controlsHeld(rest: (restControl.passed, restControl.judged.state),
                                                     restore: (restoreControl.passed, restoreControl.judged.state), holds: [judged.holdState])
        let records = judged.observations.map(\.record)
        let anyLeft = plan.kind.s1Rules && leftOfNotch([restControl.judged, restoreControl.judged] + judged.baseline)
        let run = CycleRun(record: CycleRecord(observations: records, controlMiss: !controlsPassed),
                           claimGranted: measurement.observations.contains { $0.attempts.contains { $0.claim.granted } },
                           controlsPassed: controlsPassed, measurements: measurement.baseline.resolution.measurements,
                           noGo: anyLeft || records.contains { $0.outcome == .noGo })
        environment.evidence.record("cycle", ["length": length, "controlsPassed": controlsPassed, "noGo": run.noGo,
                                              "observations": records.map { $0.outcome.rawValue }])
        return run
    }
}
