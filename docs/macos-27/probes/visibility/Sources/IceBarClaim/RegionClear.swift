// Rules 2-3, `RegionClear` (pre-registration section 3; claim plan R16): no
// cluster of >= 16 px in the region, notch columns excepted and agent frames
// included, differs from the stored image by more than `T_diff`.
import IceCore

public enum RegionClearReason: Equatable, Sendable {
    /// Not the attempt's 6 captures (section 2).
    case captureCount(Int)
    case shapeMismatch(index: Int)
    /// The first capture with a changed cluster, and its largest cluster.
    case changed(index: Int, clusterPx: Int)
}

public enum RegionClearOutcome: Equatable, Sendable {
    /// The largest changed cluster seen (all below the minimum).
    case clear(largestCluster: Int)
    case notClear(RegionClearReason)
}

public enum RegionClear {
    public static func evaluate(baseline: HiddenBaseline, captures: [StripImage],
                                parameters: ClaimParameters = .preRegistered) -> RegionClearOutcome {
        guard captures.count == parameters.observationCaptures else { return .notClear(.captureCount(captures.count)) }
        let stored = baseline.stored
        if let index = captures.firstIndex(where: { $0.width != stored.width || $0.height != stored.height || $0.scale != stored.scale }) {
            return .notClear(.shapeMismatch(index: index))
        }
        var largest = 0
        for (index, capture) in captures.enumerated() {
            var mask = [Bool](repeating: false, count: capture.width * capture.height)
            for y in 0..<capture.height {
                for x in baseline.claimRegion.columns where PixelKit.distance(capture, stored, x, y) > parameters.tDiff {
                    mask[y * capture.width + x] = true
                }
            }
            let top = PixelKit.largestCluster(mask, width: capture.width, height: capture.height)
            if top >= parameters.clusterMinPx { return .notClear(.changed(index: index, clusterPx: top)) }
            largest = max(largest, top)
        }
        return .clear(largestCluster: largest)
    }
}
