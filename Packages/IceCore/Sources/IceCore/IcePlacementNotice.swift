/// What Ice tells the owner about where its own icon sits (plan
/// 2026-10-07-icebar-preference-hiding, S2 design T2c): on macOS 27 in IceBar
/// mode everything left of the hidden divider is hidden, Ice's icon with it,
/// so with the icon there Ice hides nothing and says how to repair it.
public enum IcePlacementNotice: Equatable, Sendable {
    /// Ice's icon was read on the bar, left of its hidden divider.
    case iconLeftOfDivider

    /// The layout pane's line, and the hiding status line for the same state.
    /// The repair is the owner's Command-drag; whether macOS keeps a dragged
    /// position is not promised (not measured: STATUS "Remembered positions").
    public var message: String {
        switch self {
        case .iconLeftOfDivider:
            "Ice's icon is left of its hidden-section divider, so Ice hides nothing. "
                + "Hold Command and drag Ice's icon to the right of the divider."
        }
    }

    /// Where Ice holds its icon to be after a discovery pass. Only a pass whose
    /// hidden boundary is trusted may say: the divider read at standard
    /// length, settled (`DiscoveredCachePlan` placed the sections by it). At a
    /// hiding length the divider's left edge is far left of where it draws
    /// the boundary, so the icon reads right of it, or the divider unusable,
    /// wherever the icon is; what Ice held from the last trusted pass stands.
    /// - Parameters:
    ///   - held: the placement after the previous pass; `nil` is "right of
    ///     the divider", also before any pass.
    ///   - read: `PreferenceHidingPreconditions.iconPlacement` for this pass.
    public static func placement(
        held: PreferenceHidingIconPlacement?,
        read: PreferenceHidingIconPlacement?,
        hiddenBoundaryTrusted: Bool
    ) -> PreferenceHidingIconPlacement? {
        hiddenBoundaryTrusted ? read : held
    }

    /// The notice owed for the placement Ice holds, or `nil`.
    /// - Parameters:
    ///   - placement: `placement(held:read:hiddenBoundaryTrusted:)`; `nil` is
    ///     "right of the divider". An icon or a divider that could not be
    ///     read is not an inversion Ice saw, and is not reported as one.
    ///   - isIceBarMode: outside it the divider hides nothing by its place
    ///     alone, and where the icon sits is the owner's choice.
    ///   - isDragging: a Command-drag of a menu bar item is under way; the
    ///     owner is arranging, possibly doing the repair.
    public static func notice(
        placement: PreferenceHidingIconPlacement?,
        isIceBarMode: Bool,
        isDragging: Bool
    ) -> IcePlacementNotice? {
        guard isIceBarMode, !isDragging, placement == .iconLeftOfDivider else { return nil }
        return .iconLeftOfDivider
    }
}
