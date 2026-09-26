// I5: `vizprobe c1` -- the C1 protocol (docs/plans/2026-09-26-c1-protocol.md,
// sections 2-5, Amendment v4/v5) as its own stage, independent of
// `StageRun`/`LiveRun` (the 2026-09-19/2026-09-23 plans' two-helper
// protocols): C1 launches three helpers in a fixed order (Protected, the
// spacer, Target), and every decision -- the scan plan, the preflight
// order/roster checks, baseline equivalence, the latch, the terminal
// state, the run's final verdict -- comes from C1Core (I1) through the
// tested seams in C1Live (I3/I4/I5's dry-run/trip sequencing, and the
// `C1StageMachine` state machine the Codex review's P0s asked for). This
// file holds setup, launch and the run driver; the scan and smoke cycle is
// `StageC1Cycle.swift`, teardown and accounting are `StageC1Teardown.swift`.
//
// Rework #5, step A: moved out of `Sources/vizprobe` into this library
// target so a test target can drive it (I7). Every live/AppKit/Accessibility
// dependency the old `Sources/vizprobe/StageC1.swift` had directly is now a
// field of `C1StageEnvironment`; `vizprobe c1` builds the one real
// environment (`Sources/vizprobe/StageC1Live.swift`) and constructs this
// type with it. No behaviour changed in this step.
import C1Core
import C1Live
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

/// Where build.sh's output apps directory holds the helper bundles.
/// `spacer` is a distinct bundle (`build.sh`'s `Spacer.app`), but Codex
/// review round 1 P0-1 found it carries the *same* bundle id as Protected
/// (the Twin precedent: a new id would leave a permanent entry in the
/// system's menu bar settings) -- so every role below is identified by the
/// pid `HelperControl` hands back and the AX identifier discovery reads,
/// never by bundle id.
public struct C1Apps: Sendable {
    public let target: URL
    public let protected: URL
    public let spacer: URL

    public init(target: URL, protected: URL, spacer: URL) {
        self.target = target
        self.protected = protected
        self.spacer = spacer
    }
}

/// Restated from `Sources/vizprobe/LiveRunTypes.swift`'s `HelperRole`
/// (internal to a different, executable target this library cannot depend
/// on) -- these two bundle ids must never drift from build.sh's own, and
/// build.sh is the single other place either string is spelled out.
public enum C1HelperRole {
    /// Reused from probes/safewidth's own swhelper on purpose: T13's DoD is
    /// that no new bundle id appears in the menu bar settings for the
    /// target or the reference (Opus P2-13).
    public static let target = "com.icespike4.target"
    /// The spacer (`build.sh`'s `Spacer.app`) carries this same id --
    /// P0-1. `all` is therefore only two distinct ids, not three.
    public static let protected = "com.icespike4.protected"
    public static let all = [target, protected]
}

/// A step's own verdict: continue, or the reason the whole run stops here.
/// Restated from `Sources/vizprobe/LiveRunTypes.swift` (internal to a
/// different, executable target) rather than imported.
enum StepResult {
    case ok
    case abort(String)
}

/// The spacer's own AX identifier (`SpacerItem.identifier` in
/// `Sources/vzhelper/main.swift`), restated here rather than imported: the
/// `vzhelper` executable target is not a library another target can
/// depend on.
public enum SpacerIdentifier {
    public static let value = "vz-spacer"
}

