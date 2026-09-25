// I5: `vizprobe c1` -- the C1 protocol (docs/plans/2026-09-26-c1-protocol.md,
// sections 2-5) as its own stage, independent of `StageRun`/`LiveRun` (the
// 2026-09-19/2026-09-23 plans' two-helper protocols): C1 launches three
// helpers in a fixed order (Protected, the spacer, Target), and every
// decision -- the scan plan, the preflight order/roster checks, baseline
// equivalence, the latch, the run's final verdict -- comes from C1Core
// (I1) through the tested seams in C1Live (I3/I4/I5's own dry-run/trip
// sequencing). This file holds setup, launch and the run driver; the scan
// and smoke cycle is `StageC1Cycle.swift`, teardown and accounting are
// `StageC1Teardown.swift`.
import AppKit
import C1Core
import C1Live
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

/// Where build.sh's output apps directory holds the three helper bundles.
/// Target and Protected reuse `probes/safewidth`'s own bundle ids exactly
/// as `HelperRole` already does (2026-09-23 plan); the spacer needs a
/// fourth bundle build.sh does not produce today -- out of this change's
/// edit scope (Package.swift/Sources/Tests only). Until the owner adds a
/// `Spacer.app` target to build.sh (or points `--spacer-app` at some other
/// bundle carrying a `vzhelper` binary), `vizprobe c1` cannot actually
/// launch the spacer role; everything else here is real.
struct C1Apps {
    let target: URL
    let protected: URL
    let spacer: URL
}

enum C1HelperRole {
    static let target = HelperRole.target
    static let protected = HelperRole.reference
    /// Not one of `HelperRole.allBundleIDs` (2026-09-23 plan) on purpose:
    /// the spacer is new to C1 and never existed under the older plans'
    /// two-helper bundles.
    static let spacer = "com.icespike4.spacer"
    static let all = [target, protected, spacer]
}

/// I5's channel: every command this stage sends a helper goes through here,
/// so `C1Live`'s tested pieces (`LatchingCapturer`, `C1ExpansionDriver`) can
/// drive the same real helpers the launch steps started, and a fake can
/// stand in for it in a test.
final class HelperControlChannel: C1HelperChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var helpers: [HelperControl]
    private let spacerHelper: () -> HelperControl?

    init(helpers: [HelperControl], spacer: @escaping () -> HelperControl?) {
        self.helpers = helpers
        self.spacerHelper = spacer
    }

    func sendLength(_ pt: Double) {
        spacerHelper()?.send("length \(pt)")
    }

    func sendRest() {
        spacerHelper()?.send("rest")
    }

    /// Quits every helper this channel knows about. Not itself a
    /// discovery-verified reap (section 2's "quits and reaps all three
    /// helpers and confirms none of their items is listed" is
    /// `StageC1.reapAll()`, which calls this and then re-discovers); a
    /// trip (I3) only needs the commands sent, synchronously, which is all
    /// this method promises.
    func quitAll() {
        let snapshot: [HelperControl] = lock.withLock { helpers }
        for helper in snapshot { helper.quit() }
    }
}

final class StageC1 {
    static let watchdogMinutes = 15.0

    let apps: C1Apps
    let dry: Bool
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

    var geometry: BarGeometry!
    var evidence: LiveEvidence!

    var targetHelper: HelperControl?
    var spacerHelper: HelperControl?
    var protectedHelper: HelperControl?
    var targetKey: ItemKey?
    var spacerKey: ItemKey?
    var protectedKey: ItemKey?

    /// Section 3's roster snapshot: recorded at the end of the previous
    /// *passing* reset check (or, before the first preflight, at the end
    /// of the baseline). A missing snapshot fails closed
    /// (`RosterSnapshotCheck`).
    var rosterSnapshot: RosterSnapshot?
    /// Baseline-equivalence readings a passing baseline/reset check leaves
    /// behind, for the next reset check and for teardown to compare
    /// against.
    var ownerBaselineReadings: [BaselineEquivalence.Reading] = []
    var helperBaselineReadings: [BaselineEquivalence.Reading] = []
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
    var safetyStop: RunAccounting.SafetyStop?

    private let lock = NSLock()
    private var stopping = false

    init(apps: C1Apps, dry: Bool) {
        self.apps = apps
        self.dry = dry
    }

    // MARK: - Run

    func run() -> Int32 {
        for step in [
            ("step0.bundles", step0Bundles),
            ("step1.setup", step1Setup),
            ("step2.launch", step2Launch),
            ("step3.baseline", step3Baseline),
        ] {
            evidence?.record("step.begin", ["step": step.0])
            if case .abort(let reason) = step.1() {
                return finish(.inconclusive("setup: \(step.0): \(reason)"))
            }
        }

        let scanReadings = runScan()
        guard let midpoint = ScanPlanner.midpointOfWidestHiddenRun(scanReadings.map { .init(length: $0.length, hidden: $0.reading == .hidden(folded: false)) }) else {
            return finish(runTeardownAndDecide(scan: scanReadings, smoke: [], smokeChecks: []))
        }
        evidence.record("scan.midpoint", ["length": midpoint])
        summary["midpoint"] = midpoint

        var smokeReadings = [TargetReading]()
        var smokeChecks = [Bool]()
        for cycle in 0..<5 where safetyStop == nil {
            guard let result = runCycle(length: midpoint, label: "smoke.\(cycle)") else { break }
            smokeReadings.append(result.reading)
            smokeChecks.append(result.otherChecksPassed)
        }

        return finish(runTeardownAndDecide(scan: scanReadings, smoke: smokeReadings, smokeChecks: smokeChecks))
    }

    /// Section 3: whether the preflight has ever passed this run, and
    /// whether captures stayed unreadable -- section 1's two INCONCLUSIVE
    /// reasons.
    var preflightEverPassed = false
    var capturesStayedUnreadable = false

    func runScan() -> [(length: Double, reading: TargetReading)] {
        var results = [(length: Double, reading: TargetReading)]()
        for length in ScanPlanner.lengths where safetyStop == nil {
            guard let result = runCycle(length: length, label: "scan.\(Int(length))") else { break }
            results.append((length, result.reading))
        }
        return results
    }

    /// From the watchdog and signal handlers, from any thread.
    func emergencyStop() {
        lock.withLock { stopping = true }
        channel?.sendRest()
        channel?.quitAll()
        stopCaffeinate()
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
