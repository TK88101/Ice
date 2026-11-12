/// When the owner is arranging items on the bar, so Ice must give the real
/// divider and the hidden items back (plan 2026-11-12-hide-at-once, D4): a
/// Command-drag under way, or Command held with the pointer on the menu bar.
/// The second is how a hidden item is taken out: hold Command, the members
/// are drawn again, drag one right of the divider, let go.
public enum IceBarArrangingRule {
    public static func isArranging(isDragging: Bool, isCommandDown: Bool, isPointerOnBar: Bool) -> Bool {
        isDragging || (isCommandDown && isPointerOnBar)
    }
}