/// I5's channel: every command this stage sends a helper goes through here,
/// so `C1Live`'s tested pieces (`LatchingCapturer`, `C1ExpansionDriver`,
/// `C1StageMachine`) can drive the same real helpers the launch steps
/// started, and a fake can stand in for it in a test.
///
/// Item 2 (Codex round 2): built *before* any helper launches and
/// registered with each one as soon as its process actually starts --
/// `register(_:isSpacer:)`, not a constructor that only exists once all
/// three have succeeded. A failure discovering the spacer or Target must
/// still be able to quit and reap whatever already launched (Protected,
/// or Protected and the spacer); the old constructor-based channel had no
/// way to reach a helper that started but whose launch step had not yet
/// returned.
///
/// Step A: generalised to `any C1HelperControlling` (was the concrete
/// `HelperControl`), so a fake helper can register here exactly like a real
/// one.
public final class HelperControlChannel: C1HelperChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var helpers: [any C1HelperControlling] = []
    private var spacerHelperRef: (any C1HelperControlling)?
    private var protectedHelperRef: (any C1HelperControlling)?

    public init() {}

    /// Registers a helper the instant its process starts (P0-2/item 2),
    /// before this run waits for its `up` reply or discovers its item --
    /// so a launch failure right after this still has a way to quit it.
    public func register(_ helper: any C1HelperControlling, isSpacer: Bool = false, isProtected: Bool = false) {
        lock.withLock {
            helpers.append(helper)
            if isSpacer { spacerHelperRef = helper }
            if isProtected { protectedHelperRef = helper }
        }
    }

    public func sendLength(_ pt: Double) {
        (lock.withLock { spacerHelperRef })?.send("length \(pt)")
    }

    public func sendRest() {
        (lock.withLock { spacerHelperRef })?.send("rest")
    }

    /// F2 (Amendment v6, staged teardown): Target and the spacer only --
    /// Protected is deliberately excluded here (see `quitProtected()`), so
    /// every cleanup path that reaches this method (a trip's own I3
    /// response, the machine's one-shot `.quitAllHelpers` action, off-main
    /// or not) leaves Protected running for the staged fold read. Not
    /// itself a discovery-verified reap (section 2's "quits and reaps all
    /// three helpers and confirms none of their items is listed" is
    /// `StageC1.confirmReap()`/`confirmNonProtectedReap()`, which call
    /// this and then re-discover, checked against `C1ReapCheck` -- P0-6);
    /// a trip (I3) only needs the commands sent, synchronously, which is
    /// all this method promises.
    public func quitAll() {
        let snapshot: [any C1HelperControlling] = lock.withLock {
            helpers.filter { $0 !== protectedHelperRef }
        }
        for helper in snapshot { helper.quit() }
    }

    /// F2: Protected's own quit, kept separate so no path reaches it
    /// through `quitAll()`.
    public func quitProtected() {
        (lock.withLock { protectedHelperRef })?.quit()
    }

    /// G5 (Amendment v7): `quitAll()`'s own reach (Target and the spacer),
    /// through each helper's non-blocking `requestQuit()` instead.
    public func quitAllNonBlocking() {
        let snapshot: [any C1HelperControlling] = lock.withLock {
            helpers.filter { $0 !== protectedHelperRef }
        }
        for helper in snapshot { helper.requestQuit() }
    }
}

public final class StageC1 {
    /// G8 (Amendment v7): raised from 15 to 20 minutes, together with the
    /// helper lifetime derivation below -- both now derive from this one
    /// setting ("one effective configuration in main.swift/StageC1Live").
    public static let watchdogMinutes = 20.0
    /// F3 (Amendment v6): a conservative first estimate of one cycle's own
    /// wall time, used only before any cycle has completed (nothing
    /// measured yet). The recorded evidence from 20260925-145233-vzverify
    /// puts one verify at 7-9 s, and a full cycle (two verifies, the
    /// preflight, rest confirmation, the reset check, and every capture's
    /// own keyed-discovery overhead) at roughly 25-40 s -- this constant
    /// is deliberately larger than that measured range, never presented as
    /// measured itself.
    public static let initialCycleDurationEstimateSeconds = 90.0
    /// F3: the safety margin subtracted from `BaselineReuse.maxAge` before
    /// deciding whether to re-prepare -- larger than one worst-case cycle,
    /// per Codex's own correction to F3.
    public static let baselineRefreshMarginSeconds = 120.0
    /// G8 (Amendment v7, "time budget"): the fixed allowance the budget
    /// guard reserves for the staged teardown (reap, the Protected-only
    /// fold read up to 10 s, the 30 s owner-population equivalence loop,
    /// preference domains) -- deliberately larger than section 5 step 4's
    /// own nominal cost (crosscheck-rework6.json's own duration note puts
    /// teardown at about 6 s nominal).
    public static let budgetTeardownAllowanceSeconds = 45.0
    /// G8: the safety margin the budget guard subtracts from the watchdog
    /// before deciding whether the rest of the run still fits -- distinct
    /// from `baselineRefreshMarginSeconds` (F3's own, narrower margin
    /// against `BaselineReuse.maxAge`, not the watchdog).
    public static let budgetMarginSeconds = 60.0
    /// G8: the 120 s watchdog/signal backstop (`vizprobe/main.swift`'s own
    /// `asyncAfter(deadline: .now() + 120)`), restated here (like
    /// `SpacerIdentifier`/`C1HelperRole`) so the helper lifetime below can
    /// derive from the *same* number that file schedules the backstop
    /// with, without this library depending on that executable target.
    public static let watchdogBackstopSeconds = 120.0
    /// G8: a comfortable margin beyond watchdog + backstop, so a helper
    /// never self-exits (`vzhelper`'s own `--lifetime`) while the
    /// watchdog's own staged teardown could still legitimately be running.
    public static let helperLifetimeMarginSeconds = 180.0
    /// G8 ("the helpers' lifetime cap is derived from the same setting
    /// [the watchdog]: watchdog + backstop + margin"; crosscheck-rework6.json's
    /// own "Helper --lifetime 900 is fixed..." finding) -- replaces the old
    /// hard-coded `"900"` in `step2Launch`'s launch arguments. Capped at
    /// `vzhelper`'s own maximum (1800 s, `Sources/vzhelper/main.swift`) so
    /// a future watchdog raise cannot silently ask for more than a helper
    /// will ever accept.
    public static var effectiveHelperLifetimeSeconds: Double {
        min(1800, watchdogMinutes * 60 + watchdogBackstopSeconds + helperLifetimeMarginSeconds)
    }

