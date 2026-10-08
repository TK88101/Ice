/// What one discovery pass says about where Ice's own items and the other
/// status items sit, as frames and counts only, never a name (plan
/// 2026-10-07-icebar-preference-hiding, S2 design T2a). The trace emits one
/// per pass, so its oracle -- `hidden divider | the other items | icon` -- is
/// judged on a single snapshot.
public struct LabTracePlacement: Equatable, Sendable {
    public let icon: BarRect?
    /// The icon's own position is `.onBar` or `.stacked`; when it is not,
    /// `iconPlacement` is `.iconUnreadable` whatever the frame says.
    public let iconOnBar: Bool
    public let hiddenDivider: BarRect?
    public let hiddenDividerUsable: Bool
    public let alwaysHiddenDivider: BarRect?
    public let alwaysHiddenDividerUsable: Bool
    /// `PreferenceHidingPreconditions.iconPlacement` on the discovered icon:
    /// `nil` when it is on the bar and right of the hidden divider.
    public let iconPlacement: PreferenceHidingIconPlacement?
    /// `IcePlacementNotice.notice` for that placement in the state the trace
    /// runs in: IceBar mode, no drag (S2 design T2c, the `inv` variant).
    public let notice: IcePlacementNotice?
    /// On the bar, mid-x left of the hidden divider's boundary
    /// (`DividerReading.boundaryMinX`). Geometry of this pass only: the
    /// membership rule shares the boundary and the on-bar condition but also
    /// asks for a trusted divider state and remembers previous members, so
    /// this is not "membership resolves to these". Needs no icon.
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
    /// How many processes' reads failed in an incomplete pass; a number, so
    /// a failed run says why without naming anything.
    public let failedReads: Int
    public let ownReadOk: Bool

    public init(set: DiscoveredItemSet) {
        let iconFrame = set.visibleControlItem?.frame
        icon = iconFrame
        iconOnBar = set.visibleControlItem?.position.isOnBar ?? false
        hiddenDivider = set.hiddenDivider?.frame
        hiddenDividerUsable = set.hiddenDivider?.isUsable ?? false
        alwaysHiddenDivider = set.alwaysHiddenDivider?.frame
        alwaysHiddenDividerUsable = set.alwaysHiddenDivider?.isUsable ?? false
        iconPlacement = PreferenceHidingPreconditions.iconPlacement(icon: set.visibleControlItem, divider: set.hiddenDivider)
        notice = IcePlacementNotice.notice(placement: iconPlacement, isIceBarMode: true, isDragging: false)
        isComplete = set.completeness == .complete
        failedReads = if case .incomplete(let failedPIDs) = set.completeness { failedPIDs.count } else { 0 }
        ownReadOk = set.ownRead == .ok

        let regions = set.items.map { Self.region(of: $0, icon: iconFrame, divider: set.hiddenDivider) }
        func count(_ region: Region) -> Int {
            regions.count { $0 == region }
        }
        othersLeftOfHiddenDivider = count(.leftOfHiddenDivider)
        othersBetween = count(.between)
        othersRightOfIcon = count(.rightOfIcon)
        othersUnplaced = count(.unplaced)
        othersOnBar = set.items.count(where: \.position.isOnBar)
    }

    private enum Region {
        case leftOfHiddenDivider
        case between
        case rightOfIcon
        case unplaced
    }

    private static func region(of item: DiscoveredItem, icon: BarRect?, divider: DividerReading?) -> Region {
        guard item.position.isOnBar, let midX = item.frame?.midX, midX.isFinite, let boundary = divider?.boundaryMinX else {
            return .unplaced
        }
        if midX < boundary { return .leftOfHiddenDivider }
        guard let icon, icon.hasFiniteComponents else { return .unplaced }
        return midX < icon.midX ? .between : .rightOfIcon
    }
}
