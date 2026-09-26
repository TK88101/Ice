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

    /// Rework #7b: now that G1 is fixed (`C1Discoverer` composes
    /// `ownRead: .ok`), a plain clean bar no longer fails `prepare()` at
    /// all, so this scenario needs its own dedicated, G1-independent way
    /// to force a benign "prepare comes back not ready" -- see
    /// `FakeBarWorld.injectPrepareRejection`'s own doc comment. G2's own
    /// finding (crosscheck-rework6.json #3) is that
    /// `waitForTeardownBaselineEquivalence` runs anyway once `ownerBaseline`
    /// is non-nil, and always fails, because `seedBaselines()` -- the only
    /// place that sets `baselineIndicatorFrame`/`ownerBaselineReadings` --
    /// never ran before the abort. That turns a correct INCONCLUSIVE into a
    /// wrong, final SAFETY STOP NEEDING ATTENTION.
    @Test("G2: step 3's prepare comes back not ready on an otherwise clean bar -> INCONCLUSIVE, no teardown mismatch, all three helpers reaped")
    func prepareNotReadyOnCleanBarIsInconclusive() {
        let world = FakeBarWorld(injectPrepareRejection: true)
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
    /// The change never recovers, so teardown's own equivalence check sees
    /// the same wrong glyph again: Amendment v5's escalation rule raises the
    /// earlier stop to needing attention, while the first terminal reason
    /// stays the stop itself (a reset-check failure or an owner-miss trip).
    @Test("G3: a baseline-static owner item whose appearance changes after baseline -> SAFETY STOP, escalated at teardown")
    func staticOwnerAppearanceChangeTripsSafetyStop() {
        let world = FakeBarWorld()
        world.arm(.ownerAppearanceChangesLater)
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.lastVerdict() == "safetyStopNeedingAttention")
        let firstReason = run.evidence.terminalReasons().first ?? ""
        #expect(firstReason.contains("resetCheckFailed") || firstReason.contains("ownerItemMissing"))
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }

    // MARK: - G3: a single weak/ambiguous match never trips by itself

    /// Rework #7a's own brief asked for this case and it was not written:
    /// section 4's own trip condition is a templated owner item read
    /// `notDrawn` (absent) or off its baseline x in a stable capture --
    /// never a merely weak or ambiguous single-capture match
    /// (crosscheck-rework6.json finding 1's corrected fix, item 2). A
    /// one-off glitch that recovers on its very next capture must not
    /// stop the run.
    @Test("G3: a single weak/ambiguous match of a static owner item in one capture that recovers next does not trip by itself")
    func singleWeakOwnerMatchDoesNotTripAlone() {
        let world = FakeBarWorld()
        world.arm(.ownerWeakMatchOnce)
        let run = I7.run(world: world)

        #expect(run.evidence.lastVerdict() == "pass")
        #expect(run.code == 0)
    }

    // MARK: - G6: freshness enforced immediately before every verify

    /// Rework #7a's own brief asked for this case and it was not written:
    /// the refresh regression half -- a plain, clean bar's first cycle
    /// (nothing measured yet, `initialCycleDurationEstimateSeconds`) must
    /// still actually re-prepare before its own verify age would pass
    /// `BaselineReuse.maxAge - baselineRefreshMarginSeconds`, and no verify
    /// call is ever refused as stale on an unmodified bar.
    @Test("G6: the proactive per-cycle refresh actually re-prepares on a plain clean bar, and no verify is ever refused as stale")
    func proactiveRefreshHappensOnCleanBar() {
        let world = FakeBarWorld()
        let run = I7.run(world: world)

        #expect(run.evidence.lastVerdict() == "pass")
        let refreshCount = run.evidence.allRecords().filter { $0.kind == "baseline.refreshed" }.count
        #expect(refreshCount >= 1)
        #expect(!run.evidence.allRecords().contains { $0.kind == "verify.refused.baselineStale" })
    }

    /// The enforced-guard half: a cycle that unexpectedly takes far longer
    /// internally than the proactive per-cycle prediction ever accounted
    /// for (`.hugeAgeJumpBeforeVerify`, armed before any refresh prediction
    /// this run would otherwise need) still reaches a stale `prepared` by
    /// the time it verifies -- only the newly enforced per-verify guard
    /// catches it, refusing the verify and ending the run through the
    /// normal teardown as INCONCLUSIVE (an incomplete scan), never a
    /// verdict built on stale data.
    @Test("G6: a verify with age >= 600 s is refused even when the proactive refresh already ran clean this cycle -> INCONCLUSIVE through teardown")
    func staleVerifyIsRefusedEvenAfterAProactiveRefreshPassed() {
        let world = FakeBarWorld()
        world.arm(.hugeAgeJumpBeforeVerify(seconds: 700))
        let run = I7.run(world: world)

        #expect(run.code == 2)
        #expect(run.evidence.lastVerdict()?.hasPrefix("inconclusive") == true)
        #expect(run.evidence.allRecords().contains { $0.kind == "verify.refused.baselineStale" })
        #expect(run.evidence.lastVerdict() != "safetyStop")
        #expect(run.evidence.lastVerdict() != "safetyStopNeedingAttention")
    }

    // MARK: - G8: a slow-discovery bar ends INCONCLUSIVE before the watchdog

    /// Rework #7a's own brief asked for this case and it was not written:
    /// FINDINGS.md's own "~290 ms with a stuck accessory process" --
    /// against the same realistic bar as scenario 1 (1 templated + 4
    /// untemplated owner items, so every latched capture also pays a
    /// keyed-discovery pass), the run would otherwise take about 21 min
    /// and get killed by the 20-minute watchdog mid-run, SAFETY STOP
    /// NEEDING ATTENTION. The budget guard (G8) must instead see this
    /// coming and end the run cleanly, through the normal teardown, as
    /// INCONCLUSIVE, well before the watchdog would ever fire.
    @Test("G8: a bar with 290 ms discovery passes ends INCONCLUSIVE through the budget guard, before the watchdog")
    func slowDiscoveryEndsInconclusiveBeforeWatchdog() {
        let world = FakeBarWorld(untemplatedOwnerCount: 4, discoverySecondsOverride: 0.29)
        let start = world.clock.now()
        let run = I7.run(world: world)
        let elapsedSeconds = world.clock.now() - start

        #expect(run.evidence.lastVerdict()?.hasPrefix("inconclusive") == true)
        #expect(run.evidence.lastVerdict() != "safetyStop")
        #expect(run.evidence.lastVerdict() != "safetyStopNeedingAttention")
        #expect(run.evidence.allRecords().contains { $0.kind == "budget.exceeded" })
        // Comfortably inside the 20-minute watchdog -- the whole point of
        // ending here instead of being killed by it.
        #expect(elapsedSeconds <= StageC1.watchdogMinutes * 60)
    }

    // MARK: - G4: a post-rest fold read that closes before the reset check

    /// Rework #7a's own brief asked for this case and it was not written:
    /// a chevron present only in `StageC1Cycle.runCycle`'s post-rest
    /// `readFoldValue` read (after `confirmRestSettled`'s own settled read,
    /// before the reset check's) must trip the latch there and then, not
    /// merely lower `otherChecksPassed` (crosscheck-rework6.json finding 2).
    @Test("G4: a chevron present only in the post-rest fold read -> SAFETY STOP foldAppeared")
    func postRestFoldReadTripsSafetyStop() {
        let world = FakeBarWorld()
        world.arm(.foldOnlyAtPostRestRead)
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.terminalReasons().first?.contains("foldAppeared") == true)
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }

    // MARK: - G5 off-main: non-blocking quit request only

    /// Rework #7a's own brief asked for this case and it was not written.
    /// `.captureFailure`'s very first failing capture lands inside
    /// `readTarget()`'s own `verifyOnce()` call -- `FakePump.blocking`
    /// bridges into `HidingVerification.verify(...)` through
    /// `Task.detached`, so the trip this capture failure causes fires off
    /// the thread that called `stage.run()`. G5 requires that an off-main
    /// terminal response send only `rest` and a *non-blocking* quit
    /// request (`FakeHelperControl.requestQuit()`, logged
    /// `"\(role).quitRequested"`), never the blocking `quit()`
    /// (`"\(role).quit"`) -- the main-thread teardown that follows still
    /// reaps for real afterward, so both a `.quitRequested` and a later
    /// `.quit` entry are expected for target/spacer, in that order.
    @Test("G5 off-main: a trip that fires off the caller's thread sends rest and a non-blocking quit request first, never a blocking quit")
    func offMainTripSendsNonBlockingQuitFirst() {
        let world = FakeBarWorld()
        world.arm(.captureFailure)
        let run = I7.run(world: world)

        #expect(run.code == 3)
        let log = world.commandLog
        for role in ["target", "spacer"] {
            guard let requestedIndex = log.firstIndex(of: "\(role).quitRequested") else {
                Issue.record("expected a non-blocking \"\(role).quitRequested\" before any blocking \"\(role).quit\" -- log: \(log)")
                continue
            }
            if let blockingIndex = log.firstIndex(of: "\(role).quit") {
                #expect(requestedIndex < blockingIndex, "the non-blocking request must precede the main-thread teardown's own blocking quit for \(role)")
            }
        }
        // Protected is never reached by either quitAll variant (F2, staged
        // teardown) -- no off-main path may quit it early.
        #expect(!log.contains("protected.quitRequested"))
    }
}
