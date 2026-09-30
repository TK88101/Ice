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
    ///
    /// Rework #7a (G1, G8): today the run cannot even reach that #0 defect.
    /// `FakeBarWorld.discoveryResult()` now honestly reads `ownRead:
    /// .notRead` (the raw live seam), and `C1Discoverer` forwards it
    /// unchanged (`Sources/C1Live/C1Discoverer.swift:57`), so step 3's
    /// `prepare()` returns `.skip(.dividerUnavailable)` and the run aborts
    /// there, long before the scan -- see `SEAM-AUDIT.md` and the worker
    /// report. This scenario still asserts the spec's own PASS and the
    /// v7-calibrated duration bound, unchanged: both remain the desired
    /// end state once rework #7b's `C1Discoverer` fix (and its own G2
    /// teardown fix) land.
    @Test("1: a realistic clean bar (1 templated + 4 untemplated owner items) -> PASS, no baselineStale, duration under the watchdog")
    func scenario1_realisticCleanBarPass() {
        let world = FakeBarWorld(templatedOwnerPresent: true, untemplatedOwnerCount: 4)
        let start = world.clock.now()
        let run = I7.run(world: world)
        let elapsedSeconds = world.clock.now() - start
        // Always printed, whether or not the run reached PASS -- the RED
        // report reads this to say where (in simulated time) the run
        // actually stopped. Per G8's own calibration (captureSeconds 0.03 s,
        // discoverySeconds 0.0365 s -- see `SimulatedLatency`'s own doc
        // comment), a *completed* run should print roughly 11 min; today,
        // blocked by G1/G2 at step 3, it prints only the setup's own cost.
        let refreshCount = run.evidence.allRecords().filter { $0.kind == "baseline.refreshed" }.count
        print("I7 scenario 1: simulated duration \(elapsedSeconds) s, code \(run.code), verdict \(run.evidence.lastVerdict() ?? "<none>"), first terminal reason \(run.evidence.terminalReasons().first ?? "<none>"), F3 re-prepares: \(refreshCount)")

        #expect(run.code == 0)
        #expect(run.evidence.lastVerdict() == "pass")
        #expect(!run.evidence.terminalReasons().contains { $0.contains("baselineStale") })
        // Amendment v7's own run-time bullet: the watchdog is 20 min
        // (`StageC1.watchdogMinutes` is still the pre-v7 15.0 in source --
        // that raise, paired with deriving the helper `--lifetime` from it
        // per G8, is one of rework #7b's own source fixes, not a test-only
        // change), with an explicit 3 min margin.
        #expect(elapsedSeconds <= 17 * 60)
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
    ///
    /// Rework #7a (Q-dry, the "dry rehearsal" the owner is asked to run
    /// immediately before the real one): Codex round 7b's own ruling
    /// recommends it, precisely because it exercises real owner-bar wiring
    /// a fake can miss -- G1 is exactly such a miss. This scenario now also
    /// asserts the dry-rehearsal gate's own three conditions (protocol
    /// Amendment v7's last bullet): no setup abort, no safety stop, an
    /// equivalent teardown. Blocked by G1/G2 today: the run aborts at step
    /// 3 and the teardown equivalence check can never pass (see
    /// `SEAM-AUDIT.md`), so all three new assertions are expected RED.
    @Test("5: --dry sends no length and, on a clean bar, ends PROVISIONAL FAIL -- never PASS")
    func scenario5_dryRunSendsNoLengthNeverPasses() {
        let world = FakeBarWorld()
        let run = I7.run(world: world, dry: true)

        #expect(!world.commandLog.contains { $0.hasPrefix("spacer.length ") })
        #expect(run.code != 0)
        #expect(run.evidence.lastVerdict() != "pass")
        #expect(run.evidence.lastVerdict()?.hasPrefix("provisionalFail") == true)

        // Q-dry's own gate: no setup abort (`step.abort`, the step0-step2
        // pre-launch failure path -- distinct from a step-3 prepare
        // failure, which is expected and does not block the gate), no
        // safety stop of either kind, and a teardown that actually matched.
        #expect(!run.evidence.allRecords().contains { $0.kind == "step.abort" })
        #expect(run.evidence.lastVerdict() != "safetyStop")
        #expect(run.evidence.lastVerdict() != "safetyStopNeedingAttention")
        #expect(run.evidence.allRecords().contains { $0.kind == "teardown.baselineEquivalent" && ($0.fields["matched"] as? Bool) == true })
    }
}
