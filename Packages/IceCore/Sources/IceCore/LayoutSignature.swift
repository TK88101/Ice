/// The layout a hiding length was applied in (plan 2026-10-03-icebar-build, D1;
/// re-aimed by plan 2026-10-07-icebar-preference-hiding, T3b design): what can
/// make the roster wrong, and what the bar is shown with.
/// `PreferenceHidingLayoutChange.between` names a difference.
///
/// Left out on purpose: item frames (they move with Ice's own divider, so Ice
/// would invalidate itself) and `MenuBarAgent`'s items (never discovered, and
/// Ice's own captures summon the capture indicator).
public struct LayoutSignature: Hashable, Sendable {
    /// Every third-party item a pass read, parked ones included, in a stable
    /// order: an item that appears or goes anywhere changes it.
    public let items: [TagKey]
    /// The roster's tags, in its order.
    public let members: [TagKey]
    public let frontmostPID: Int32?
    /// The application menu's right edge to the whole point; `nil` when it
    /// could not be read.
    public let menuMaxX: Int?
    public let displayID: UInt32?
    public let spaceID: UInt64?

    public init(
        items: [TagKey],
        members: [TagKey],
        frontmostPID: Int32?,
        menuMaxX: Double?,
        displayID: UInt32?,
        spaceID: UInt64?
    ) {
        self.items = items
        self.members = members
        self.frontmostPID = frontmostPID
        self.menuMaxX = menuMaxX.flatMap { $0.isFinite ? Int(exactly: $0.rounded()) : nil }
        self.displayID = displayID
        self.spaceID = spaceID
    }
}
