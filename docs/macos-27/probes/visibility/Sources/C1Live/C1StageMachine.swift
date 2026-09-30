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
}

/// Why the run became terminal (P0-3).
public enum C1TerminalReason: Equatable, Sendable {
    case latchTrip(LatchTrip)
    case watchdog
    case teardownReapFailed
    /// Item 7 (Codex round 2): section 5's reset check (baseline
    /// equivalence) failing is itself an immediate safety stop, not a
    /// flag that lets the current cycle or a later scan length continue.
    case resetCheckFailed
    /// Item 1: teardown's own discoveries -- a helper preference domain
    /// that is not empty or not readable, or the bar not
    /// baseline-equivalent within teardown's 30 s window -- also go
    /// through the machine rather than a separate stage-level flag.
    case teardownMismatch
    /// Round 4 item 1: the post-collapse settled read did not confirm
    /// the spacer back at rest (an unstable/unreadable pair, or the
    /// spacer not read back as drawn at its own baseline) -- fails
    /// closed, immediately, rather than closing the window and letting
    /// the next cycle continue on an unconfirmed premise.
    case restNotConfirmed
    /// Rework #5 item 8 (r5b item 8, P0): Ctrl-C, `kill` or a closed
    /// terminal -- its own terminal reason, distinct from `.watchdog`
    /// (the two are different events, however similar their cleanup), and
    /// itself needing the owner's attention like a watchdog fire, never a
    /// plain `.stop`.
    case signal
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
    /// Items 1/9 (Codex round 2): part of the machine's own state, set in
    /// the same assignment that sets `terminalReason` -- a caller that
    /// only ever reads `isTerminal`/`terminalReason`/`safetyStop` through
    /// one lock (as `StageC1` does) can never observe `isTerminal == true`
    /// with `safetyStop == nil`. `RunAccounting.Input.safetyStop` reads
    /// this value alone, never a copy the stage keeps separately.
    public private(set) var safetyStop: RunAccounting.SafetyStop?
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

    /// Item 8: a signal is its own terminal event too, ending in the same
    /// terminal safety teardown a trip or the watchdog does.
    @discardableResult
    public mutating func signalReceived() -> [C1StageAction] {
        enterTerminal(.signal)
    }

    /// P0-6: a teardown reap that never confirms is a safety stop needing
    /// the owner's attention, not a silent PASS. Rework #5 item 4 (r5b item
    /// 4, P0): if a trip or another safety stop already made this run
    /// terminal, this raises `safetyStop` from `.stop` to
    /// `.needingAttention` instead of being silently swallowed by
    /// `enterTerminal`'s own "already terminal" guard -- the first
    /// `terminalReason` still stands, and cleanup does not run twice.
    @discardableResult
    public mutating func teardownReapFailed() -> [C1StageAction] {
        guard isTerminal else { return enterTerminal(.teardownReapFailed) }
        escalateToNeedingAttentionIfStopped()
        return []
    }

    /// Item 7: a reset-check (baseline-equivalence) failure is itself an
    /// immediate safety stop -- section 5 states this as unconditional,
    /// not a flag the run carries while continuing.
    @discardableResult
    public mutating func resetCheckFailed() -> [C1StageAction] {
        enterTerminal(.resetCheckFailed)
    }

    /// Item 1: teardown's own mismatch (a non-empty/unreadable helper
    /// domain, or the bar not baseline-equivalent within 30 s). Item 4:
    /// escalates like `teardownReapFailed()` above when this run already
    /// stopped for another reason.
    @discardableResult
    public mutating func teardownMismatch() -> [C1StageAction] {
        guard isTerminal else { return enterTerminal(.teardownMismatch) }
        escalateToNeedingAttentionIfStopped()
        return []
    }

    /// Item 4: a teardown mismatch or failed reap discovered after an
    /// earlier `.stop` is itself a reason the owner needs to look --
    /// escalation only ever raises severity, never lowers it, and never
    /// touches `terminalReason` (the first trip/failure that actually
    /// caused this run to stop is still what gets reported).
    private mutating func escalateToNeedingAttentionIfStopped() {
        guard safetyStop == .stop else { return }
        safetyStop = .needingAttention
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

    /// Round 4 item 1: closes the expansion window only when
    /// `restConfirmed` is true (a settled, bracketed read genuinely
    /// showed the spacer back at rest) -- idempotent, safe whether or not
    /// the window was ever opened, and safe to call again after a trip
    /// already closed it in spirit (G-a: the fold is only watched for
    /// while this is closed).
    ///
    /// `restConfirmed == false` fails closed: the window is left exactly
    /// as it was (still open, if it was) and the run goes terminal --
    /// there is no "close and continue" from an unconfirmed rest. This is
    /// itself a terminal event like `trip`/`resetCheckFailed`, so it also
    /// runs cleanup and publishes `safetyStop` atomically.
    @discardableResult
    public mutating func endExpansion(restConfirmed: Bool) -> [C1StageAction] {
        guard restConfirmed else {
            return enterTerminal(.restNotConfirmed)
        }
        expansionWindowOpen = false
        return []
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
            // This generic, single-threaded convenience has no rest-read
            // of its own to confirm against, so it always reports
            // confirmed -- a real stage instead calls
            // `endExpansion(restConfirmed:)` directly with its own
            // settled read's result (see `StageC1.withExpansionWindow`).
            endExpansion(restConfirmed: true)
        }
        return body()
    }

    /// P0-5: the one idempotent emergency cleanup for every exit after
    /// setup starts -- rest, quit and reap the helpers. Fires its actions
    /// only the first time it is called; every later call (from any exit
    /// path, or a second terminal event) returns `[]`.
    ///
    /// G5 (Amendment v7, crosscheck-rework6.json finding 3/5): `caffeinate`
    /// is deliberately not one of these actions any more -- it used to
    /// stop here, the instant *any* terminal event fired (a trip, the
    /// watchdog, a signal, a teardown mismatch), which is before every
    /// screen read that still has to run and decide the verdict (the
    /// staged teardown's Protected-only fold read, the 30 s owner-population
    /// equivalence loop). Section 2 says caffeinate exists so "the display
    /// does not sleep mid-run," and those teardown reads are still part of
    /// the run. It is now stopped exactly once, in `StageC1.finish(_:)`
    /// (after every verdict-deciding read, on every exit path) and in the
    /// watchdog/signal backstop (`recordWatchdogBackstopVerdict()`), never
    /// here.
    @discardableResult
    public mutating func cleanup() -> [C1StageAction] {
        guard !cleanupRan else { return [] }
        cleanupRan = true
        return [.sendRest, .quitAllHelpers, .reapHelpers]
    }

    /// Items 1/9/7: `isTerminal`, `terminalReason` and `safetyStop` are set
    /// together, before `cleanup()` (and its potentially slow reap) even
    /// starts -- publication is complete the instant this method returns.
    private mutating func enterTerminal(_ reason: C1TerminalReason) -> [C1StageAction] {
        guard !isTerminal else { return [] }
        isTerminal = true
        terminalReason = reason
        safetyStop = Self.safetyStop(for: reason)
        return cleanup()
    }

    private static func safetyStop(for reason: C1TerminalReason) -> RunAccounting.SafetyStop {
        switch reason {
        case .latchTrip, .resetCheckFailed, .restNotConfirmed:
            return .stop
        case .watchdog, .teardownReapFailed, .teardownMismatch, .signal:
            return .needingAttention
        }
    }
}
