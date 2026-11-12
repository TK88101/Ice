/// Whether a point of the menu bar is on a status item, from the frames the
/// last discovery pass read (plan 2026-11-12-settings-cleanup, 9.5). macOS 27
/// lists no menu bar item windows, so Ice's older test, which asked the window
/// list, called every item empty space: a click on another app's item also
/// showed the IceBar (run 20261112-192750-s6, G3).
public enum MenuBarPointRule {
    /// An item answers clicks in its window, which is wider than the frame
    /// Accessibility gives (a 14 pt frame in a 28 pt window on the helpers).
    public static let margin: Double = 8

    /// - Parameters:
    ///   - itemFrames: every item on the bar that is not Ice's own divider and
    ///     is not hidden by Ice: other apps' items, the system's, Ice's icon.
    ///   - hasReading: a pass has read the bar. Without one every point is
    ///     taken for an item, so nothing is shown on a guess.
    ///
    /// Only `x` is asked: the caller knows the point is on the bar, and an
    /// item's window is as tall as the bar.
    public static func isOnItem(x: Double, itemFrames: [BarRect], hasReading: Bool) -> Bool {
        guard hasReading else { return true }
        return itemFrames.contains { x >= $0.minX - margin && x <= $0.maxX + margin }
    }
}
