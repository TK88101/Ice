/// The preferred positions Ice seeds for its own status items. Before macOS
/// 27 they are upstream's (`ControlItem.preflightSetup`): both added to the
/// right of the existing items, the icon rightmost, the hidden divider left
/// of it.
///
/// On macOS 27 a preferred position of 0 is read as none and the item lands
/// leftmost (MEASURED 27.0.1 26A434, plan 2026-10-07-icebar-menu-frame-fix,
/// section 13), which put the icon left of the hidden divider: no visible
/// section at all. Positive values order items from the right, smallest
/// rightmost, so the icon gets a small positive value there.
///
/// The hidden divider gets none on 27, so that it lands leftmost and a fresh
/// Ice starts as `divider | the other items | icon` (plan
/// 2026-10-07-icebar-preference-hiding, S2 design T2a). Seeded 1, it landed
/// right of every other status item and made all of them hidden-section
/// members; the unseeded always-hidden divider landed left of everything
/// (MEASURED 26A434, run 20261007-231100-cM6U06-trace). A stored value is
/// never replaced: its provenance cannot be told from the number.
public enum ControlItemPositionSeed {
    public enum Item: Sendable {
        case visible
        case hidden
        case alwaysHidden
    }

    /// Positive, so not none on 27, and smaller than any real position.
    public static let visibleOnMacOS27 = 0.1
    static let hiddenBeforeMacOS27 = 1.0

    /// The value to store, or `nil` to leave what is stored.
    public static func seed(for item: Item, stored: Double?, isMacOS27: Bool) -> Double? {
        switch item {
        case .visible:
            if isMacOS27 {
                return stored == nil || stored == 0 ? visibleOnMacOS27 : nil
            }
            return stored == nil ? 0 : nil
        case .hidden:
            return stored == nil && !isMacOS27 ? hiddenBeforeMacOS27 : nil
        case .alwaysHidden:
            return nil
        }
    }
}