    let apps: C1Apps
    let dry: Bool
    let environment: C1StageEnvironment
    /// Never read directly once `latchingCapturer` exists (P0-2: every
    /// post-channel capture goes through the latch first) -- everything
    /// downstream reads through `latchingCapturer` instead.
    var capturer: any StripCapturing { environment.capturer }
    let parameters = DetectorParameters.preRegistered
    let decision: MenuBarItemVisibility
    var discoverer: any Discovering { environment.discoverer }
    /// Item 8: "same bound for the keyed discovery reads used by the
    /// untemplated watch and preflight" -- `currentUntemplatedReadings()`
    /// and `passesPreflightOnce()`'s AX order fetch use this, never
    /// `discoverer` directly. Launch-time discovery keeps using
    /// `discoverer` unbounded -- item 8 names only the keyed reads.
    ///
    /// Item 6 (rework #5, r5b item 6, P0): a single-flight,
    /// deadline-bounded `C1DiscoveryExecutor`, replacing `TimedDiscoverer`'s
    /// after-the-fact timing (it always awaited the real call to
    /// completion first, which was never a real bound at all) and
    /// `blockingDiscover`'s own unbounded wait (bounded transitively now,
    /// since what it awaits can no longer hang past this executor's own
    /// bound). The reap (`confirmReap()`) already goes through this same
    /// property, so item 6's "the reap uses it too" holds by construction.
    /// A timeout marks the executor permanently stuck -- every later
    /// keyed/reap read fails at once -- and latches `captureFailed`
    /// synchronously (rest, then quit), recorded via the same `onStuck`
    /// this property already wired for `TimedDiscoverer`.
    lazy var timedDiscoverer: any Discovering = C1DiscoveryExecutor(wrapping: discoverer, bound: environment.discoveryExecutorBoundSeconds, onStuck: { [weak self] in
        self?.evidence?.record("discovery.stuck", [:])
        self?.latchingCapturer?.feed(.init(captureFailed: true))
    })

    /// Round 3 item 2: the one stage-wide serial AX executor. Every AX
    /// read the stage or its verifiers make (the owner observer's
    /// sampler, `HidingVerification`'s own internal one, its preflight
    /// closure's reader) is wrapped with `C1ExecutedAXReader` around this
    /// single instance, so a stuck read anywhere synchronously trips the
    /// latch -- feeding `captureFailed` is an immediate abort (`Latch`,
    /// C1Core) -- and every later AX read, through any of those readers,
    /// fails at once rather than becoming a quiet `.refused` that could
    /// still average out to PASS. `rest`/`quit` go over the helpers'
    /// stdin (`HelperControl.send`), never AX, so cleanup still works
    /// with this executor stuck.
    lazy var axExecutor = C1AXExecutor(onStuck: { [weak self] in
        self?.latchingCapturer?.feed(.init(captureFailed: true))
    })

