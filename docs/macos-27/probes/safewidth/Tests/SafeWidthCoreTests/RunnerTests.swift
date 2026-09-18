import Testing
@testable import SafeWidthCore

// MARK: - Fixtures

private func defaultSignature() -> Signature {
    Signature(markers: ["P": .unique(Span(lo: 10, hi: 20))], itemOffsets: [:])
}

private func sample(_ length: Double = 100, tag: Double = 0) -> LegSample {
    LegSample(length: length, target: .visible(x: 500 + tag))
}

private func assessment(
    time: Double,
    decision: GuardDecision = .clean(info: []),
    signature: Signature = defaultSignature(),
    length: Double = 100,
    frontmostOK: Bool = true,
    helpersAlive: Bool = true,
    pillAXPresent: Bool? = nil,
    sampleTag: Double? = nil
) -> Assessment {
    Assessment(
        time: time,
        decision: decision,
        signature: signature,
        sample: sample(length, tag: sampleTag ?? time),
        frontmostOK: frontmostOK,
        helpersAlive: helpersAlive,
        pillAXPresent: pillAXPresent
    )
}

private func config(
    captureInterval: Double = 1.0,
    settleSpan: Double = 1.0,
    settleTolerance: Double = 0.5,
    settleTimeout: Double = 10.0,
    restoreTimeout: Double = 5.0,
    maxCaptureFailures: Int = 3
) -> RunnerConfig {
    RunnerConfig(
        captureInterval: captureInterval,
        settleSpan: settleSpan,
        settleTolerance: settleTolerance,
        settleTimeout: settleTimeout,
        restoreTimeout: restoreTimeout,
        maxCaptureFailures: maxCaptureFailures
    )
}

/// A scripted `World`: returns assessments from a fixed list in order (nil entries
/// simulate a failed capture), and advances its own fake clock only via `pause` and
/// (when a capture succeeded) by snapping to that capture's own scripted time.
private final class FakeWorld: World {
    private var clock: Double
    private var script: [Assessment?]
    private var index = 0

    private(set) var setSpacerLog: [Double?] = []
    private(set) var pauseLog: [Double] = []
    private(set) var assessLengthLog: [Double?] = []

    init(start: Double = 0, script: [Assessment?]) {
        self.clock = start
        self.script = script
    }

    func now() -> Double { clock }

    func setSpacer(_ length: Double?) {
        setSpacerLog.append(length)
    }

    func assess(length: Double?) -> Assessment? {
        assessLengthLog.append(length)
        precondition(index < script.count, "FakeWorld script exhausted")
        let result = script[index]
        index += 1
        if let result {
            clock = result.time
        }
        return result
    }

    func pause(_ seconds: Double) {
        pauseLog.append(seconds)
        clock += seconds
    }
}

// MARK: - Settling

@Suite("Runner.probe settling")
struct RunnerSettlingTests {
    @Test("settles after two matching captures spanning the settle span, and leaves the spacer expanded")
    func settlesAndLeavesSpacerExpanded() {
        let world = FakeWorld(script: [
            assessment(time: 0),
            assessment(time: 1),
        ])
        let runner = Runner(world: world, config: config())
        let outcome = runner.probe(length: 100, pillAtStart: nil)

        #expect(outcome == .settled(sample: sample(100, tag: 1), holds: []))
        #expect(world.setSpacerLog == [100])
    }

    @Test("a differing capture restarts the settle run, which then settles once the restarted run spans the span")
    func restartsThenSettlesLater() {
        let sigA = defaultSignature()
        let sigB = Signature(markers: ["P": .unique(Span(lo: 100, hi: 110))], itemOffsets: [:])
        let world = FakeWorld(script: [
            assessment(time: 0, signature: sigA),
            assessment(time: 1, signature: sigB),
            assessment(time: 2, signature: sigB),
        ])
        let runner = Runner(world: world, config: config(settleTimeout: 100))
        let outcome = runner.probe(length: 100, pillAtStart: nil)

        #expect(outcome == .settled(sample: sample(100, tag: 2), holds: []))
    }

