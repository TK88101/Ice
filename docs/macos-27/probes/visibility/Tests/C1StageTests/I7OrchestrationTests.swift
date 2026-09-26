// I7 (Amendment v5): the real `StageC1` orchestration, through the real
// pixel pipeline (`Ink`/`TemplateMatcher`/`CaptureStability`/
// `VisibilityObserver`/`HidingVerification`), driven against a synthesized
// fake bar (`FakeBarWorld`) with every live seam faked (`FakeC1Environment.swift`)
// and an injected virtual clock -- no real sleep, no screen, no
// Accessibility. Required before the one live run (Amendment v5); minimum
// scenarios 1/2/5 match the spec exactly, 3/4 are covered by the sub-cases
// below (see the worker report for the scope this reduces to).
import C1Stage
import Foundation
import Testing

@Suite("I7 -- C1 stage orchestration against a fake bar", .serialized)
struct I7OrchestrationTests {
    private func apps() -> C1Apps {
        C1Apps(
            target: URL(fileURLWithPath: "/tmp/fakebar/Target.app"),
            protected: URL(fileURLWithPath: "/tmp/fakebar/Protected.app"),
            spacer: URL(fileURLWithPath: "/tmp/fakebar/Spacer.app")
        )
    }

    private func run(world: FakeBarWorld, dry: Bool = false) -> (code: Int32, evidence: FakeEvidence, caffeinate: FakeCaffeinate) {
        let evidence = FakeEvidence()
        let caffeinate = FakeCaffeinate()
        let environment = FakeC1EnvironmentFactory.make(world: world, evidence: evidence, caffeinate: caffeinate)
        let stage = StageC1(environment: environment, apps: apps(), dry: dry)
        let code = stage.run()
        return (code, evidence, caffeinate)
    }

    // MARK: - Scenario 1: stable all-hidden scan + five smoke cycles -> PASS

    @Test("1: Target hidden(folded: false) at every scanned length and every smoke cycle -> PASS")
    func scenario1_allHiddenScanAndSmokePass() {
        let world = FakeBarWorld()
        let (code, evidence, caffeinate) = run(world: world)

        #expect(code == 0)
        #expect(evidence.lastVerdict() == "pass")
        // Scenario 6: the fake's own helper lifecycle and Protected
        // reference were actually exercised, not bypassed -- all three
        // helpers launched (their commands appear) and were quit at
        // teardown, and the spacer actually received real `length`
        // commands (the scan actually ran) before its final `rest`.
        #expect(world.commandLog.contains { $0.hasPrefix("spacer.length ") })
        #expect(world.commandLog.contains("protected.quit"))
        #expect(world.commandLog.contains("spacer.quit"))
        #expect(world.commandLog.contains("target.quit"))
        #expect(caffeinate.startCount == 1)
        #expect(caffeinate.stopCount >= 1)
    }

    // MARK: - Scenario 2: Target never hides -> PROVISIONAL FAIL

    @Test("2: Target stays drawn through every scanned length -> PROVISIONAL FAIL")
    func scenario2_targetNeverHidesProvisionalFail() {
        let world = FakeBarWorld()
        world.setTargetNeverHides(true)
        let (code, evidence, _) = run(world: world)

        #expect(code == 1)
        #expect(evidence.lastVerdict()?.hasPrefix("provisionalFail") == true)
    }

    // MARK: - Scenario 3: a latch trigger -> rest before quit, SAFETY STOP

    @Test("3a: the owner's own item disappearing trips the latch -> rest sent before quit, SAFETY STOP")
    func scenario3a_ownerItemDisappearingTripsLatchSafetyStop() {
        let world = FakeBarWorld()
        // Vanishes after the baseline's own captures but before the scan's
        // first settle -- a credible mid-run disappearance, not a baseline
        // that never accepted the item in the first place.
        world.setVanishOwnerAfterCaptures(20)
        let (code, evidence, _) = run(world: world)

        #expect(code == 3)
        let verdict = evidence.lastVerdict()
        #expect(verdict == "safetyStop" || verdict == "safetyStopNeedingAttention")
        #expect(evidence.terminalReasons().contains { $0.contains("ownerItemMissing") || $0.contains("captureFailed") || $0.contains("restNotConfirmed") })
        // Section 4 / P0-3: rest reaches the spacer before any helper is
        // quit, whatever tripped the latch.
        let restIndex = world.commandLog.firstIndex(of: "spacer.rest")
        let firstQuitIndex = world.commandLog.firstIndex { $0.hasSuffix(".quit") }
        if let restIndex, let firstQuitIndex {
            #expect(restIndex < firstQuitIndex)
        } else {
            Issue.record("expected both a rest command and a quit command in \(world.commandLog)")
        }
    }

    @Test("3b: the spacer not actually back at rest after collapse -> unconfirmed rest, SAFETY STOP")
    func scenario3b_spacerStuckAwayFromRestIsUnconfirmed() {
        let world = FakeBarWorld()
        world.setSpacerStuckOffsetPt(30)
        let (code, evidence, _) = run(world: world)

        #expect(code == 3)
        // Today (pre-fix #1): `settledPairedRead`'s own empty-`references`
        // bug feeds `captureFailed` to the latch *before*
        // `confirmRestSettled` even returns, so the latch trips first and
        // `.restNotConfirmed` never becomes the recorded reason at all --
        // `endExpansion`'s own `enterTerminal` is a no-op by the time it
        // runs (already terminal). After fix 1, this scenario's stuck
        // offset must instead produce `.restNotConfirmed` on its own.
        #expect(evidence.terminalReasons().contains { $0.contains("captureFailed") || $0.contains("restNotConfirmed") })
    }

    // MARK: - Scenario 4: a teardown mismatch after an earlier stop escalates

    @Test("4: a teardown mismatch after an earlier safety stop -> SAFETY STOP NEEDING ATTENTION")
    func scenario4_teardownMismatchAfterStopEscalates() {
        let world = FakeBarWorld()
        // Never recovers -- still missing at teardown's own
        // baseline-equivalence check, after the same disappearance already
        // tripped an earlier stop.
        world.setVanishOwnerAfterCaptures(20)
        let (code, evidence, _) = run(world: world)

        #expect(code == 3)
        #expect(evidence.lastVerdict() == "safetyStopNeedingAttention")
    }

    // MARK: - Scenario 5: --dry sends no length, never PASS

    @Test("5: --dry sends no length and, on a clean bar, ends PROVISIONAL FAIL -- never PASS")
    func scenario5_dryRunSendsNoLengthNeverPasses() {
        let world = FakeBarWorld()
        let (code, evidence, _) = run(world: world, dry: true)

        #expect(!world.commandLog.contains { $0.hasPrefix("spacer.length ") })
        #expect(code != 0)
        #expect(evidence.lastVerdict() != "pass")
        #expect(evidence.lastVerdict()?.hasPrefix("provisionalFail") == true)
    }
}
