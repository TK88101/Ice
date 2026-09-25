import C1Core

/// What the stage does in response to a terminal event or an ordinary
/// expansion collapse -- section 4's rest-then-quit, plus the reap and the
/// `caffeinate` stop the Codex review's P0-5 wants funnelled through one
/// idempotent cleanup. The stage (`StageC1*.swift`) is the only thing that
/// actually performs these; this type only decides which ones, when, and
/// once.
public enum C1StageAction: Equatable, Sendable {
    case sendRest
    case quitAllHelpers
    case reapHelpers
    case stopCaffeinate
}

/// Why the run became terminal (P0-3).
public enum C1TerminalReason: Equatable, Sendable {
    case latchTrip(LatchTrip)
    case watchdog
    case teardownReapFailed
}

/// The stage's own control-flow state (Amendment v4 / Codex review round
/// 1's P0s): a trip enters a terminal state synchronously, forbids any
/// later reset, and its cleanup fires exactly once no matter how many exit
/// paths reach it. Also tracks section 5 step 2's expansion window (G-a:
/// the fold is only a credible latch trip while this is closed). Pure
/// state -- no helpers, no screen, no channel of its own; the live files
/// hand its returned actions to the real `C1HelperChannel`/reap/caffeinate.
public struct C1StageMachine: Sendable {
    public private(set) var isTerminal = false
    public private(set) var terminalReason: C1TerminalReason?
    public private(set) var expansionWindowOpen = false
    private var cleanupRan = false

    public init() {}

    /// Section 4 / P0-3: a trip synchronously enters the terminal state,
    /// carrying its own reason, and runs cleanup. A trip once already
    /// terminal changes nothing -- the first reason stands.
    @discardableResult
    public mutating func trip(_ reason: LatchTrip) -> [C1StageAction] {
        enterTerminal(.latchTrip(reason))
    }

    /// The 15-minute watchdog (P1): also a terminal event, so the watchdog
    /// path ends in the same safety teardown a trip does, not a bare exit.
    @discardableResult
    public mutating func watchdogFired() -> [C1StageAction] {
        enterTerminal(.watchdog)
    }

    /// P0-6: a teardown reap that never confirms is a safety stop needing
    /// the owner's attention, not a silent PASS.
    @discardableResult
    public mutating func teardownReapFailed() -> [C1StageAction] {
        enterTerminal(.teardownReapFailed)
    }

    /// Section 4 / P0-3: "forbids any later reset" -- once terminal, the
    /// stage may never call `LatchingCapturer.resetAfterPassingCheck()`
    /// again.
    public var canReset: Bool { !isTerminal }

    /// Section 5 step 2's expansion scope: opened synchronously right
    /// before `length` is sent.
    public mutating func beginExpansion() {
        expansionWindowOpen = true
    }

    /// Closes the expansion window -- idempotent, safe whether or not it
    /// was ever opened, and safe to call again after a trip already closed
    /// it in spirit (G-a: the fold is only watched for while this is
    /// closed).
    public mutating func endExpansion() {
        expansionWindowOpen = false
    }

    /// P0-4: runs `body` with the expansion window open, `length` already
    /// sent (unless `--dry`), and guarantees `rest` on every exit --
    /// return, or `body` producing nothing to report. The latch's own
    /// trip (via `LatchingCapturer`, wired with the same `driver`'s
    /// channel) is still the *first*, synchronous responder to a
    /// disappearance; this is the scope's own backup for the exits a trip
    /// never causes, such as a plain verification skip.
    ///
    /// A caller that shares one `C1StageMachine` across threads (a real
    /// stage, guarding it with its own lock) cannot call this directly:
    /// `body` here is exactly where a trip's `onTrip` callback can fire
    /// back in, from a different thread than whichever one is running
    /// `body` -- holding that caller's lock across this whole call would
    /// deadlock the callback against it. Such a caller instead calls
    /// `beginExpansion()`/`endExpansion()` directly, each under its own
    /// short lock, around the same expand/body/defer-collapse shape (see
    /// `StageC1.withExpansionWindow`). This method stays correct and
    /// tested for a single-threaded caller, or one with its own
    /// reentrant-safe locking.
    public mutating func withExpansion<T>(driver: C1ExpansionDriver, to lengthPt: Double, _ body: () -> T) -> T {
        beginExpansion()
        driver.expand(to: lengthPt)
        defer {
            driver.collapse()
            endExpansion()
        }
        return body()
    }

    /// P0-5: the one idempotent emergency cleanup for every exit after
    /// setup starts -- rest, quit and reap the helpers, stop
    /// `caffeinate`. Fires its actions only the first time it is called;
    /// every later call (from any exit path, or a second terminal event)
    /// returns `[]`.
    @discardableResult
    public mutating func cleanup() -> [C1StageAction] {
        guard !cleanupRan else { return [] }
        cleanupRan = true
        return [.sendRest, .quitAllHelpers, .reapHelpers, .stopCaffeinate]
    }

    private mutating func enterTerminal(_ reason: C1TerminalReason) -> [C1StageAction] {
        guard !isTerminal else { return [] }
        isTerminal = true
        terminalReason = reason
        return cleanup()
    }
}
