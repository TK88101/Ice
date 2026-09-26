// I7 (Amendment v5/v6): the real `StageC1` orchestration, through the real
// pixel pipeline (`Ink`/`TemplateMatcher`/`CaptureStability`/
// `VisibilityObserver`/`HidingVerification`), driven against a synthesized
// fake bar (`FakeBarWorld`) with every live seam faked (`FakeC1Environment.swift`)
// and an injected virtual clock -- no real sleep, no screen, no
// Accessibility. Required before the one live run (Amendment v5); this
// file covers scenarios 1, 1b, 2 and 5. Scenarios 3/4/6 (the phase-armed
// latch triggers, teardown escalation, and a signal during setup) are
// `I7FaultTriggerTests.swift`.
import C1Stage
import Foundation
import Testing

@Suite("I7 -- C1 stage orchestration against a fake bar (clean/provisional paths)", .serialized)
struct I7OrchestrationTests {
    // MARK: - Scenario 1: a realistic clean bar -> PASS

    /// Amendment v6 / crosscheck #0: `readFoldValue`'s reset-check fold
    /// read uses every `ownerItemIDs` key -- templated and untemplated --
    /// as its `CaptureStability` reference set. `CaptureStability.isStable`
    /// requires a template for *every* reference, so any untemplated owner
    /// item (four here, matching the owner's own recorded 1-accepted/
    /// 4-rejected preflights) makes `referencesStable` false on every
    /// sample, `FoldWitness` reads `.unreadable`, and the very first reset
    /// check (scan.600) reports `foldNotAbsent` -> `resetCheckFailed` ->
    /// SAFETY STOP, not PASS. This scenario asserts the spec's own PASS --
    /// it is expected to fail today for exactly that reason.
    @Test("1: a realistic clean bar (1 templated + 4 untemplated owner items) -> PASS, no baselineStale, duration under the watchdog")
    func scenario1_realisticCleanBarPass() {
        let world = FakeBarWorld(templatedOwnerPresent: true, untemplatedOwnerCount: 4)
        let start = world.clock.now()
        let run = I7.run(world: world)
        let elapsedSeconds = world.clock.now() - start
        // Always printed, whether or not the run reached PASS -- the RED
        // report reads this to say where (in simulated time) the run
        // actually stopped.
        let refreshCount = run.evidence.allRecords().filter { $0.kind == "baseline.refreshed" }.count
        print("I7 scenario 1: simulated duration \(elapsedSeconds) s, code \(run.code), verdict \(run.evidence.lastVerdict() ?? "<none>"), first terminal reason \(run.evidence.terminalReasons().first ?? "<none>"), F3 re-prepares: \(refreshCount)")

        #expect(run.code == 0)
        #expect(run.evidence.lastVerdict() == "pass")
        #expect(!run.evidence.terminalReasons().contains { $0.contains("baselineStale") })
        // Amendment v6's own run-time bullet: the watchdog is 15 min, with
        // an explicit 3 min margin.
        #expect(elapsedSeconds <= 12 * 60)
        // Scenario 6 (Amendment v5): the fake's own helper lifecycle and
        // Protected reference were actually exercised, not bypassed -- all
        // three helpers launched (their commands appear) and were quit at
        // teardown, and the spacer actually received real `length`
        // commands (the scan actually ran) before its final `rest`.
        #expect(world.commandLog.contains { $0.hasPrefix("spacer.length ") })
        #expect(world.commandLog.contains("protected.quit"))
        #expect(world.commandLog.contains("spacer.quit"))
        #expect(world.commandLog.contains("target.quit"))
        #expect(run.caffeinate.startCount == 1)
        #expect(run.caffeinate.stopCount >= 1)
    }

    // MARK: - Scenario 1b: no templated owner item at all -> PASS

    /// Crosscheck #1/#18: with zero templated owner items,
    /// `readFoldForTeardown` returns `.unreadable` unconditionally (its own
    /// `genuineOwnerIDs` guard). This scenario never reaches teardown
    /// today (the reset check at scan.600 fails first, same as scenario 1
    /// -- #0's bug does not require a templated owner item to exist; an
    /// empty reference set is exactly as unreadable as a mismatched one).
    @Test("1b: the no-templated-owner bar, clean -> PASS")
    func scenario1b_noTemplatedOwnerCleanBarPass() {
        let world = FakeBarWorld(templatedOwnerPresent: false, untemplatedOwnerCount: 4)
        let run = I7.run(world: world)

        #expect(run.code == 0)
        #expect(run.evidence.lastVerdict() == "pass")
    }

    // MARK: - Scenario 1c: a transient unstable pair right after a collapse

    /// F4 (Amendment v6, crosscheck #3): `settledPairedRead` used to feed
    /// `captureFailed` on *any* unstable pair, tripping the latch on a
    /// transient (e.g. the spacer still animating back right after a
    /// collapse) that the rest-confirmation retry loop's own 10 s budget
    /// was meant to absorb. The fix separates an absent observation (a
    /// real capture/AX failure, still an immediate abort) from a
    /// successful-but-unstable one, which now only records
    /// `pairedRead.unstable` and retries.
    @Test("1c: a transient unstable pair right after a collapse settles before the 10 s deadline -> the run continues and ends PASS")
    func scenario1c_transientUnstablePairThenStablePass() {
        let world = FakeBarWorld()
        world.arm(.transientUnstableRestOnce)
        let run = I7.run(world: world)

        #expect(run.code == 0)
        #expect(run.evidence.lastVerdict() == "pass")
        #expect(run.evidence.terminalReasons().isEmpty)
        #expect(run.evidence.allRecords().contains { $0.kind == "pairedRead.unstable" })
    }

    // MARK: - Scenario 2: Target never hides -> PROVISIONAL FAIL

    /// Kept on the plain (single templated owner, no untemplated) bar,
    /// deliberately: with the untemplated cluster present, defect #0 fires
    /// at the very first reset check regardless of Target's own state,
    /// which would only re-report #0 under a different scenario name. This
    /// isolates "Target never hides" from #0's unrelated reset-check bug,
    /// matching the brief's "keep the existing 1/2/5 semantics."
    @Test("2: Target stays drawn through every scanned length -> PROVISIONAL FAIL")
    func scenario2_targetNeverHidesProvisionalFail() {
        let world = FakeBarWorld()
        world.setTargetNeverHides(true)
        let run = I7.run(world: world)

        #expect(run.code == 1)
        #expect(run.evidence.lastVerdict()?.hasPrefix("provisionalFail") == true)
    }

    // MARK: - Scenario 5: --dry sends no length, never PASS

    /// Also kept on the plain bar for the same reason as scenario 2.
    @Test("5: --dry sends no length and, on a clean bar, ends PROVISIONAL FAIL -- never PASS")
    func scenario5_dryRunSendsNoLengthNeverPasses() {
        let world = FakeBarWorld()
        let run = I7.run(world: world, dry: true)

        #expect(!world.commandLog.contains { $0.hasPrefix("spacer.length ") })
        #expect(run.code != 0)
        #expect(run.evidence.lastVerdict() != "pass")
        #expect(run.evidence.lastVerdict()?.hasPrefix("provisionalFail") == true)
    }
}
