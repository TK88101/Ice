// Plan 6.1 steps 1-2: preflight and the pre-flight baseline (shared with
// `--dry-run` via `PreflightCheck`), then deleting `com.icespike4.*`
// defaults and launching the reference, then the target.
import Foundation
import IceCore
import MenuBarCapture

extension LiveRun {
    func step1PreflightAndBaseline() -> StepResult {
        let outcome = PreflightCheck.run(capturer: capturer, axReader: axReader, parameters: parameters)
        guard let geometry = outcome.geometry else {
            return .abort("no bar geometry (NSScreen.main unavailable)")
        }
        self.geometry = geometry
        guard case .ready = outcome.preflight else {
            return .abort("preflight: \(outcome.preflight)")
        }
        guard let preflightBaseline = outcome.baseline else {
            return .abort("pre-flight baseline failed (a capture or an Accessibility read did not complete)")
        }
        self.preflightBaseline = preflightBaseline
        guard !outcome.chevronOrPillSignal else {
            return .abort("a chevron or a privacy pill is present before any helper is launched")
        }
        guard outcome.freeRoomOK else {
            return .abort("free room right of the notch is under \(Int(PreflightCheck.minFreeRoomPt)) pt")
        }

        do {
            evidence = try LiveEvidence(binaryURLs: binaryURLs(), arguments: CommandLine.arguments, geometry: geometry, parameters: parameters)
        } catch {
            return .abort("could not create the evidence directory: \(error)")
        }
        evidence.record("preflight", [
            "leftmostThirdPartyX": outcome.room?.leftmostThirdPartyX ?? -1,
            "freeRoomPt": outcome.room?.freeRoomPt ?? -1,
            "acceptedThirdPartyItems": preflightBaseline.acceptedIDs,
            "rejectedThirdPartyItems": preflightBaseline.rejections.mapValues { "\($0)" },
            "foldAtBaseline": "\(preflightBaseline.foldAtBaseline)",
            "environmentIndicators": outcome.environmentIndicators.map { "\($0.minX)/\($0.width)" },
        ])

        // Plan 6.1 step 1: fewer than one accepted item and there is nothing to
        // protect the user's bar with. A monitor watching nothing is not a
        // safeguard -- the 2026-09-18 runs shipped that mistake twice.
        guard !preflightBaseline.acceptedIDs.isEmpty else {
            return .abort("the pre-flight baseline accepted no user item, so the safety monitor would watch nothing")
        }

        do {
            monitor = try SafetyMonitor(baseline: preflightBaseline, parameters: parameters)
        } catch {
            return .abort("the pre-flight baseline had no calibrated ink; the safety monitor cannot start")
        }
        evidence.record("safetyMonitor.armed", ["watching": monitor.watchedCount])

        sampler = Sampler(capturer: capturer, axReader: axReader)
        observer = VisibilityObserver(sampler: sampler, parameters: parameters)
        return .ok
    }

    func step2LaunchHelpers() -> StepResult {
        for bundleID in HelperRole.allBundleIDs { HelperDefaults.forget(bundleID) }
        let controllerPID = getpid()

        let referenceHelper: HelperControl
        let targetHelper: HelperControl
        do {
            // Reference first, then target: a new item appears leftmost, so
            // the target ends up left of the reference and hiding it later
            // moves nobody (plan 6.1 step 2).
            referenceHelper = try HelperControl(appURL: apps.reference, bundleID: HelperRole.reference, role: "reference", controllerPID: controllerPID)
            Thread.sleep(forTimeInterval: 0.6)
            targetHelper = try HelperControl(appURL: apps.target, bundleID: HelperRole.target, role: "target", controllerPID: controllerPID)
        } catch {
            return .abort("could not launch a helper: \(error)")
        }
        reference = referenceHelper
        target = targetHelper
        evidence.record("helpers.launched", ["referencePID": referenceHelper.pid, "targetPID": targetHelper.pid])

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let snapshot = axReader.read(items: ["target": targetHelper.pid, "reference": referenceHelper.pid]),
               snapshot.itemFrames["target"] != nil, snapshot.itemFrames["reference"] != nil {
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return .ok
    }

    private func binaryURLs() -> [String: URL] {
        [
            "vizprobe": URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath(),
            "vzhelper.target": apps.target.appendingPathComponent("Contents/MacOS/vzhelper"),
            "vzhelper.reference": apps.reference.appendingPathComponent("Contents/MacOS/vzhelper"),
            "vzhelper.twin": apps.twin.appendingPathComponent("Contents/MacOS/vzhelper"),
        ]
    }
}