    var geometry: BarGeometry!
    var evidence: (any C1EvidenceRecording)?

    var targetHelper: (any C1HelperControlling)?
    var spacerHelper: (any C1HelperControlling)?
    var protectedHelper: (any C1HelperControlling)?
    var targetKey: ItemKey?
    var spacerKey: ItemKey?
    var protectedKey: ItemKey?

    /// Section 3's roster snapshot: the fresh full AX roster, taken only
    /// after a passing reset (Amendment v4/P1) -- or, before the first
    /// preflight, at the end of the baseline. A missing snapshot fails
    /// closed (`RosterSnapshotCheck`).
    var rosterSnapshot: RosterSnapshot?
    /// Baseline-equivalence readings a passing baseline/reset check leaves
    /// behind, for the next reset check and for teardown to compare
    /// against. Templated owner items (pixel, 2 pt) and the three helpers
    /// are tracked here; untemplated owner items are tracked separately
    /// (`untemplatedOwnerBaseline`, G-b) since they are watched by AX, not
    /// pixels.
    var ownerBaselineReadings: [BaselineEquivalence.Reading] = []
    var helperBaselineReadings: [BaselineEquivalence.Reading] = []
    var untemplatedOwnerBaseline: [UntemplatedOwnerWatch.Reading] = []
    var baselineIndicatorFrame: BarFrame?
    /// G3 (Amendment v7, crosscheck-rework6.json finding 1): owner ids
    /// `StripAssessor.baseline` accepted but marked dynamic (its own
    /// baseline samples disagreed) -- left out of `ownerBaselineReadings`
    /// and every pixel check that reads it (`assessLatch`, `readFoldValue`'s
    /// references, the preflight/drawn targets, the reset check's `x()`),
    /// and watched through the keyed AX condition instead
    /// (`untemplatedOwnerBaseline`), like a baseline-rejected item.
    var dynamicOwnerIDs: Set<String> = []
    /// G3 (per-item "two consecutive agreeing captures" gate): the owner
    /// ids `assessLatch` found genuinely absent or uniquely off their
    /// baseline x in the *previous* capture -- an owner template trips only
    /// when the capture is stable against Protected or the same id was
    /// also flagged last time (crosscheck-rework6.json finding 1's
    /// corrected fix, item 2). A weak or ambiguous match never reaches
    /// this set at all; it never trips by itself, however many captures in
    /// a row.
    var previousCaptureOwnerIssues: Set<String> = []

    var ownerBaseline: BaselineResult!
    var ownerObserver: VisibilityObserver!
    var ownerItemIDs: [String: pid_t] = [:]

    var verification: HidingVerification!
    var prepared: PreparedVerification!
    /// F3 (Amendment v6, crosscheck #2/#7): the previous cycle's own
    /// measured wall time, used to predict the next cycle's -- `nil`
    /// until the first cycle completes, when `maybeRefreshVerificationBaseline`
    /// falls back to `initialCycleDurationEstimate`.
    var lastCycleDurationSeconds: Double?
    /// G8 (Amendment v7, "time budget"): `environment.pump.now()` at the
    /// very start of `run()` -- the budget guard's own "elapsed so far,"
    /// since the watchdog itself is armed at process start
    /// (`vizprobe/main.swift`), not at `step1Setup`'s own later point.
    var runStartAt: Double = 0
    /// G8: how many scan/smoke cycles have completed so far -- the budget
    /// guard's own "remaining cycles" (`ScanPlanner.lengths.count +
    /// RunAccounting.smokeCycleCount`, minus this, minus the one about to
    /// run).
    var cyclesRunSoFar = 0

    var latchingCapturer: LatchingCapturer!
    var channel: HelperControlChannel!
    var expansionDriver: C1ExpansionDriver!

    var caffeinateStarted = false
    var summary = [String: Any]()
    var preflightEverPassed = false
    var capturesStayedUnreadable = false

