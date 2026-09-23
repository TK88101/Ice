// The orchestrator for T14, the live run of plan section 6. Not executed by
// this task -- section T13 only has to build it and pass `--dry-run`; the
// parent session runs it live. Every step below returns a `StepResult`
// rather than throwing, so `execute()` is the one place that decides what
// "no retry within the run" (section 6, last paragraph) means: the instant
// a step aborts, every later step is skipped and the helpers are quit.
import AppKit
import Foundation
import IceCore
import MenuBarCapture

enum LiveRunOutcome {
    case completed
    case aborted(step: String, reason: String)
}

/// `observeChecked`'s result: `Result<ObservationResult, String>` is not
/// expressible directly because `String` does not conform to `Error`, and
/// wrapping every abort reason in a throwing `Error` type buys nothing a
/// plain enum does not already say.
enum ObserveOutcome {
    case success(ObservationResult)
    case failure(String)
}

final class LiveRun {
    let apps: HelperApps
    let capturer = CGWindowListStripCapturer()
    let axReader = NSScreen.main.map { LiveMenuBarAXReader(screen: $0) } ?? LiveMenuBarAXReader()
    let parameters = DetectorParameters.preRegistered
    let decision: MenuBarItemVisibility

    var geometry: BarGeometry!
    var evidence: LiveEvidence!
    var monitor: SafetyMonitor!
    var preflightBaseline: BaselineResult!
    var itemBaseline: BaselineResult!
    var sampler: Sampler!
    var observer: VisibilityObserver!

    var reference: HelperControl?
    var target: HelperControl?
    var twin: HelperControl?

    /// The ids the detector sees for the two helpers. `live` keeps the
    /// 2026-09-19 names; `vizprobe verify` (2026-09-23 plan, step 3) sets
    /// them to the discovered keys' encodings, read through
    /// `DiscoveredFrameReader`.
    var targetID = "target"
    var referenceID = "reference"
    /// Control (c), the twin, is left out by the 2026-09-23 plan's step 3.
    var includeControlC = true
    /// Other items observed alongside the helpers so their ink is explained
    /// (2026-09-23 plan, D15 and Deviation 8); empty in the `live` mode.
    var alsoObservedIDs = [String: pid_t]()

    /// The helpers' ids plus `alsoObservedIDs`.
    func observedItems(_ helpers: [String: pid_t]) -> [String: pid_t] {
        helpers.merging(alsoObservedIDs) { first, _ in first }
    }

    init(apps: HelperApps) {
        self.apps = apps
        self.decision = MenuBarItemVisibility(maxMismatch: parameters.maxMismatch)
    }

    func run() -> Int32 {
        switch execute() {
        case .completed:
            print("vizprobe: run completed -- evidence at \(evidence?.directory.path ?? "?")")
            evidence?.record("run.completed", [:])
            evidence?.close()
            return 0
        case .aborted(let step, let reason):
            FileHandle.standardError.write(Data("vizprobe: ABORTED at \(step) -- \(reason)\n".utf8))
            evidence?.record("run.aborted", ["step": step, "reason": reason])
            evidence?.close()
            return 1
        }
    }

    private func execute() -> LiveRunOutcome {
        let steps: [(name: String, body: () -> StepResult)] = [
            ("step1.preflight", step1PreflightAndBaseline),
            ("step2.launch", step2LaunchHelpers),
            ("step3.roomCheck", step3RoomCheck),
            ("step4.baseline", step4Baseline),
            ("step5.cycles", step5Cycles),
            ("step6.controls", step6Controls),
        ]
        for step in steps {
            if case .abort(let reason) = step.body() {
                quitHelpers()
                return .aborted(step: step.name, reason: reason)
            }
        }
        // Teardown always runs, even though it is itself a step that can
        // report a problem: the plan's teardown (6.1 step 7) is what quits
        // the helpers in the success path, so it is not behind the same
        // "quit first" guard the earlier steps are.
        if case .abort(let reason) = step7Teardown() {
            return .aborted(step: "step7.teardown", reason: reason)
        }
        return .completed
    }

    func quitHelpers() {
        reference?.quit()
        target?.quit()
        twin?.quit()
        for bundleID in HelperRole.allBundleIDs { HelperDefaults.forget(bundleID) }
    }

    /// Captures once, keeps it in the evidence directory, and feeds the
    /// safety monitor (plan 6.2). `nil` means the check passed.
    ///
    /// This is the one place the implementation cannot reach literally
    /// "every capture": `Sampler`'s own before/after brackets
    /// (MenuBarCapture, which this task may not modify) are private to
    /// `observe()`/`baseline()`, so the monitor is fed once per logical
    /// step from a capture taken here instead. Recorded as a deviation in
    /// the final report, not silently narrowed.
    func safetyCapture(label: String) -> String? {
        guard let capture = capturer.capture() else {
            return "capture failed during the \(label) safety check"
        }
        evidence.keep(capture, label: "safety-\(label)")
        let tripped = monitor.feed(capture)
        evidence.record("safety.check", ["label": label, "tripped": tripped])
        return tripped ? "safety monitor: a user item was not uniquely at its baseline position in two consecutive checks" : nil
    }

    /// `observe()`, recorded, then a safety check -- the shape every step
    /// from step 4 onward repeats.
    func observeChecked(items: [String: pid_t], label: String) -> ObserveOutcome {
        guard let result = observer.observe(baseline: itemBaseline, targets: [targetID] + Array(alsoObservedIDs.keys), references: [referenceID], items: observedItems(items)) else {
            return .failure("\(label): observe failed (a capture or an Accessibility read did not complete)")
        }
        evidence.record("observe", [
            "label": label,
            "visibility": result.visibility.mapValues { "\($0)" },
            "fold": "\(result.reading.fold)",
            "captureStable": result.reading.captureStable,
        ])
        if let reason = safetyCapture(label: label) {
            return .failure(reason)
        }
        return .success(result)
    }
}
