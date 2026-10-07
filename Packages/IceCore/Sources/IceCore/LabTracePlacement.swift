/// What one discovery pass says about where Ice's own items and the other
/// status items sit, as frames and counts only, never a name (plan
/// 2026-10-07-icebar-preference-hiding, S2 design T2a). The trace emits one
/// per pass, so its oracle -- `hidden divider | the other items | icon` -- is
/// judged on a single snapshot.
public struct LabTracePlacement: Equatable, Sendable {
    public let icon: BarRect?
    public let hiddenDivider: BarRect?
    public let hiddenDividerUsable: Bool
    public let alwaysHiddenDivider: BarRect?
    public let alwaysHiddenDividerUsable: Bool
    /// `PreferenceHidingPreconditions.iconPlacement`: `nil` when the icon is
    /// right of the hidden divider.
    public let iconPlacement: PreferenceHidingIconPlacement?
    /// On the bar, mid-x left of the divider's minX, the section boundary:
    /// what the hidden section would hold.
    public let othersLeftOfHiddenDivider: Int
    /// On the bar, from the divider's minX up to the icon's mid-x.
    public let othersBetween: Int
    /// On the bar, at or right of the icon's mid-x.
    public let othersRightOfIcon: Int
    /// On the bar (`.onBar` or `.stacked`), wherever: needs no boundary, so a
    /// pass taken before Ice's items exist has it too.
    public let othersOnBar: Int
    /// Not on the bar (no frame, or parked: the divider cannot carry such an
    /// item and it never becomes a member, plan D-a), or no boundary to place
    /// them by.
    public let othersUnplaced: Int
    public let isComplete: Bool
    public let ownReadOk: Bool

    public init(set: DiscoveredItemSet) {
        let iconFrame = set.visibleControlItem?.frame
        icon = iconFrame
        hiddenDivider = set.hiddenDivider?.frame
        hiddenDividerUsable = set.hiddenDivider?.isUsable ?? false
        alwaysHiddenDivider = set.alwaysHiddenDivider?.frame
        alwaysHiddenDividerUsable = set.alwaysHiddenDivider?.isUsable ?? false
        iconPlacement = PreferenceHidingPreconditions.iconPlacement(icon: iconFrame, divider: set.hiddenDivider)
        isComplete = set.completeness == .complete
        ownReadOk = set.ownRead == .ok

        let regions = set.items.map { Self.region(of: $0, icon: iconFrame, divider: set.hiddenDivider) }
        func count(_ region: Region) -> Int {
            regions.count { $0 == region }
        }
        othersLeftOfHiddenDivider = count(.leftOfHiddenDivider)
        othersBetween = count(.between)
        othersRightOfIcon = count(.rightOfIcon)
        othersUnplaced = count(.unplaced)
        othersOnBar = set.items.count { $0.position == .onBar || $0.position == .stacked }
    }

    private enum Region {
        case leftOfHiddenDivider
        case between
        case rightOfIcon
        case unplaced
    }

    private static func region(of item: DiscoveredItem, icon: BarRect?, divider: DividerReading?) -> Region {
        guard
            item.position != .parked,
            let frame = item.frame, frame.hasFiniteComponents,
            let icon, icon.hasFiniteComponents,
            let divider, divider.isUsable, let dividerFrame = divider.frame, dividerFrame.hasFiniteComponents
        else {
            return .unplaced
        }
        if frame.midX < dividerFrame.minX { return .leftOfHiddenDivider }
        return frame.midX < icon.midX ? .between : .rightOfIcon
    }
}