    private let lock = NSLock()
    private var machine = C1StageMachine()
    /// Item 3 / F2 (Amendment v6, staged teardown): set right before the
    /// staged teardown quits Protected (`runTeardownAndDecide`'s own
    /// stage 3, `confirmProtectedReap()`) -- `assessLatch` reads it to
    /// stop watching Protected once its disappearance is expected, not
    /// credible. Target and the spacer are quit much earlier (stage 1)
    /// but were never part of this gate -- `assessLatch`'s own
    /// `ownerOnlyIDs` already excludes all three helper ids from
    /// `missingOwnerItems`, so only Protected's separate one-miss
    /// condition ever needed a "this is expected now" flag.
    private var protectedTornDown = false
    var isProtectedTornDown: Bool { lock.withLock { protectedTornDown } }

    /// F2: called only by the staged teardown, right before it quits
    /// Protected.
    func markProtectedTornDown() {
        lock.withLock { protectedTornDown = true }
    }

    public init(environment: C1StageEnvironment, apps: C1Apps, dry: Bool) {
        self.environment = environment
        self.apps = apps
        self.dry = dry
        self.decision = MenuBarItemVisibility(maxMismatch: DetectorParameters.preRegistered.maxMismatch)
    }

    // MARK: - Run

    public func run() -> Int32 {
        // G8: the budget guard's own "elapsed so far" baseline -- as close
        // to the watchdog's own real arming point (process start) as this
        // method ever gets.
        runStartAt = environment.pump.now()
        // F5 (Amendment v6, crosscheck #4-#6/#9/#10/#12): no helper exists
        // yet -- a terminal event here (a signal before setup even
        // starts) has nothing to tear down, so it is reported straight
        // from `safetyStop`, never a re-runnable INCONCLUSIVE.
        for step in [("step0.bundles", step0Bundles), ("step1.setup", step1Setup)] {
            evidence?.record("step.begin", ["step": step.0])
            if let stop = safetyStop {
                return finish(stop == .needingAttention ? .safetyStopNeedingAttention : .safetyStop)
            }
            if case .abort(let reason) = step.1() {
                evidence?.record("step.abort", ["step": step.0, "reason": reason])
                return finish(.inconclusive("setup: \(step.0): \(reason)"))
            }
        }

        // Past this point a helper may be running -- F5: every exit,
        // terminal or a plain step abort, now funnels through the one
        // authoritative `runTeardownAndDecide()` (main-thread confirmReap,
        // the domain check, baseline-equivalence) rather than the bare
        // `runCleanup(); finish(.inconclusive(...))` that used to drop a
        // recorded safety stop and skip the reap/equivalence checks
        // entirely.
        for step in [("step2.launch", step2Launch), ("step3.baseline", step3Baseline)] {
            evidence?.record("step.begin", ["step": step.0])
            if isTerminal {
                return finish(runTeardownAndDecide(scan: [], smoke: [], smokeChecks: []))
            }
            if case .abort(let reason) = step.1() {
                evidence?.record("step.abort", ["step": step.0, "reason": reason])
                return finish(runTeardownAndDecide(scan: [], smoke: [], smokeChecks: []))
            }
        }

        let scanReadings = runScan()
        if isTerminal {
            return finish(runTeardownAndDecide(scan: scanReadings, smoke: [], smokeChecks: []))
        }
        guard let midpoint = ScanPlanner.midpointOfWidestHiddenRun(scanReadings.map { .init(length: $0.length, hidden: $0.reading == .hidden(folded: false)) }) else {
            return finish(runTeardownAndDecide(scan: scanReadings, smoke: [], smokeChecks: []))
        }
        evidence?.record("scan.midpoint", ["length": midpoint])
        summary["midpoint"] = midpoint

        var smokeReadings = [TargetReading]()
        var smokeChecks = [Bool]()
        // Round 3 item 1: a smoke preflight that keeps failing leaves this
        // loop short (or empty) -- `RunAccounting.decide` requires exactly
        // `smokeCycleCount` completed cycles for anything but INCONCLUSIVE,
        // so a partial `smokeReadings`/`smokeChecks` here is reported
        // correctly without this loop needing its own extra bookkeeping.
        for cycle in 0..<RunAccounting.smokeCycleCount {
            guard !isTerminal, let result = runCycle(length: midpoint, label: "smoke.\(cycle)") else { break }
            smokeReadings.append(result.reading)
            smokeChecks.append(result.otherChecksPassed)
        }

        return finish(runTeardownAndDecide(scan: scanReadings, smoke: smokeReadings, smokeChecks: smokeChecks))
    }

