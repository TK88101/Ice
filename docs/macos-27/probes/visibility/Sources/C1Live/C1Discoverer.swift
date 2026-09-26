import IceCore
import MenuBarDetectorFeed
import MenuBarDiscovery

/// I4 (section 2's last paragraph): "a C1 discoverer records the spacer's
/// real rest frame and makes its `minX` the divider; Target is the only
/// section item, Protected is supplied explicitly as the reference; the
/// discoverer rejects the read unless Target is the sole item left of the
/// divider and Protected lies right of it." Compare
/// `StandInDividerDiscoverer` in `vizprobe/StageShared.swift`, which stands
/// in a divider the same way for the 2026-09-23 plan's two-helper
/// composition checks but never rejects a read -- C1's own geometry
/// depends on the spacer actually being where section 2 puts it, so this
/// wrapper checks that before handing anything downstream a divider at all.
public struct C1Discoverer: Discovering {
    public let base: any Discovering
    public let targetKey: ItemKey
    public let spacerKey: ItemKey
    public let protectedKey: ItemKey

    public init(base: any Discovering, targetKey: ItemKey, spacerKey: ItemKey, protectedKey: ItemKey) {
        self.base = base
        self.targetKey = targetKey
        self.spacerKey = spacerKey
        self.protectedKey = protectedKey
    }

    /// `nil` when the base pass itself produced nothing, or when this
    /// pass's composition does not match section 2's intended order --
    /// there is no partial or "recorded" outcome here, only accept or
    /// reject (I4's own row: "rejects the read otherwise").
    public func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? {
        guard let result = await base.discover(previous: previous) else { return nil }
        let set = result.set

        guard let spacerFrame = set.items.first(where: { $0.key == spacerKey })?.frame else { return nil }
        guard let protectedFrame = set.items.first(where: { $0.key == protectedKey })?.frame else { return nil }
        guard set.items.contains(where: { $0.key == targetKey }) else { return nil }

        let divider = spacerFrame.minX
        let leftOfDivider = set.items.filter { ($0.frame?.minX ?? .infinity) < divider }
        guard leftOfDivider.count == 1, leftOfDivider[0].key == targetKey else { return nil }
        guard protectedFrame.minX >= divider else { return nil }

        let dividerReading = DividerReading.make(
            frame: BarRect(minX: divider, minY: spacerFrame.minY, width: 1, height: spacerFrame.height),
            in: result.bounds
        )
        // The spacer stays in `items` (section 2: "the spacer is carried
        // as an observed item in baseline and verification") -- only the
        // divider changes; nothing here filters the roster.
        let composed = DiscoveredItemSet(
            items: set.items,
            visibleControlItem: set.visibleControlItem,
            hiddenDivider: dividerReading,
            alwaysHiddenDivider: set.alwaysHiddenDivider,
            // G1 (Amendment v7): the raw harness's own read is always
            // `.notRead` (`HarnessProcesses` drops this process's own
            // `isSelf` read before `ItemCatalog.build` ever sees it) --
            // that has nothing to do with whether C1's own composed
            // divider is usable, since C1 supplies it itself from the
            // spacer's `minX`, not from the harness's own-process read.
            // Forwarding `set.ownRead` unchanged made `CheckPlan.make`
            // reject every real composed set as `.skip(.dividerUnavailable)`.
            ownRead: .ok,
            systemElements: set.systemElements,
            dropped: set.dropped,
            staleProcesses: set.staleProcesses,
            completeness: set.completeness
        )
        return DiscoveryResult(
            set: composed, duration: result.duration, origin: result.origin, bounds: result.bounds,
            nextCursor: result.nextCursor, quarantined: result.quarantined, enumeratedPIDs: result.enumeratedPIDs
        )
    }
}
