import C1Core
import Testing
@testable import C1Live

/// The Codex-review P0s (round 1, docs/plans/2026-09-26-c1-protocol.md
/// Amendment v4): a trip must synchronously enter a terminal state (P0-3),
/// forbid any later reset, and the cleanup it triggers must fire exactly
/// once however many exit paths reach it (P0-5). Pure state, no real
/// helpers or screen -- the live files (`StageC1*.swift`) only adapt this.
@Suite("C1StageMachine")
struct C1StageMachineTests {
    @Test("a fresh machine is not terminal, has no expansion window open, and allows a reset")
    func freshMachine() {
        let machine = C1StageMachine()
        #expect(machine.isTerminal == false)
        #expect(machine.expansionWindowOpen == false)
        #expect(machine.canReset)
    }

    @Test("trip() enters the terminal state with the trip's own reason")
    func tripEntersTerminal() {
        var machine = C1StageMachine()
        _ = machine.trip(.protectedMissing)
        #expect(machine.isTerminal)
        #expect(machine.terminalReason == .latchTrip(.protectedMissing))
    }

    // MARK: - Items 1/9: safetyStop is part of the machine's own locked
    // state, set atomically with `terminalReason` -- by the time a caller
    // observes `isTerminal == true` (necessarily after the same
    // `trip()`/`watchdogFired()`/etc. call that set it), `safetyStop` is
    // already set too. There is no window where accounting could read
    // `isTerminal` true and `safetyStop` nil.

    @Test("a latch trip sets safetyStop to .stop, atomically with terminalReason")
    func tripSetsSafetyStopToStop() {
        var machine = C1StageMachine()
        _ = machine.trip(.protectedMissing)
        #expect(machine.safetyStop == .stop)
    }

    @Test("the watchdog sets safetyStop to .needingAttention")
    func watchdogSetsSafetyStopToNeedingAttention() {
        var machine = C1StageMachine()
        _ = machine.watchdogFired()
        #expect(machine.safetyStop == .needingAttention)
    }

    @Test("a teardown reap failure sets safetyStop to .needingAttention")
    func teardownReapFailedSetsSafetyStopToNeedingAttention() {
        var machine = C1StageMachine()
        _ = machine.teardownReapFailed()
        #expect(machine.safetyStop == .needingAttention)
    }

    @Test("item 7: a reset-check failure is terminal, immediately, with safetyStop .stop")
    func resetCheckFailedIsTerminal() {
        var machine = C1StageMachine()
        let actions = machine.resetCheckFailed()
        #expect(machine.isTerminal)
        #expect(machine.terminalReason == .resetCheckFailed)
        #expect(machine.safetyStop == .stop)
        #expect(actions == [.sendRest, .quitAllHelpers, .reapHelpers, .stopCaffeinate])
    }

    @Test("safetyStop is nil before any terminal event")
    func safetyStopNilBeforeTerminal() {
        let machine = C1StageMachine()
        #expect(machine.safetyStop == nil)
    }

    @Test("a second terminal event never overwrites the first's safetyStop")
    func secondTerminalEventNeverOverwritesSafetyStop() {
        var machine = C1StageMachine()
        _ = machine.trip(.protectedMissing)
        _ = machine.watchdogFired()
        #expect(machine.safetyStop == .stop)
    }

    @Test("item 1: a teardown mismatch (a non-empty helper domain, or the bar not baseline-equivalent after teardown) is also terminal, through the machine, needing attention")
    func teardownMismatchIsTerminal() {
        var machine = C1StageMachine()
        let actions = machine.teardownMismatch()
        #expect(machine.isTerminal)
        #expect(machine.terminalReason == .teardownMismatch)
        #expect(machine.safetyStop == .needingAttention)
        #expect(actions == [.sendRest, .quitAllHelpers, .reapHelpers, .stopCaffeinate])
    }