    func runScan() -> [(length: Double, reading: TargetReading)] {
        var results = [(length: Double, reading: TargetReading)]()
        for length in ScanPlanner.lengths {
            guard !isTerminal, let result = runCycle(length: length, label: "scan.\(Int(length))") else { break }
            results.append((length, result.reading))
        }
        return results
    }

    /// From the watchdog and the signal handlers, from any thread (P1: the
    /// watchdog enters the same terminal safety teardown a trip does --
    /// rest first, via `machine`'s own ordering, then reap, then report
    /// needing attention).
    public func emergencyStop() {
        handleTerminal(lock.withLock { machine.watchdogFired() })
    }

    /// Item 8: a signal's own entry point -- its own terminal reason
    /// (`.signal`, needing attention), distinct from the watchdog's,
    /// though the immediate cleanup this triggers is the same shape.
    public func signalReceived() {
        handleTerminal(lock.withLock { machine.signalReceived() })
    }

    var isTerminal: Bool { lock.withLock { machine.isTerminal } }

    /// Items 1/9: accounting reads only the machine -- there is no
    /// separate stage-level copy that could lag behind or race it.
    var safetyStop: RunAccounting.SafetyStop? { lock.withLock { machine.safetyStop } }

    /// Opens the expansion window, sends `length` (unless `--dry`), runs
    /// `body`, and guarantees `rest` plus a closed window on every exit
    /// (P0-4) -- `C1StageMachine.beginExpansion()`/`endExpansion()`
    /// directly, each under its own short lock, rather than
    /// `C1StageMachine.withExpansion(...)` held across the whole call:
    /// `body` runs `verify()`, whose captures reach `latchingCapturer` --
    /// and a trip there calls `onLatchTrip` back on `HidingVerification`'s
    /// own queue thread, not this one. Holding `lock` for the whole of
    /// `body` would deadlock that callback against this thread's own wait
    /// on the same lock.
    ///
    /// Item 3 (G-a, Codex round 2) / round 4 item 1: the window stays open
    /// through `confirmRestSettled()` -- a settled, bracketed read
    /// confirming the spacer is actually back at rest (drawn at its own
    /// baseline template), not merely that `rest` was sent. Round 4 item
    /// 1: an unconfirmed rest (the read was unstable/unreadable, or did
    /// not show the spacer drawn) fails closed -- `endExpansion(
    /// restConfirmed:)` then goes terminal instead of closing the window,
    /// and this method performs whatever cleanup actions that returns.
    /// Only a *confirmed* read's own fold, found once the window is
    /// actually closed, is fed to the latch (`watchFold` itself checks
    /// `!expansionWindowOpen`, so feeding it before closing would always
    /// be silently ignored as "still mid-expansion").
    func withExpansionWindow<T>(to lengthPt: Double, _ body: () -> T) -> T {
        lock.withLock { machine.beginExpansion() }
        expansionDriver.expand(to: lengthPt)
        defer {
            expansionDriver.collapse()
            let (restConfirmed, fold) = confirmRestSettled()
            let actions = lock.withLock { machine.endExpansion(restConfirmed: restConfirmed) }
            // Evidence gap (crosscheck, I7 3h): `perform(actions)` alone
            // runs the cleanup but never records *why* -- only
            // `handleTerminal` writes the `"terminal"` evidence record, and
            // every other terminal path already goes through it. An
            // unconfirmed rest is itself a terminal event (`restNotConfirmed`)
            // and must be recorded the same way.
            handleTerminal(actions)
            if restConfirmed, let fold { watchFold(fold, label: "collapse.rest") }
        }
        return body()
    }

