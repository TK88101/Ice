// Rework #7a (Amendment v7): new I7 scenarios for G2, G3 and G5. Every
// scenario here is written to the spec's own desired end state, not to
// today's code -- per the worker brief's "honest RED," each one is expected
// to fail today, and its own doc comment says which G item explains the
// failure, or (G5's) says why it does not. See `SEAM-AUDIT.md` and the
// worker report for the shared root cause (G1) most of these share.
import C1Stage
import Foundation
import Testing

@Suite("I7 -- Amendment v7 additions (G2, G3, G5)", .serialized)
struct I7AmendmentV7Tests {
    // MARK: - G2: a benign step-3 prepare failure must not become a teardown mismatch

    /// On today's code this is not a special case at all: G1 alone
    /// (`C1Discoverer` forwarding the raw discoverer's `ownRead: .notRead`
    /// unchanged) already makes step 3's `prepare()` return
    /// `.skip(.dividerUnavailable)` on *every* plain, clean `FakeBarWorld`,
    /// with no fault knob armed. The spec (section 1) treats this as
    /// INCONCLUSIVE, re-runnable up to twice; G2's own finding
    /// (crosscheck-rework6.json) is that `waitForTeardownBaselineEquivalence`
    /// runs anyway once `ownerBaseline` is non-nil, and always fails,
    /// because `seedBaselines()` -- the only place that sets
    /// `baselineIndicatorFrame`/`ownerBaselineReadings` -- never ran before
    /// the abort. That turns a correct INCONCLUSIVE into a wrong, final
    /// SAFETY STOP NEEDING ATTENTION. Expected RED today for both G1 (the
    /// abort itself) and G2 (the wrong verdict it produces).
    @Test("G2: step 3's prepare comes back not ready on an otherwise clean bar -> INCONCLUSIVE, no teardown mismatch, all three helpers reaped")
    func prepareNotReadyOnCleanBarIsInconclusive() {
        let world = FakeBarWorld()
        let run = I7.run(world: world)

        #expect(run.evidence.allRecords().contains { $0.kind == "step3.prepareFailed" })
        #expect(run.evidence.lastVerdict()?.hasPrefix("inconclusive") == true)
        #expect(!run.evidence.allRecords().contains { $0.kind == "teardown.baselineEquivalent" && ($0.fields["matched"] as? Bool) == false })
        #expect(world.commandLog.contains("protected.quit"))
        #expect(world.commandLog.contains("spacer.quit"))
        #expect(world.commandLog.contains("target.quit"))
    }

    // MARK: - G5: caffeinate must outlive every verdict-deciding read

    /// Not blocked by G1: even a run that aborts at step 3 still runs the
    /// full staged teardown (F5), and that teardown's own reads (the
    /// Protected-only fold read, the 30 s owner-population equivalence
    /// loop) are real captures through `latchingCapturer` -- exactly the
    /// screen reads amendment v7's own caffeinate bullet is about. Today
    /// `C1StageMachine.cleanup()` still lists `.stopCaffeinate` as one of
    /// its four one-shot actions, and `runTeardownAndDecide` calls
    /// `runCleanup()` as its very first statement -- before any of those
    /// reads. Expected RED today for exactly that reason (G5); this
    /// scenario needs no fault knob and is not masked by G1/G2.
    @Test("G5: the fake caffeinate is still running at every capture the stage takes, and is stopped exactly once, only at the end")
    func caffeinateOutlivesEveryCapture() {
        let world = FakeBarWorld()
        let run = I7.run(world: world)

        let stoppedTooEarlyAt = run.caffeinate.captureRunningLog.firstIndex(of: false)
        #expect(stoppedTooEarlyAt == nil, "a capture ran with caffeinate already stopped, at position \(stoppedTooEarlyAt.map(String.init) ?? "?") of \(run.caffeinate.captureRunningLog.count) recorded captures")
        #expect(run.caffeinate.stopCount == 1)
    }

    // MARK: - G3: a dynamic templated owner item

    /// Blocked by G1/G2 today (see `prepareNotReadyOnCleanBarIsInconclusive`
    /// above): the run cannot reach a cycle at all, so it cannot reach the
    /// specific G3 code paths (`assessLatch`, `readFoldValue`,
    /// `performResetCheck`) this scenario is really about. Written to the
    /// spec's own desired behaviour regardless -- once G1/G2 are fixed,
    /// this is the scenario that will actually exercise G3's "a dynamic
    /// owner template must leave the pixel population" fix. The fixture
    /// mechanism itself (`dynamicTemplatedOwnerAtBaseline`) is independently
    /// checked in `FakeBarWorldFixtureTests.swift`, so a failure here is
    /// attributable to G1/G2/G3, not to the knob.
    @Test("G3: an owner template the baseline marks dynamic, which then redraws mid-run, still ends PASS")
    func dynamicOwnerTemplateRedrawingMidRunStillPasses() {
        let world = FakeBarWorld(dynamicTemplatedOwnerAtBaseline: true)
        let run = I7.run(world: world)

        #expect(run.evidence.lastVerdict() == "pass")
        #expect(run.code == 0)
    }

    // MARK: - G3: a baseline-static owner item that later changes appearance

    /// Same blocker as above. Distinct from `.vanishTemplatedOwner` (the
    /// item disappears): here it stays listed and drawn, just as a
    /// different glyph -- G3's own "a baseline-static item that later
    /// reads weak or ambiguous... stays a mismatch." Armed from the first
    /// `length` command, so the item reads as a normal static template at
    /// baseline (unlike the dynamic scenario above) and only changes once
    /// a cycle is under way.
    @Test("G3: a baseline-static owner item whose appearance changes after baseline -> SAFETY STOP")
    func staticOwnerAppearanceChangeTripsSafetyStop() {
        let world = FakeBarWorld()
        world.arm(.ownerAppearanceChangesLater)
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.lastVerdict() == "safetyStop")
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }
}
