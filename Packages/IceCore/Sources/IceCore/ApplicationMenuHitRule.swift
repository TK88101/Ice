/// Whether a point is on the application menu (plan
/// 2026-10-07-icebar-menu-frame-fix, F2b): upstream's
/// `HIDEventManager.isMouseInsideApplicationMenu` test, moved here so it can be
/// tested. The menu's frame is widened to the screen's left edge, and the
/// edges are `CGRect.contains`'s: min inclusive, max exclusive.
public enum ApplicationMenuHitRule {
    /// `false` without a frame: then a click on the menu reads as empty bar
    /// space, which is what the macOS 27 reader's nil did before the fix.
    public static func contains(x: Double, y: Double, menuFrame: BarRect?, screenMinX: Double) -> Bool {
        guard let menuFrame else {
            return false
        }
        return x >= screenMinX && x < menuFrame.maxX
            && y >= menuFrame.minY && y < menuFrame.maxY
    }
}