    @Test("rework #5 item 4: a teardown mismatch after an earlier trip escalates safetyStop from .stop to .needingAttention, keeps the trip's own terminalReason, and runs no new cleanup actions")
    func teardownMismatchAfterATripEscalates() {
        var machine = C1StageMachine()
        _ = machine.trip(.protectedMissing)
        #expect(machine.safetyStop == .stop)

        let actions = machine.teardownMismatch()
        #expect(actions == [])
        #expect(machine.terminalReason == .latchTrip(.protectedMissing))
        #expect(machine.safetyStop == .needingAttention)
    }

    @Test("rework #5 item 4: a teardown reap failure after an earlier reset-check failure escalates the same way")
    func teardownReapFailedAfterAResetCheckFailureEscalates() {
        var machine = C1StageMachine()
        _ = machine.resetCheckFailed()
        #expect(machine.safetyStop == .stop)

        let actions = machine.teardownReapFailed()
        #expect(actions == [])
        #expect(machine.terminalReason == .resetCheckFailed)
        #expect(machine.safetyStop == .needingAttention)
    }

    @Test("rework #5 item 4: a teardown mismatch after the watchdog (already .needingAttention) changes nothing further")
    func teardownMismatchAfterWatchdogStaysNeedingAttention() {
        var machine = C1StageMachine()
        _ = machine.watchdogFired()
        let actions = machine.teardownMismatch()
        #expect(actions == [])
        #expect(machine.terminalReason == .watchdog)
        #expect(machine.safetyStop == .needingAttention)
    }

    @Test("trip() returns the cleanup actions in order: rest, quit, reap, stop caffeinate")
    func tripReturnsCleanupActions() {
        var machine = C1StageMachine()
        let actions = machine.trip(.protectedMissing)
        #expect(actions == [.sendRest, .quitAllHelpers, .reapHelpers, .stopCaffeinate])
    }

    @Test("a second trip (or watchdog, or teardown-reap-failed) after the first is a no-op: no new actions, the first reason stands")
    func secondTerminalEventIsANoOp() {
        var machine = C1StageMachine()
        _ = machine.trip(.protectedMissing)
        let secondActions = machine.trip(.ownerItemMissing("owner-1"))
        #expect(secondActions == [])
        #expect(machine.terminalReason == .latchTrip(.protectedMissing))

        let watchdogActions = machine.watchdogFired()
        #expect(watchdogActions == [])
        #expect(machine.terminalReason == .latchTrip(.protectedMissing))
    }

    @Test("watchdogFired() enters terminal with .watchdog and runs cleanup")
    func watchdogEntersTerminal() {
        var machine = C1StageMachine()
        let actions = machine.watchdogFired()
        #expect(machine.isTerminal)
        #expect(machine.terminalReason == .watchdog)
        #expect(actions == [.sendRest, .quitAllHelpers, .reapHelpers, .stopCaffeinate])
    }

    @Test("teardownReapFailed() enters terminal with .teardownReapFailed")
    func teardownReapFailedEntersTerminal() {
        var machine = C1StageMachine()
        _ = machine.teardownReapFailed()
        #expect(machine.terminalReason == .teardownReapFailed)
    }

    @Test("cleanup() fires its actions only once however many exit paths call it (P0-5)")
    func cleanupIsIdempotent() {
        var machine = C1StageMachine()
        let first = machine.cleanup()
        let second = machine.cleanup()
        let third = machine.cleanup()
        #expect(first == [.sendRest, .quitAllHelpers, .reapHelpers, .stopCaffeinate])
        #expect(second == [])
        #expect(third == [])
    }

    @Test("cleanup() before any trip does not itself mark the machine terminal")
    func cleanupAloneIsNotATerminalEvent() {
        var machine = C1StageMachine()
        _ = machine.cleanup()
        #expect(machine.isTerminal == false)
    }

    @Test("a trip after an earlier plain cleanup() still runs cleanup's actions only once total")
    func tripAfterPlainCleanupDoesNotRepeatActions() {
        var machine = C1StageMachine()
        _ = machine.cleanup()
        let actions = machine.trip(.protectedMissing)
        #expect(actions == [])
        #expect(machine.isTerminal)
    }

