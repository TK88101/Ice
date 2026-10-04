/// D1 (plan 2026-10-03-icebar-build, section 9.2): the layout a calibrated
/// hidden length was measured in. Any difference restores the standard length
/// at once, and a length is reused only for an equal signature.
///
/// Left out on purpose: item frames (they move with Ice's own divider, so Ice
/// would invalidate itself) and `MenuBarAgent`'s items (never discovered, and
/// Ice's own captures summon the capture indicator).
public struct LayoutSignature: Hashable, Sendable {
    /// The items of each section, in bar order.
    public let visible: [String]
    public let hidden: [String]
    public let alwaysHidden: [String]
    public let frontmostPID: Int32?
    /// The application menu's right edge to the whole point; `nil` when it
    /// could not be read.
    public let menuMaxX: Int?
    public let displayID: UInt32?
    public let spaceID: UInt64?

    public init(
        visible: [String],
        hidden: [String],
        alwaysHidden: [String],
        frontmostPID: Int32?,
        menuMaxX: Double?,
        displayID: UInt32?,
        spaceID: UInt64?
    ) {
        self.visible = visible
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
        self.frontmostPID = frontmostPID
        self.menuMaxX = menuMaxX.flatMap { $0.isFinite ? Int(exactly: $0.rounded()) : nil }
        self.displayID = displayID
        self.spaceID = spaceID
    }
}