    /// G-a / round 4 item 1 / rework #5 item 1 (r5b item 1, P0): the
    /// spacer's own settled, bracketed read after `rest` was sent, fixed
    /// per the round-5b ruling:
    ///  - Protected is the reference (`settledPairedRead`'s own
    ///    `CaptureStability` check needs a non-empty reference set to ever
    ///    report stable at all -- an empty one was never stable, which is
    ///    exactly what made this unreachable before);
    ///  - the first sample is not taken until >= 1 s after `rest` was sent;
    ///  - up to 10 s is spent retrying for two stable captures (each
    ///    `settledPairedRead` call is itself already a two-sample bracket
    ///    >= 1 s apart) that also show the spacer `.drawn` within
    ///    `referenceTolerancePt` of its own rest-baseline x -- not merely
    ///    `.drawn` at any x, which an expanded or otherwise misplaced
    ///    spacer could also satisfy.
    private func confirmRestSettled() -> (restConfirmed: Bool, fold: Fold?) {
        guard let spacerKey, let protectedKey else { return (false, nil) }
        let restBaselineX = helperBaselineReadings.first(where: { $0.id == spacerKey.encoded })?.x
        environment.pump.sleep(1.0)
        let deadline = environment.pump.now() + 10
        var lastFold: Fold?
        repeat {
            guard let settled = settledPairedRead(targets: [spacerKey.encoded], references: [protectedKey.encoded]) else {
                guard !isTerminal else { break }
                continue
            }
            lastFold = settled.reading.fold
            if case .drawn(let x)? = settled.visibility[spacerKey.encoded],
               let restBaselineX, abs(x - restBaselineX) <= parameters.referenceTolerancePt {
                return (true, settled.reading.fold)
            }
        } while !isTerminal && environment.pump.now() < deadline
        return (false, lastFold)
    }

    var expansionWindowOpen: Bool { lock.withLock { machine.expansionWindowOpen } }

    /// I3's trip callback (wired into `latchingCapturer` in `step2Launch`):
    /// P0-3's terminal state, synchronously, ahead of the channel's own
    /// rest/quit (`LatchingCapturer.onTrip` already fires before those).
    func onLatchTrip(_ reason: LatchTrip) {
        handleTerminal(lock.withLock { machine.trip(reason) })
    }

    /// Section 4 / P0-3: never reset a tripped (or otherwise terminal)
    /// latch.
    func resetLatchIfNotTerminal() {
        guard lock.withLock({ machine.canReset }) else { return }
        latchingCapturer.resetAfterPassingCheck()
    }

    /// P0-6: teardown could not confirm a reap -- a safety stop needing
    /// the owner's attention, not a silent PASS.
    func markTeardownReapFailed() {
        handleTerminal(lock.withLock { machine.teardownReapFailed() })
    }

    /// Item 7: a reset-check (baseline-equivalence) failure is itself an
    /// immediate safety stop -- no further cycle or scan-length work.
    func markResetCheckFailed() {
        handleTerminal(lock.withLock { machine.resetCheckFailed() })
    }

    /// Item 1: teardown's own mismatch (a non-empty/unreadable helper
    /// domain, or the bar not baseline-equivalent within 30 s) -- routed
    /// through the machine like every other safety event, not a
    /// stage-level flag.
    func markTeardownMismatch() {
        handleTerminal(lock.withLock { machine.teardownMismatch() })
    }

    /// P0-5: every exit after setup starts, that is not already itself a
    /// terminal event, still runs the one idempotent cleanup.
    func runCleanup() {
        perform(lock.withLock { machine.cleanup() })
    }

    /// Round 3 item 4: the watchdog's last-resort backstop, called
    /// synchronously right before it forces a raw `exit` -- writes a
    /// recorded terminal verdict to evidence (when evidence exists at
    /// all; a backstop this early in setup has none to write to) so the
    /// run never disappears from the record silently. Distinct from
    /// `finish(_:)`: that reads `machine.terminalReason`/`safetyStop` for
    /// a verdict this method cannot safely wait on `run()`'s own thread
    /// to produce, which is exactly the situation that put the backstop
    /// on the table.
    public func recordWatchdogBackstopVerdict() {
        // Item 7: the backstop also stops caffeinate -- unconditionally,
        // ahead of the `evidence` guard below (a backstop this early in
        // setup, before `evidence` exists, still has a `caffeinate` to
        // stop if `step1Setup` got that far); `stop()` is a no-op if it
        // never started.
        environment.caffeinate.stop()
        guard let evidence else { return }
        evidence.record("terminal", ["reason": "watchdog backstop"])
        evidence.record("run.verdict", ["verdict": "\(Verdict.safetyStopNeedingAttention)"])
        evidence.close()
    }

