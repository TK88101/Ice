// Builds IceCore's own `BaselineResult` for every third-party item on the
// bar, reusing `StripAssessor.baseline` exactly as MenuBarCapture's
// `VisibilityObserver` does for our own items -- the difference is only
// where the `ObservationSample`s come from: `BarScan`'s AX walk of every
// running application, not the pid-scoped `MenuBarAXReading` that library
// exposes. This is what the pre-flight baseline of plan section 6.1 step 1
// is (a real baseline attempt, before anything of ours exists), and it is
// what the safety monitor of 6.2 cuts once and watches for the rest of the
// run. It is also exactly what `vizprobe --dry-run` reports: a real
// baseline attempt against the user's own bar that launches nothing.
import Foundation
import IceCore
import MenuBarCapture

enum ThirdPartyBaseline {
    /// `nil` when a capture failed on any attempt -- the same rule
    /// `Sampler` and `VisibilityObserver` use (MenuBarCapture, plan
    /// deviation 4): a baseline built around a hole in the record is not a
    /// baseline.
    static func take(
        capturer: some StripCapturing,
        geometry: BarGeometry,
        parameters: DetectorParameters,
        maxAttempts: Int = 32,
        sleep: (Double) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) -> BaselineResult? {
        var samples = [ObservationSample]()
        while samples.count < maxAttempts {
            guard let sample = takeSample(capturer: capturer, geometry: geometry) else { return nil }
            samples.append(sample)
            let span = samples[samples.count - 1].time - samples[0].time
            if samples.count >= parameters.baselineMinSamples, span >= parameters.baselineMinSpan {
                break
            }
            sleep(parameters.minSampleSpacing)
        }
        guard samples.count >= parameters.baselineMinSamples,
              samples[samples.count - 1].time - samples[0].time >= parameters.baselineMinSpan
        else {
            return nil
        }
        return StripAssessor.baseline(samples: samples, geometry: geometry, parameters: parameters)
    }

    private static func takeSample(capturer: some StripCapturing, geometry: BarGeometry) -> ObservationSample? {
        guard let before = capturer.capture() else { return nil }
        let items = BarScan.items().filter { $0.minY >= 0 && $0.minY < geometry.heightPt }
        guard let after = capturer.capture() else { return nil }

        // Id by bundle id plus left-to-right rank within it, never by x: x is
        // exactly what a later comparison (the safety monitor, teardown) has
        // to be free to say has changed. Matches the id scheme already on
        // record in labels.json ("com.apple.MenuBarAgent#0").
        var itemFrames = [String: ItemFrame]()
        var rankByBundle = [String: Int]()
        for item in items where item.bundleID != BarScan.menuBarAgentBundleID {
            let rank = rankByBundle[item.bundleID, default: 0]
            rankByBundle[item.bundleID] = rank + 1
            let frameID = "\(item.bundleID)#\(rank)"
            itemFrames[frameID] = ItemFrame(id: frameID, minX: item.minX, minY: item.minY, width: item.width, height: item.height)
        }
        let agentFrames = items
            .filter { $0.bundleID == BarScan.menuBarAgentBundleID }
            .map { AgentFrame(minX: $0.minX, minY: $0.minY, width: $0.width) }

        return ObservationSample(
            time: ProcessInfo.processInfo.systemUptime,
            before: before,
            after: after,
            agentFrames: agentFrames,
            itemFrames: itemFrames
        )
    }
}