    @Test("never settling by the settle timeout ends the probe unsettled with the spacer rested")
    func timesOutUnsettledAndRestsSpacer() {
        let los = [10.0, 10.4, 10.8, 11.2, 11.6]
        let script: [Assessment?] = los.enumerated().map { i, lo in
            assessment(
                time: Double(i),
                signature: Signature(markers: ["P": .unique(Span(lo: lo, hi: lo + 10))], itemOffsets: [:])
            )
        }
        let world = FakeWorld(script: script)
        let runner = Runner(world: world, config: config(settleSpan: 10, settleTimeout: 4))
        let outcome = runner.probe(length: 100, pillAtStart: nil)

        #expect(outcome == .unsettled(sample: sample(100, tag: 4)))
        #expect(world.setSpacerLog == [100, nil])
        #expect(world.pauseLog == [1, 1, 1, 1])
    }

    @Test("slow drift that never exceeds tolerance against its immediate neighbour, but always exceeds it against the run's fixed reference, ends the probe unsettled")
    func slowDriftNeverSettles() {
        // Each step drifts 0.3 from its predecessor (within the 0.5 tolerance),
        // so a detector that compared only to the previous capture would never
        // restart and would settle once 2+ captures spanned the 2s span; the
        // correct, reference-anchored detector instead keeps restarting and
        // never settles before the 4s timeout.
        let los = [10.0, 10.3, 10.6, 10.9, 11.2]
        let script: [Assessment?] = los.enumerated().map { i, lo in
            assessment(
                time: Double(i),
                signature: Signature(markers: ["P": .unique(Span(lo: lo, hi: lo + 10))], itemOffsets: [:])
            )
        }
        let world = FakeWorld(script: script)
        let runner = Runner(world: world, config: config(settleSpan: 2, settleTimeout: 4))
        let outcome = runner.probe(length: 100, pillAtStart: nil)

        #expect(outcome == .unsettled(sample: sample(100, tag: 4)))
        #expect(world.setSpacerLog == [100, nil])
    }
}

// MARK: - Guard decisions

@Suite("Runner.probe guard decisions")
struct RunnerGuardTests {
    @Test("a restore decision rests the spacer and reports restored=true once a clean capture follows within the restore timeout")
    func harmRestoredTrue() {
        let world = FakeWorld(script: [
            assessment(time: 0, decision: .restore(reasons: [.protectedLost])),
            assessment(time: 0.5, decision: .clean(info: [])),
        ])
        let runner = Runner(world: world, config: config())
        let outcome = runner.probe(length: 100, pillAtStart: nil)

        #expect(outcome == .harm(length: 100, reasons: [.protectedLost], restored: true))
        #expect(world.setSpacerLog == [100, nil])
        #expect(world.assessLengthLog == [100, nil])
    }

    @Test("a restore decision reports restored=false when no clean capture arrives within the restore timeout")
    func harmRestoredFalse() {
        let world = FakeWorld(script: [
            assessment(time: 0, decision: .restore(reasons: [.protectedLost])),
            assessment(time: 0, decision: .suspect(reasons: [.itemUnverifiable(id: "x")])),
            assessment(time: 1, decision: .suspect(reasons: [.itemUnverifiable(id: "x")])),
        ])
        let runner = Runner(world: world, config: config(restoreTimeout: 2))
        let outcome = runner.probe(length: 100, pillAtStart: nil)

        #expect(outcome == .harm(length: 100, reasons: [.protectedLost], restored: false))
        #expect(world.setSpacerLog == [100, nil])
    }

    @Test("a stop decision rests the spacer and returns immediately without waiting to restore")
    func stopReturnsImmediately() {
        let world = FakeWorld(script: [
            assessment(time: 0, decision: .stop(reasons: [.itemUnverifiable(id: "y")])),
        ])
        let runner = Runner(world: world, config: config())
        let outcome = runner.probe(length: 100, pillAtStart: nil)

        #expect(outcome == .stop(reasons: [.itemUnverifiable(id: "y")]))
        #expect(world.setSpacerLog == [100, nil])
        #expect(world.assessLengthLog == [100])
    }
}

// MARK: - Void reasons

