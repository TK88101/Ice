/// D16's two numeric gates on the verifier: whether there is enough free bar
/// to capture, and whether a previous baseline is still trustworthy enough
/// to skip a fresh one.

/// Whether the bar has enough free room right of the notch for a capture to
/// run without the capture indicator being what pushes an item behind the
/// overflow chevron (plan section 1, "the check is skipped when the bar has
/// under 41 pt free").
public enum RoomGuard {
    public static let minimumFreeRoom: Double = 41.0

    /// `free` = the `minX` of the leftmost on-bar *listed* item (own items
    /// included -- `set.visibleControlItem` counts, `set.items` does not
    /// include own items at all) minus `notchMaxX`. No listed on-bar item at
    /// all -> room is assumed.
    public static func hasRoom(set: DiscoveredItemSet, notchMaxX: Double) -> Bool {
        let minXs: [Double] = set.listedItems
            .filter { $0.position == .onBar }
            .compactMap { $0.frame?.minX }
        guard let leftmost = minXs.min() else { return true }
        return leftmost - notchMaxX >= minimumFreeRoom
    }
}

/// Whether a previously captured baseline can stand in for a fresh one
/// (D16): the fresh AX read must hold exactly the baseline's framed keys, each
/// at essentially the same frame, the baseline must not be too old, and it
/// must have been built for the same roster the fresh plan names.
public enum BaselineReuse {
    public static let maxAge: Double = 600.0
    public static let tolerance: Double = 0.5

    /// `freshFrames` are the fresh plan's own framed keys: one the baseline
    /// never had is ink it cannot explain, so it is as disqualifying as one
    /// that went missing.
    public static func isReusable(baselineFrames: [ItemKey: BarRect], freshFrames: [ItemKey: BarRect], age: Double) -> Bool {
        guard age <= maxAge, freshFrames.count == baselineFrames.count else { return false }
        for (key, baseline) in baselineFrames {
            guard let fresh = freshFrames[key] else { return false }
            guard abs(fresh.minX - baseline.minX) <= tolerance, abs(fresh.width - baseline.width) <= tolerance else { return false }
        }
        return true
    }

    /// Whether a baseline built for `baselineTargets` and `baselineSkipped`
    /// covers the roster a fresh plan names (plan Deviation 5): otherwise
    /// `verify` would report items that left the section and none for items
    /// that joined it.
    public static func sameRoster(
        baselineTargets: [ItemKey],
        baselineSkipped: [ItemKey: CheckSkipReason],
        freshTargets: [ItemKey],
        freshSkipped: [ItemKey: CheckSkipReason]
    ) -> Bool {
        Set(baselineTargets) == Set(freshTargets) && baselineSkipped == freshSkipped
    }
}
