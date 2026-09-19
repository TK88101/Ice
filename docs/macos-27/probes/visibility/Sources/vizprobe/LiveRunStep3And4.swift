// Plan 6.1 step 3: the room check after launching the helpers -- abort,
// helpers quit first, if a chevron appeared, the agent set changed, or the
// safety monitor reports harm. Step 4: the baseline both helpers must be
// accepted into.
import Foundation
import IceCore
import MenuBarCapture

extension LiveRun {
    func step3RoomCheck() -> StepResult {
        // Warm up again before reading: the indicator that capturing summons
        // fades within a second or two of the last capture, and launching the
        // helpers is exactly such a gap — the agent set would then differ from
        // the baseline's through our own instrument's doing, not the bar's.
        for _ in 0..<PreflightCheck.warmUpCaptures / 4 {
            _ = capturer.capture()
            Thread.sleep(forTimeInterval: PreflightCheck.warmUpInterval)
        }
        guard let capture = capturer.capture() else { return .abort("room check: capture failed") }
        evidence.keep(capture, label: "roomcheck")

        let onBar = BarScan.items().filter { $0.minY >= 0 && $0.minY < geometry.heightPt }
        let currentAgent = onBar
            .filter { $0.bundleID == BarScan.menuBarAgentBundleID }
            .map { AgentFrame(minX: $0.minX, minY: $0.minY, width: $0.width) }

        guard !agentSetChanged(current: currentAgent, baseline: preflightBaseline.agentFrames) else {
            evidence.record("roomcheck.agentSetChanged", ["current": currentAgent.count, "baseline": preflightBaseline.agentFrames.count])
            return .abort("the MenuBarAgent item set changed after launching the helpers")
        }

        let ownBundleIDs = [HelperRole.target, HelperRole.reference]
        let thirdParty = onBar.filter { $0.bundleID != BarScan.menuBarAgentBundleID && !ownBundleIDs.contains($0.bundleID) }
        if let leftmost = thirdParty.min(by: { $0.minX < $1.minX }) {
            // Only the chevron's own width (17.5 pt in every reading on
            // record) and the microphone pill's (16 pt, two recorded
            // baselines) abort here. A capture summons a ≈ 20 pt indicator
            // left of the items (MEASURED 2026-09-19) and the run cannot
            // avoid capturing; that one is already in the baseline's agent
            // set, and `agentSetChanged` above is what notices if it moves.
            let chevronCandidates = currentAgent.filter {
                $0.minX < leftmost.minX
                    && (FoldWitness.isChevron($0, parameters: parameters) || FoldWitness.isPill($0, parameters: parameters))
            }
            guard chevronCandidates.isEmpty else {
                evidence.record("roomcheck.chevronAppeared", ["count": chevronCandidates.count])
                return .abort("a chevron or a privacy pill appeared left of the leftmost third-party item")
            }
        }

        if let reason = safetyCapture(label: "roomcheck") {
            return .abort(reason)
        }
        return .ok
    }

    func step4Baseline() -> StepResult {
        guard let target, let reference else { return .abort("helpers not launched") }
        guard let baseline = observer.baseline(items: ["target": target.pid, "reference": reference.pid], geometry: geometry) else {
            return .abort("baseline: a capture or an Accessibility read failed")
        }
        itemBaseline = baseline
        evidence.record("baseline", ["accepted": baseline.acceptedIDs, "rejections": baseline.rejections.mapValues { "\($0)" }])
        guard baseline.acceptedIDs.contains("target"), baseline.acceptedIDs.contains("reference") else {
            return .abort("baseline did not accept both helpers: accepted=\(baseline.acceptedIDs) rejections=\(baseline.rejections)")
        }
        if let reason = safetyCapture(label: "baseline") {
            return .abort(reason)
        }
        return .ok
    }

    /// Every current non-chevron-width frame paired with a baseline frame at
    /// the same x and width, one to one -- the same idea as `FoldWitness`'s
    /// own rule (Packages/IceCore/Sources/IceCore/FoldWitness.swift), kept
    /// local here because that function is private to IceCore and this is a
    /// coarser, room-check-only version of it (it does not exempt
    /// chevron-width frames, because at this point in the protocol none are
    /// expected at all).
    /// IceCore's own rule, not a copy of it: the harness asks exactly the
    /// question the fold witness asks, so it calls the same function.
    private func agentSetChanged(current: [AgentFrame], baseline: [AgentFrame]) -> Bool {
        !FoldWitness.agentSetMatches(current: current, baseline: baseline, parameters: parameters)
    }
}