@Suite("Runner.probe void reasons")
struct RunnerVoidTests {
    @Test("frontmost lost voids the probe and rests the spacer")
    func voidFocusLost() {
        let world = FakeWorld(script: [assessment(time: 0, frontmostOK: false)])
        let runner = Runner(world: world, config: config())
        #expect(runner.probe(length: 100, pillAtStart: nil) == .void(.focusLost))
        #expect(world.setSpacerLog == [100, nil])
    }

    @Test("a dead helper voids the probe")
    func voidHelperDied() {
        let world = FakeWorld(script: [assessment(time: 0, helpersAlive: false)])
        let runner = Runner(world: world, config: config())
        #expect(runner.probe(length: 100, pillAtStart: nil) == .void(.helperDied))
        #expect(world.setSpacerLog == [100, nil])
    }

    @Test("the pill toggling relative to pillAtStart voids the probe")
    func voidPillToggled() {
        let world = FakeWorld(script: [assessment(time: 0, pillAXPresent: false)])
        let runner = Runner(world: world, config: config())
        #expect(runner.probe(length: 100, pillAtStart: true) == .void(.pillToggled))
        #expect(world.setSpacerLog == [100, nil])
    }

    @Test("focusLost takes precedence over helperDied when both are true")
    func voidPrecedenceFocusBeforeHelpers() {
        let world = FakeWorld(script: [assessment(time: 0, frontmostOK: false, helpersAlive: false)])
        let runner = Runner(world: world, config: config())
        #expect(runner.probe(length: 100, pillAtStart: nil) == .void(.focusLost))
        #expect(world.setSpacerLog == [100, nil])
    }

    @Test("helperDied takes precedence over pillToggled when both are true")
    func voidPrecedenceHelpersBeforePill() {
        let world = FakeWorld(script: [assessment(time: 0, helpersAlive: false, pillAXPresent: false)])
        let runner = Runner(world: world, config: config())
        #expect(runner.probe(length: 100, pillAtStart: true) == .void(.helperDied))
        #expect(world.setSpacerLog == [100, nil])
    }

    @Test("the pill check is skipped entirely when pillAtStart is nil")
    func pillCheckSkippedWhenNil() {
        // settleTimeout: 0 forces a deterministic .unsettled outcome on the very first
        // capture, proving the mismatched pill reading never voided the probe.
        let world = FakeWorld(script: [assessment(time: 0, pillAXPresent: false)])
        let runner = Runner(world: world, config: config(settleTimeout: 0))
        #expect(runner.probe(length: 100, pillAtStart: nil) == .unsettled(sample: sample(100, tag: 0)))
    }

    @Test("a non-matching pill reading proceeds normally to settle when pillAtStart matches")
    func pillCheckPassesWhenReadingMatchesStart() {
        let world = FakeWorld(script: [
            assessment(time: 0, pillAXPresent: true),
            assessment(time: 1, pillAXPresent: true),
        ])
        let runner = Runner(world: world, config: config())
        #expect(
            runner.probe(length: 100, pillAtStart: true)
                == .settled(sample: sample(100, tag: 1), holds: [])
        )
    }

    @Test("a nil AX pill reading voids the probe when pillAtStart expects a non-nil value")
    func pillCheckVoidsOnNilReadingAgainstNonNilStart() {
        let world = FakeWorld(script: [assessment(time: 0, pillAXPresent: nil)])
        let runner = Runner(world: world, config: config())
        #expect(runner.probe(length: 100, pillAtStart: false) == .void(.pillToggled))
    }

    @Test("the guard decision wins over a void in the same capture: a stop is reported as a stop")
    func guardDecisionPrecedesVoidOnStop() {
        let world = FakeWorld(script: [
            assessment(time: 0, decision: .stop(reasons: [.itemUnverifiable(id: "x")]), helpersAlive: false),
        ])
        let runner = Runner(world: world, config: config())
        #expect(runner.probe(length: 100, pillAtStart: nil) == .stop(reasons: [.itemUnverifiable(id: "x")]))
        #expect(world.setSpacerLog == [100, nil])
        #expect(world.assessLengthLog == [100])
    }

    @Test("the guard decision wins over a void in the same capture: harm is reported as harm")
    func guardDecisionPrecedesVoidOnHarm() {
        let world = FakeWorld(script: [
            assessment(time: 0, decision: .restore(reasons: [.protectedLost]), frontmostOK: false),
            assessment(time: 0.5, decision: .clean(info: [])),
        ])
        let runner = Runner(world: world, config: config())
        #expect(runner.probe(length: 100, pillAtStart: nil) == .harm(length: 100, reasons: [.protectedLost], restored: true))
        #expect(world.setSpacerLog == [100, nil])
    }
}

