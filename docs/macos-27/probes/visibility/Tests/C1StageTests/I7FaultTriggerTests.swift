// I7 (Amendment v6): one test per section-4 latch trigger (crosscheck
// #13-#16's own corrected recommendation -- every knob armed by phase, via
// `FakeBarWorld.arm(_:afterNthLength:)`, never a raw capture count), plus
// the teardown escalation (scenario 4) and a signal during setup
// (scenario 6). Each scenario asserts the exact first terminal reason, the
// verdict, and (section 4 / P0-3) that `rest` reached the spacer before any
// helper was quit.
//
// Most scenarios here run on the *plain* bar (`FakeBarWorld()`, one
// templated owner item, no untemplated cluster): the untemplated cluster
// exists specifically to reproduce crosscheck #0/#1 (`I7OrchestrationTests`
// scenarios 1/1b), and every one of those scenarios' own reset checks fails
// for that unrelated reason before a scenario's own trigger ever gets to
// run its course. 3c/3d are the exception -- they are themselves about the
// untemplated cluster, so they carry their own small (2-item) one.
import C1Stage
import Foundation
import Testing

@Suite("I7 -- one test per section-4 latch trigger, plus escalation and a signal", .serialized)
struct I7FaultTriggerTests {
    // MARK: - 3a: templated owner item disappears, then returns before teardown