    @Test("canReset is false once terminal -- section 4/P0-3: no reset survives a trip")
    func canResetFalseOnceTerminal() {
        var machine = C1StageMachine()
        #expect(machine.canReset)
        _ = machine.trip(.residualInkChanged)
        #expect(machine.canReset == false)
    }

    @Test("beginExpansion opens the window; endExpansion(restConfirmed: true) closes it")
    func expansionWindowOpensAndCloses() {
        var machine = C1StageMachine()
        machine.beginExpansion()
        #expect(machine.expansionWindowOpen)
        let actions = machine.endExpansion(restConfirmed: true)
        #expect(machine.expansionWindowOpen == false)
        #expect(actions == [])
        #expect(machine.isTerminal == false)
    }

    @Test("endExpansion(restConfirmed: true) is safe to call when the window was never opened")
    func endExpansionWithoutBeginIsSafe() {
        var machine = C1StageMachine()
        _ = machine.endExpansion(restConfirmed: true)
        #expect(machine.expansionWindowOpen == false)
    }

    // MARK: - Round 4 item 1: rest confirmation fails closed

    @Test("endExpansion(restConfirmed: false) does NOT close the window, and goes terminal instead")
    func endExpansionRestNotConfirmedStaysOpenAndGoesTerminal() {
        var machine = C1StageMachine()
        machine.beginExpansion()
        let actions = machine.endExpansion(restConfirmed: false)
        #expect(machine.expansionWindowOpen) // never closed -- "never close the window and continue"
        #expect(machine.isTerminal)
        #expect(machine.terminalReason == .restNotConfirmed)
        #expect(machine.safetyStop == .stop)
        #expect(actions == [.sendRest, .quitAllHelpers, .reapHelpers, .stopCaffeinate])
    }

    @Test("endExpansion(restConfirmed: false) after the window was never opened still goes terminal")
    func endExpansionRestNotConfirmedWithoutBeginStillGoesTerminal() {
        var machine = C1StageMachine()
        _ = machine.endExpansion(restConfirmed: false)
        #expect(machine.isTerminal)
        #expect(machine.terminalReason == .restNotConfirmed)
    }

    @Test("endExpansion(restConfirmed: false) is a no-op if the machine is already terminal from something else")
    func endExpansionRestNotConfirmedAfterAlreadyTerminalIsANoOp() {
        var machine = C1StageMachine()
        _ = machine.trip(.protectedMissing)
        let actions = machine.endExpansion(restConfirmed: false)
        #expect(actions == [])
        #expect(machine.terminalReason == .latchTrip(.protectedMissing)) // the first reason stands
    }

    @Test("withExpansion sends length, runs body, and always collapses on exit -- a normal return")
    func withExpansionCollapsesOnNormalReturn() {
        let channel = FakeC1HelperChannel()
        let driver = C1ExpansionDriver(channel: channel, dry: false)
        var machine = C1StageMachine()
        let result = machine.withExpansion(driver: driver, to: 650) { 42 }
        #expect(result == 42)
        #expect(channel.commands == [.length(650), .rest])
        #expect(machine.expansionWindowOpen == false)
    }

    @Test("withExpansion still collapses when body returns nil (an early-abort path with no trip) -- P0-4")
    func withExpansionCollapsesOnEarlyAbort() {
        let channel = FakeC1HelperChannel()
        let driver = C1ExpansionDriver(channel: channel, dry: false)
        var machine = C1StageMachine()
        let result: Int? = machine.withExpansion(driver: driver, to: 650) { nil }
        #expect(result == nil)
        #expect(channel.commands == [.length(650), .rest])
    }

    @Test("withExpansion under --dry never sends length or rest, but still tracks the window")
    func withExpansionUnderDrySendsNothing() {
        let channel = FakeC1HelperChannel()
        let driver = C1ExpansionDriver(channel: channel, dry: true)
        var machine = C1StageMachine()
        _ = machine.withExpansion(driver: driver, to: 650) { 1 }
        #expect(channel.commands.isEmpty)
        #expect(machine.expansionWindowOpen == false)
    }
}
