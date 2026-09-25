// I5: `vizprobe c1` -- the C1 protocol (docs/plans/2026-09-26-c1-protocol.md,
// sections 2-5, Amendment v4) as its own stage, independent of
// `StageRun`/`LiveRun` (the 2026-09-19/2026-09-23 plans' two-helper
// protocols): C1 launches three helpers in a fixed order (Protected, the
// spacer, Target), and every decision -- the scan plan, the preflight
// order/roster checks, baseline equivalence, the latch, the terminal
// state, the run's final verdict -- comes from C1Core (I1) through the
// tested seams in C1Live (I3/I4/I5's dry-run/trip sequencing, and the
// `C1StageMachine` state machine the Codex review's P0s asked for). This
// file holds setup, launch and the run driver; the scan and smoke cycle is
// `StageC1Cycle.swift`, teardown and accounting are `StageC1Teardown.swift`.
import AppKit
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
struct C1Apps {
    let target: URL
    let protected: URL
    let spacer: URL
}

enum C1HelperRole {
    static let target = HelperRole.target
    /// The spacer (`build.sh`'s `Spacer.app`) carries this same id --
    /// P0-1. `all` is therefore only two distinct ids, not three.
    static let protected = HelperRole.reference
    static let all = [target, protected]
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
final class HelperControlChannel: C1HelperChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var helpers: [HelperControl] = []
    private var spacerHelperRef: HelperControl?

    /// Registers a helper the instant its process starts (P0-2/item 2),
    /// before this run waits for its `up` reply or discovers its item --
    /// so a launch failure right after this still has a way to quit it.
    func register(_ helper: HelperControl, isSpacer: Bool = false) {
        lock.withLock {
            helpers.append(helper)
            if isSpacer { spacerHelperRef = helper }
        }
    }

    func sendLength(_ pt: Double) {
        (lock.withLock { spacerHelperRef })?.send("length \(pt)")
    }

    func sendRest() {
        (lock.withLock { spacerHelperRef })?.send("rest")
    }

    /// Quits every helper this channel knows about. Not itself a
    /// discovery-verified reap (section 2's "quits and reaps all three
    /// helpers and confirms none of their items is listed" is
    /// `StageC1.confirmReap()`, which calls this and then re-discovers,
    /// checked against `C1ReapCheck` -- P0-6); a trip (I3) only needs the
    /// commands sent, synchronously, which is all this method promises.
    func quitAll() {
        let snapshot: [HelperControl] = lock.withLock { helpers }
        for helper in snapshot { helper.quit() }
    }
}

final class StageC1 {
    static let watchdogMinutes = 15.0