    /// Crosscheck #13/#14's own corrected fix: the control case that proves
    /// escalation (scenario 4), not a first-time teardown mismatch, is what
    /// turns a stop into "needing attention" -- the same trip, but the item
    /// is back by the time teardown's own baseline-equivalence check runs.
    @Test("3a: the templated owner item disappears and returns before teardown -> SAFETY STOP (not escalated)")
    func scenario3a_templatedOwnerVanishesAndReturns() {
        let world = FakeBarWorld()
        world.arm(.vanishTemplatedOwner(returnsAfterCaptures: 5))
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.terminalReasons().first?.contains("ownerItemMissing") == true)
        #expect(run.evidence.lastVerdict() == "safetyStop")
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }

    // MARK: - 3b: Protected disappears

    @Test("3b: Protected disappears -> SAFETY STOP (protectedMissing)")
    func scenario3b_protectedVanishes() {
        let world = FakeBarWorld()
        world.arm(.vanishProtected)
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.terminalReasons().first?.contains("protectedMissing") == true)
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }

    // MARK: - 3c: an untemplated owner item disappears

    /// G-b's own keyed watch (`UntemplatedOwnerWatch`/`LatchObservationMerge`):
    /// a missing untemplated item is folded into `missingOwnerItems`, the
    /// same trip reason a templated miss produces.
    @Test("3c: an untemplated owner item disappears (pixels + AX + discovery) -> SAFETY STOP")
    func scenario3c_untemplatedItemVanishes() {
        let world = FakeBarWorld(untemplatedOwnerCount: 2)
        world.arm(.vanishExtra(index: 0))
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.terminalReasons().first?.contains("ownerItemMissing") == true)
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }

    // MARK: - 3d: an untemplated owner item shifts

    @Test("3d: an untemplated owner item shifts more than 2 pt -> SAFETY STOP")
    func scenario3d_untemplatedItemShifts() {
        let world = FakeBarWorld(untemplatedOwnerCount: 2)
        world.arm(.shiftExtra(index: 0, byPt: 5))
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.terminalReasons().first?.contains("ownerItemMissing") == true)
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }

    // MARK: - 3e: a fold appears while at rest, no expansion in progress

    @Test("3e: a fold appears while the spacer is at rest -> SAFETY STOP (foldAppeared)")
    func scenario3e_foldWithoutExpansion() {
        let world = FakeBarWorld()
        world.arm(.foldWithoutExpansion)
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.terminalReasons().first?.contains("foldAppeared") == true)
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }

    // MARK: - 3f: capture returns nil

    @Test("3f: capture returns nil -> SAFETY STOP (captureFailed)")
    func scenario3f_captureFailure() {
        let world = FakeBarWorld()
        world.arm(.captureFailure)
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.terminalReasons().first?.contains("captureFailed") == true)
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }

    // MARK: - 3g: discovery blocks past the executor's bound

    /// Armed after the *second* `length` command: cycle 1's own preflight
    /// discovery fetch already ran before the first `length` was sent, so
    /// arming any earlier could not affect it. `C1DiscoveryExecutor`'s own
    /// bound is real wall-clock time (3.0 s), not this world's virtual
    /// clock (see `FaultKnob.discoveryHang`'s own doc comment) -- this test
    /// pays that real ~3 s.
    @Test("3g: discovery blocks past the executor's bound -> SAFETY STOP (captureFailed)")
    func scenario3g_discoveryTimeout() {
        let world = FakeBarWorld()
        world.arm(.discoveryHang, afterNthLength: 2)
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.terminalReasons().first?.contains("captureFailed") == true)
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }

    // MARK: - 3h: the spacer does not actually return to rest

    /// Crosscheck #15's own corrected fix: armed after the first `length`
    /// command, so the rest baseline (taken before any `length` is ever
    /// sent) records the spacer's *true* rest position -- only a rest
    /// *after* an expansion is offset, so `confirmRestSettled`'s own
    /// position check can actually fail, rather than the offset being
    /// baked into the baseline itself (which the pre-fix fixture did).
    ///
    /// A newly observed gap this scenario surfaces, distinct from #15's
    /// own fixture concern: `StageC1.withExpansionWindow`'s `defer` calls
    /// `endExpansion(restConfirmed:)` and then `perform(actions)`
    /// *directly* (StageC1.swift ~344-346) -- every other terminal path
    /// (`onLatchTrip`, `markResetCheckFailed`, the watchdog, a signal, a
    /// teardown mismatch/reap failure) instead goes through
    /// `handleTerminal(actions)`, which is the only place that writes the
    /// `"terminal"` evidence record. `RunAccounting` still reports the
    /// right verdict (`safetyStop`, read straight from the machine), but
    /// no `"terminal"` record with reason `restNotConfirmed` is ever
    /// written, so `evidence.terminalReasons()` -- and the real run's own
    /// evidence file -- never says why. Not one of crosscheck #0-#18; kept
    /// asserting the spec-correct expectation so this stays visible.
    @Test("3h: the spacer does not actually return to rest after collapse -> SAFETY STOP (restNotConfirmed)")
    func scenario3h_unconfirmedRest() {
        let world = FakeBarWorld()
        world.arm(.spacerStuckOffset(pt: 30))
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.terminalReasons().first?.contains("restNotConfirmed") == true)
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }

    // MARK: - 3i: reset-check failure (the helpers' own zero-tolerance drift)

    /// Not an *owner*-item drift (see `FakeBarWorld.spacerRenderXLocked`'s
    /// own doc comment for why that cannot isolate this from a latch
    /// trip): a small (0.5 pt), sub-`referenceTolerancePt` spacer offset,
    /// armed after the *second* `length` command so the first cycle's own
    /// reset check still passes clean against the true rest baseline, and
    /// only the second cycle's own rest is offset. `confirmRestSettled`
    /// still confirms the rest (within its own 1 pt tolerance), but the
    /// reset check's own helper condition (exact equality, no tolerance)
    /// then fails it.
    @Test("3i: the spacer rests 0.5 pt off its own baseline between cycles -> SAFETY STOP (resetCheckFailed)")
    func scenario3i_resetCheckFailsOnAnExactHelperMismatch() {
        let world = FakeBarWorld()
        world.arm(.spacerStuckOffset(pt: 0.5), afterNthLength: 2)
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.terminalReasons().first == "resetCheckFailed")
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }

    // MARK: - Scenario 4: a teardown mismatch after an earlier stop escalates

    /// Crosscheck #13's own corrected fix: the item stays gone through
    /// teardown (`returnsAfterCaptures: nil`), so the *same* trip that
    /// scenario 3a also produces now finds the owner still missing at
    /// teardown's own baseline-equivalence check, which escalates
    /// `.stop` to `.needingAttention` -- the trip is still the first
    /// recorded reason.
    @Test("4: a teardown mismatch after an earlier safety stop -> SAFETY STOP NEEDING ATTENTION, with the trip as the first reason")
    func scenario4_teardownMismatchAfterStopEscalates() {
        let world = FakeBarWorld()
        world.arm(.vanishTemplatedOwner(returnsAfterCaptures: nil))
        let run = I7.run(world: world)

        #expect(run.code == 3)
        #expect(run.evidence.terminalReasons().first?.contains("ownerItemMissing") == true)
        #expect(run.evidence.lastVerdict() == "safetyStopNeedingAttention")
        #expect(I7.restPrecedesFirstQuitAfterLastLength(world))
    }

    // MARK: - Scenario 6: a signal during setup

    /// Crosscheck #4/#5/#9/#10/#12 (Codex F5): `run()`'s setup steps never
    /// check `isTerminal` between helper launches, and the step2/step3
    /// abort path reports INCONCLUSIVE instead of reading `safetyStop` --
    /// so a signal that lands while the spacer is launching (Protected
    /// already up) does not stop Target (or even the spacer itself) from
    /// still being launched, and the recorded verdict is the wrong,
    /// re-runnable INCONCLUSIVE rather than a safety stop needing
    /// attention. The signal's own terminal-reason record is correct
    /// today (`handleTerminal` runs regardless); only the launch-continuation
    /// and the final verdict are wrong.
    @Test("6: a signal during setup -> no launch after the signal, needing attention, a recorded verdict")
    func scenario6_signalDuringSetupNeedsAttention() {
        let world = FakeBarWorld()
        let run = I7.run(world: world, signalDuringLaunchOfRole: "spacer")

        let launchedAfterSignal = run.evidence.allRecords().contains { $0.kind == "step2.launched" }
        #expect(!launchedAfterSignal, "no helper should launch once a signal has been received")
        #expect(run.evidence.terminalReasons().first == "signal")
        #expect(run.evidence.lastVerdict() == "safetyStopNeedingAttention")
        #expect(run.code == 3)
    }
}