// MARK: - Capture failures

@Suite("Runner.probe capture failures")
struct RunnerCaptureFailureTests {
    @Test("capture failures below the limit are tolerated and the failure count resets on the next success")
    func captureFailuresBelowLimitRecover() {
        // Two failures, then a success (which must reset the failure count),
        // then two more failures. Without the reset, the second pair would push
        // the cumulative count to 3 = maxCaptureFailures and end the probe with
        // .captureFailure instead of letting it continue on to settle.
        let world = FakeWorld(script: [
            nil, nil,
            assessment(time: 2),
            nil, nil,
            assessment(time: 5),
            assessment(time: 6),
        ])
        let runner = Runner(world: world, config: config(settleTimeout: 100, maxCaptureFailures: 3))
        let outcome = runner.probe(length: 100, pillAtStart: nil)

        #expect(outcome == .settled(sample: sample(100, tag: 5), holds: []))
    }

    @Test("capture failures reaching the limit rest the spacer and report captureFailure")
    func captureFailuresAtLimit() {
        let world = FakeWorld(script: [nil, nil, nil])
        let runner = Runner(world: world, config: config(maxCaptureFailures: 3))
        let outcome = runner.probe(length: 100, pillAtStart: nil)

        #expect(outcome == .captureFailure)
        #expect(world.setSpacerLog == [100, nil])
        #expect(world.pauseLog == [1, 1])
    }

    @Test("when the spacer is already at rest, hitting the capture-failure limit does not emit a redundant setSpacer(nil)")
    func captureFailuresAtLimitWithNilLengthSkipsRedundantRest() {
        let world = FakeWorld(script: [nil, nil, nil])
        let runner = Runner(world: world, config: config(maxCaptureFailures: 3))
        let outcome = runner.rest(pillAtStart: nil)

        #expect(outcome == .captureFailure)
        #expect(world.setSpacerLog == [nil])
    }
}

// MARK: - Holds

