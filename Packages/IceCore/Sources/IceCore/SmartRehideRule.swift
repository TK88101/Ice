/// The smart rehide asks which window a click landed in. On macOS 27 the
/// system keeps full-screen windows of its own above every app (Notification
/// Centre's at level 21, the Dock's at 20; window list of 26A434, 2026-11-12),
/// and each has a title: taken for the clicked window, the first stopped the
/// rule for ever and the second let any click through as "the Dock" (plan
/// 2026-11-12-settings-cleanup, case G6). They are passed over.
public enum SmartRehideRule {
    /// The Dock's window level; the overlays are at it or above.
    public static let overlayLayer = 20

    /// Whether a window is one of those overlays: at the Dock's level or
    /// above, and covering the whole of `screen`.
    public static func isSystemOverlay(layer: Int, frame: BarRect, screen: BarRect) -> Bool {
        layer >= overlayLayer
            && frame.minX <= screen.minX && frame.minY <= screen.minY
            && frame.maxX >= screen.maxX && frame.maxY >= screen.maxY
    }
}
