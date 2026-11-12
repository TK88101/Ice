/// When the owner is arranging items on the bar, so Ice must give the real
/// divider and the hidden items back (plan 2026-11-12-hide-at-once, D4): a
/// Command-drag under way, or Command held with the pointer on the menu bar.
/// The second is how a hidden item is taken out: hold Command, the members
/// are drawn again, drag one right of the divider, let go.
public enum IceBarArrangingRule {
    public static func isArranging(isDragging: Bool, isCommandDown: Bool, isPointerOnBar: Bool) -> Bool {
        isDragging || (isCommandDown && isPointerOnBar)
    }

    /// How long a re-read that never completes keeps the bar from Ice.
    public static let rereadLimit: Double = 5

    /// Whether the bar is still the owner's: while they arrange, and after it
    /// until a pass that began later has read where everything was left. A
    /// roster read during the drag is of the drag: hiding on it kept an item
    /// the owner had just taken out listed as hidden (run 20261112-192750-s6,
    /// D2: the length applied 0.35 s after a pass taken mid-drag). Times are
    /// one clock's; `rereadAt` is when the last completed pass began.
    public static func holdsBarForOwner(isArranging: Bool, arrangingEndedAt: Double?, rereadAt: Double?, now: Double) -> Bool {
        if isArranging { return true }
        guard let arrangingEndedAt else { return false }
        if let rereadAt, rereadAt >= arrangingEndedAt { return false }
        return now - arrangingEndedAt < rereadLimit
    }
}