@Suite("Runner.probe holds")
struct RunnerHoldTests {
    @Test("hold samples are recorded at the first assessment reaching each hold time, and one assessment can satisfy several holds at once")
    func holdsRecordedAcrossAssessments() {
        let world = FakeWorld(script: [
            assessment(time: 0),
            assessment(time: 1),
            assessment(time: 2, decision: .suspect(reasons: [.itemUnverifiable(id: "z")])),
        ])
        let runner = Runner(world: world, config: config(settleTimeout: 100))
        let outcome = runner.probe(length: 100, holds: [0.5, 1.5, 1.5], pillAtStart: nil)

        #expect(
            outcome == .settled(
                sample: sample(100, tag: 1),
                holds: [sample(100, tag: 1), sample(100, tag: 2), sample(100, tag: 2)]
            )
        )
    }

    @Test("the guard remains active while waiting for holds after settling, and can still abort the probe")
    func guardStillVetoesWhileWaitingForHolds() {
        let world = FakeWorld(script: [
            assessment(time: 0),
            assessment(time: 1),
            assessment(time: 2, decision: .restore(reasons: [.protectedLost])),
            assessment(time: 2.5, decision: .clean(info: [])),
        ])
        let runner = Runner(world: world, config: config(settleTimeout: 100, restoreTimeout: 5))
        let outcome = runner.probe(length: 100, holds: [2.0], pillAtStart: nil)

        #expect(outcome == .harm(length: 100, reasons: [.protectedLost], restored: true))
    }

    @Test("holds are recorded and returned in ascending time order, regardless of the order they were passed in")
    func holdsReturnedInAscendingOrderRegardlessOfInputOrder() {
        let world = FakeWorld(script: [
            assessment(time: 0),
            assessment(time: 1),
            assessment(time: 2),
            assessment(time: 3),
        ])
        let runner = Runner(world: world, config: config(settleTimeout: 100))
        let outcome = runner.probe(length: 100, holds: [3.0, 1.0], pillAtStart: nil)

        #expect(
            outcome == .settled(
                sample: sample(100, tag: 1),
                holds: [sample(100, tag: 1), sample(100, tag: 3)]
            )
        )
    }

    @Test("hold samples are recorded from t0 even before the probe has settled, using a >= boundary")
    func holdsRecordedBeforeSettlingAtBoundary() {
        let world = FakeWorld(script: [
            assessment(time: 0),
            assessment(time: 1),
        ])
        let runner = Runner(world: world, config: config())
        let outcome = runner.probe(length: 100, holds: [0, 1], pillAtStart: nil)

        // Hold 0 is satisfied by the very first (not-yet-settled) capture at t=0;
        // hold 1 is satisfied exactly at t=1, the boundary, which is also when
        // the probe settles.
        #expect(
            outcome == .settled(
                sample: sample(100, tag: 1),
                holds: [sample(100, tag: 0), sample(100, tag: 1)]
            )
        )
    }

    @Test("once settled, the probe stays settled even if later captures (while waiting for a hold) would otherwise look unsettled or timed out")
    func staysSettledWhileWaitingForLaterHolds() {
        let world = FakeWorld(script: [
            assessment(time: 0),
            assessment(time: 1),
            assessment(time: 2, signature: Signature(markers: ["P": .unique(Span(lo: 100, hi: 110))], itemOffsets: [:])),
            assessment(time: 3, signature: Signature(markers: ["P": .unique(Span(lo: 200, hi: 210))], itemOffsets: [:])),
            assessment(time: 4, signature: Signature(markers: ["P": .unique(Span(lo: 300, hi: 310))], itemOffsets: [:])),
        ])
        // settleTimeout: 2 means every capture from t=2 onward looks, in isolation,
        // like the overall timeout has elapsed without a currently-settled run; a
        // detector call that forgets the probe already settled at t=1 would report
        // .timedOut and incorrectly rest the spacer before the t=4 hold is reached.
        let runner = Runner(world: world, config: config(settleTimeout: 2))
        let outcome = runner.probe(length: 100, holds: [4], pillAtStart: nil)

        #expect(
            outcome == .settled(sample: sample(100, tag: 1), holds: [sample(100, tag: 4)])
        )
        #expect(world.setSpacerLog == [100])
    }

    @Test("a suspect capture is still fed to the settle detector and can restart the run")
    func suspectCaptureFeedsSettleDetector() {
        let sigA = defaultSignature()
        let sigB = Signature(markers: ["P": .unique(Span(lo: 100, hi: 110))], itemOffsets: [:])
        let world = FakeWorld(script: [
            assessment(time: 0, signature: sigA),
            assessment(time: 1, decision: .suspect(reasons: [.itemUnverifiable(id: "z")]), signature: sigB),
            assessment(time: 2, signature: sigA),
            assessment(time: 3, signature: sigA),
        ])
        // If the suspect capture at t=1 were not fed to the detector, the run
        // started at t=0 (sigA) would still be live and would settle as soon as
        // t=2's matching sigA capture spans the 1s settle span, giving tag 2
        // instead of tag 3.
        let runner = Runner(world: world, config: config())
        let outcome = runner.probe(length: 100, pillAtStart: nil)

        #expect(outcome == .settled(sample: sample(100, tag: 3), holds: []))
    }
}

// MARK: - rest()

@Suite("Runner.rest")
struct RunnerRestTests {
    @Test("rest(pillAtStart:) behaves exactly like probe(length: nil, holds: [], pillAtStart:)")
    func restBehavesLikeProbeWithNilLength() {
        let world = FakeWorld(script: [
            assessment(time: 0, length: 0),
            assessment(time: 1, length: 0),
        ])
        let runner = Runner(world: world, config: config())
        let outcome = runner.rest(pillAtStart: nil)

        #expect(outcome == .settled(sample: sample(0, tag: 1), holds: []))
        #expect(world.setSpacerLog == [nil])
        #expect(world.assessLengthLog == [nil, nil])
    }