    let apps: C1Apps
    let dry: Bool
    /// The one real screen capturer. Never read directly once
    /// `latchingCapturer` exists (P0-2: every post-channel capture goes
    /// through the latch first) -- everything downstream reads through
    /// `latchingCapturer` instead.
    let capturer = CGWindowListStripCapturer()
    let parameters = DetectorParameters.preRegistered
    let decision = MenuBarItemVisibility(maxMismatch: DetectorParameters.preRegistered.maxMismatch)
    let discoverer = MenuBarDiscoverer(
        apps: HarnessProcesses(base: LiveRunningApps()),
        reader: LiveExtrasReader(),
        display: LiveDisplay(),
        isTrusted: { AXIsProcessTrusted() },
        ownIdentifiers: StageRun.ownIdentifiers,
        now: { ProcessInfo.processInfo.systemUptime }
    )
    /// Item 8: "same bound for the keyed discovery reads used by the
    /// untemplated watch and preflight" -- `currentUntemplatedReadings()`
    /// and `passesPreflightOnce()`'s AX order fetch use this, never
    /// `discoverer` directly. Launch-time and reap discovery keep using
    /// `discoverer` unbounded -- item 8 names only these two reads.
    /// Round 3 item 3: bounded by elapsed time after `discover` returns,
    /// not a task-group race.
    lazy var timedDiscoverer: any Discovering = TimedDiscoverer(wrapping: discoverer, onLate: { [weak self] in
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
    var evidence: LiveEvidence!

    var targetHelper: HelperControl?
    var spacerHelper: HelperControl?
    var protectedHelper: HelperControl?
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

    var ownerBaseline: BaselineResult!
    var ownerObserver: VisibilityObserver!
    var ownerItemIDs: [String: pid_t] = [:]

    var verification: HidingVerification!
    var prepared: PreparedVerification!

    var latchingCapturer: LatchingCapturer!
    var channel: HelperControlChannel!
    var expansionDriver: C1ExpansionDriver!

    var caffeinate: Process?
    var summary = [String: Any]()
    var preflightEverPassed = false
    var capturesStayedUnreadable = false

    private let lock = NSLock()
    private var machine = C1StageMachine()

    init(apps: C1Apps, dry: Bool) {
        self.apps = apps
        self.dry = dry
    }

    // MARK: - Run

    func run() -> Int32 {
        for step in [("step0.bundles", step0Bundles), ("step1.setup", step1Setup)] {
            evidence?.record("step.begin", ["step": step.0])
            if case .abort(let reason) = step.1() {
                return finish(.inconclusive("setup: \(step.0): \(reason)"))
            }
        }

        // Past this point a helper may be running -- P0-5: every exit
        // funnels through the one idempotent cleanup.
        for step in [("step2.launch", step2Launch), ("step3.baseline", step3Baseline)] {
            evidence?.record("step.begin", ["step": step.0])
            if case .abort(let reason) = step.1() {
                runCleanup()
                return finish(.inconclusive("setup: \(step.0): \(reason)"))
            }
        }

        let scanReadings = runScan()
        if isTerminal {
            return finish(runTeardownAndDecide(scan: scanReadings, smoke: [], smokeChecks: []))
        }
        guard let midpoint = ScanPlanner.midpointOfWidestHiddenRun(scanReadings.map { .init(length: $0.length, hidden: $0.reading == .hidden(folded: false)) }) else {
            return finish(runTeardownAndDecide(scan: scanReadings, smoke: [], smokeChecks: []))
        }
        evidence.record("scan.midpoint", ["length": midpoint])
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
    func emergencyStop() {
        handleTerminal(lock.withLock { machine.watchdogFired() })
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
    /// Item 3 (G-a, Codex round 2): the window stays open through
    /// `confirmRestSettledFold()` -- a settled, bracketed read confirming
    /// the spacer is actually back at rest, not merely that `rest` was
    /// sent -- and only that read's own fold, found once the window is
    /// finally closed, is fed to the latch (`watchFold` itself checks
    /// `!expansionWindowOpen`, so feeding it before closing would always
    /// be silently ignored as "still mid-expansion").
    func withExpansionWindow<T>(to lengthPt: Double, _ body: () -> T) -> T {
        lock.withLock { machine.beginExpansion() }
        expansionDriver.expand(to: lengthPt)
        defer {
            expansionDriver.collapse()
            let fold = confirmRestSettledFold()
            lock.withLock { machine.endExpansion() }
            if let fold { watchFold(fold, label: "collapse.rest") }
        }
        return body()
    }

    /// G-a: the spacer's own settled, bracketed read after `rest` was
    /// sent. `nil` on a capture/AX failure (`settledPairedRead` already
    /// fed `.captureFailed`) or if the spacer's own key is not yet known.
    private func confirmRestSettledFold() -> Fold? {
        guard let spacerKey else { return nil }
        return settledPairedRead(targets: [spacerKey.encoded], references: [])?.reading.fold
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
    func recordWatchdogBackstopVerdict() {
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
    /// own: rest, quit, reap, stop caffeinate.
    private func perform(_ actions: [C1StageAction]) {
        for action in actions {
            switch action {
            case .sendRest: expansionDriver?.collapse()
            case .quitAllHelpers: channel?.quitAll()
            case .reapHelpers: _ = confirmReap()
            case .stopCaffeinate: stopCaffeinate()
            }
        }
    }

    private func finish(_ verdict: Verdict) -> Int32 {
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
        let process: Process? = lock.withLock {
            defer { caffeinate = nil }
            return caffeinate
        }
        process?.terminate()
    }
}
