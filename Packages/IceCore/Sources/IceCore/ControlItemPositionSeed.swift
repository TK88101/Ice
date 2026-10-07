/// The preferred positions Ice seeds for its own status items so that they
/// are added to the right of the existing ones: the icon rightmost, the hidden
/// divider left of it (upstream's `ControlItem.preflightSetup`).
///
/// On macOS 27 a preferred position of 0 is read as none and the item lands
/// leftmost (MEASURED 27.0.1 26A434, plan 2026-10-07-icebar-menu-frame-fix,
/// section 13), which put the icon left of the hidden divider: no visible
/// section at all. Positive values order items from the right, smallest
/// rightmost, so the icon gets a small positive value there.
public enum ControlItemPositionSeed {
    public enum Item: Sendable {
        case visible
        case hidden
        case alwaysHidden
    }

    /// Between 0 (none on 27) and the hidden divider's 1.
    public static let visibleOnMacOS27 = 0.1
    static let hidden = 1.0

    /// The value to store, or `nil` to leave what is stored.
    public static func seed(for item: Item, stored: Double?, isMacOS27: Bool) -> Double? {
        switch item {
        case .visible:
            if isMacOS27 {
                return stored == nil || stored == 0 ? visibleOnMacOS27 : nil
            }
            return stored == nil ? 0 : nil
        case .hidden:
            return stored == nil ? hidden : nil
        case .alwaysHidden:
            return nil
        }
    }
}