    @Test("rest() reports harm with length nil and restored=true when a clean capture follows within the restore timeout")
    func restHarmRestoredTrue() {
        let world = FakeWorld(script: [
            assessment(time: 0, decision: .restore(reasons: [.protectedLost])),
            assessment(time: 0.5, decision: .clean(info: [])),
        ])
        let runner = Runner(world: world, config: config())
        let outcome = runner.rest(pillAtStart: nil)

        #expect(outcome == .harm(length: nil, reasons: [.protectedLost], restored: true))
        #expect(world.setSpacerLog == [nil])
    }

    @Test("rest() reports harm with length nil and restored=false when no clean capture arrives within the restore timeout")
    func restHarmRestoredFalse() {
        let world = FakeWorld(script: [
            assessment(time: 0, decision: .restore(reasons: [.protectedLost])),
            assessment(time: 0, decision: .suspect(reasons: [.itemUnverifiable(id: "x")])),
            assessment(time: 1, decision: .suspect(reasons: [.itemUnverifiable(id: "x")])),
        ])
        let runner = Runner(world: world, config: config(restoreTimeout: 2))
        let outcome = runner.rest(pillAtStart: nil)

        // A mutant that short-circuits to restored=true whenever length is nil
        // would pass restHarmRestoredTrue too, but fails here.
        #expect(outcome == .harm(length: nil, reasons: [.protectedLost], restored: false))
        #expect(world.setSpacerLog == [nil])
    }

    @Test("the restore-wait window starts when the spacer actually rests, not at the probe's own start time")
    func restoreWindowStartsAtRestTimeNotProbeStart() {
        let world = FakeWorld(script: [
            assessment(time: 5, decision: .restore(reasons: [.protectedLost])),
            assessment(time: 5.5, decision: .clean(info: [])),
        ])
        // t0 (probe start) is 0, but the harmful capture lands at t=5. A restore
        // window measured from t0 would already look expired against a 2s
        // restoreTimeout and would return restored=false without even trying a
        // restoration capture; measured correctly from t=5, it has the full
        // window and succeeds.
        let runner = Runner(world: world, config: config(restoreTimeout: 2))
        let outcome = runner.probe(length: 100, pillAtStart: nil)

        #expect(outcome == .harm(length: 100, reasons: [.protectedLost], restored: true))
        #expect(world.assessLengthLog == [100, nil])
    }
}

// MARK: - Invalid holds

@Suite("Runner.probe hold validation")
struct RunnerHoldValidationTests {
    // Without validation, a non-finite hold time never satisfies `a.time - t0
    // >= hold`, so the probe would keep capturing with the spacer expanded
    // forever instead of ever reporting a result. A NaN hold also sorts
    // unpredictably, which can block every hold after it. The contract prefers
    // a loud crash over that silent, indefinite hang.
    @Test("a NaN hold traps instead of hanging the probe")
    func nanHoldTraps() async {
        await #expect(processExitsWith: .failure) {
            let world = FakeWorld(script: [assessment(time: 0), assessment(time: 1)])
            let runner = Runner(world: world, config: config())
            _ = runner.probe(length: 100, holds: [.nan], pillAtStart: nil)
        }
    }

    @Test("an infinite hold traps instead of hanging the probe")
    func infiniteHoldTraps() async {
        await #expect(processExitsWith: .failure) {
            let world = FakeWorld(script: [assessment(time: 0), assessment(time: 1)])
            let runner = Runner(world: world, config: config())
            _ = runner.probe(length: 100, holds: [.infinity], pillAtStart: nil)
        }
    }

    @Test("a negative hold traps")
    func negativeHoldTraps() async {
        await #expect(processExitsWith: .failure) {
            let world = FakeWorld(script: [assessment(time: 0), assessment(time: 1)])
            let runner = Runner(world: world, config: config())
            _ = runner.probe(length: 100, holds: [-1.0], pillAtStart: nil)
        }
    }
}