    /// `machine.trip`/`watchdogFired`/`teardownReapFailed`/
    /// `resetCheckFailed`/`teardownMismatch` already set `isTerminal`,
    /// `terminalReason` and `safetyStop` together, atomically, before
    /// returning `actions` (items 1/9) -- this only performs those
    /// actions and records the reason for evidence.
    private func handleTerminal(_ actions: [C1StageAction]) {
        perform(actions)
        guard let reason = lock.withLock({ machine.terminalReason }) else { return }
        evidence?.record("terminal", ["reason": "\(reason)"])
    }

    /// P0-5's action executor. Order matches `C1StageMachine.cleanup()`'s
    /// own: rest, quit, reap.
    private func perform(_ actions: [C1StageAction]) {
        for action in actions {
            switch action {
            // Item 9: `.sendRest` (a stdin write via `HelperControl.send`)
            // is thread-safe from any thread as it already stood.
            case .sendRest: expansionDriver?.collapse()
            // G5 (Amendment v7): off the main thread (a trip on
            // `HidingVerification`'s own queue, the watchdog/signal global
            // queue), only a non-blocking quit request is safe -- the
            // ordinary `quit()` this reaches through `quitAll()` may wait
            // up to 2 s per helper (`HelperControl.quit(timeout:)`), which
            // is not this stage's own thread-safe-only budget for off-main
            // terminal handling. On the main thread, the ordinary blocking
            // `quitAll()` still runs directly (it already stood, and the
            // main thread owns waiting on it).
            case .quitAllHelpers:
                if Thread.isMainThread {
                    channel?.quitAll()
                } else {
                    channel?.quitAllNonBlocking()
                }
            case .reapHelpers:
                // Item 9 (r5b item 9, P0): `confirmReap()` pumps
                // `RunLoop.main` (`environment.pump.run`/`.blocking`) --
                // running that from a thread that is not the stage's own
                // owner (main) thread, while the owner thread might
                // itself be concurrently pumping the very same run loop
                // inside its own `Pump.blocking` wait, is undefined
                // (`RunLoop` is not thread-safe). A trip's `onTrip`
                // callback can fire from `HidingVerification`'s own
                // internal queue thread, and the watchdog/signal paths
                // fire from a global-queue thread -- neither is the owner
                // thread. Off that thread, this action is a no-op: the
                // owner thread's own `runTeardownAndDecide()` always makes
                // its own authoritative `confirmReap()` call regardless,
                // and the watchdog/signal backstop covers the case where
                // the owner thread never gets there at all.
                guard Thread.isMainThread else { break }
                // F2: the generic one-shot cleanup only ever reaps Target
                // and the spacer -- Protected is reaped separately, only
                // by the staged teardown, once its own fold read passed.
                _ = confirmNonProtectedReap()
            }
        }
    }

    /// G5 (Amendment v7): stops `caffeinate` exactly once here -- after
    /// every verdict-deciding read on every exit path (`finish(_:)` is the
    /// very last thing `run()` calls, on the normal path and on every
    /// setup-abort path alike) -- and in the watchdog/signal backstop
    /// (`recordWatchdogBackstopVerdict()`); never in `cleanup()`, which
    /// used to stop it the instant any terminal event fired, before the
    /// staged teardown's own screen reads had run.
    private func finish(_ verdict: Verdict) -> Int32 {
        stopCaffeinate()
        summary["verdict"] = "\(verdict)"
        evidence?.record("run.verdict", ["verdict": "\(verdict)"])
        evidence?.record("summary", summary)
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print("summary:\n\(text)")
        }
        evidence?.close()
        switch verdict {
        case .pass: return 0
        case .provisionalFail: return 1
        case .safetyStop, .safetyStopNeedingAttention: return 3
        case .inconclusive: return 2
        }
    }

    func stopCaffeinate() {
        let shouldStop: Bool = lock.withLock {
            defer { caffeinateStarted = false }
            return caffeinateStarted
        }
        guard shouldStop else { return }
        environment.caffeinate.stop()
    }
}
