/// What pressing a status item on the bar opened, and whether it still shows:
/// while it does, the hidden items stay on the bar (plan
/// 2026-11-15-blind-at-length, D3, the `showing` phase). A menu's press
/// returns when the menu closes; a popover's returns at once, with the popover
/// up. The rule is upstream's for an item it shows for a click
/// (`TemporarilyShownItemContext.isShowingInterface` in `MenuBarItemManager`),
/// kept apart from it because that one is private to window-sourced items.
public enum OpenedInterfaceRule {
    /// The window levels at which a status item's interface shows whichever
    /// app is active: the system's values, given by the caller (IceCore
    /// imports nothing).
    public struct Levels: Equatable, Sendable {
        public let popUpMenu: Int
        public let status: Int
        public let mainMenu: Int

        public init(popUpMenu: Int, status: Int, mainMenu: Int) {
            self.popUpMenu = popUpMenu
            self.status = status
            self.mainMenu = mainMenu
        }
    }

    /// A window on screen and the process that owns it.
    public struct Window: Equatable, Sendable {
        public let id: UInt32
        public let pid: Int32

        public init(id: UInt32, pid: Int32) {
            self.id = id
            self.pid = pid
        }
    }

    /// The window the press opened: the first of `windows` (in the window
    /// list's order) that `pid` owns and that was not on screen `before` the
    /// press was dispatched. The caller looks while the press is out and
    /// once just after it returns, so the window is bound to the press's own
    /// interval, not to whatever that app shows later.
    public static func opened(by pid: Int32, in windows: [Window], before: Set<UInt32>) -> UInt32? {
        windows.first { $0.pid == pid && !before.contains($0.id) }?.id
    }

    /// Whether that window still shows. Off the screen (or gone): no. At a
    /// menu's level, the one below it, the status level or the main menu's:
    /// while on screen. At any other level (a popover, a panel, a window):
    /// while on screen and its app is active, so a window the owner left
    /// open and walked away from does not keep the hidden items on the bar.
    public static func isShowing(layer: Int, isOnScreen: Bool, isAppActive: Bool, levels: Levels) -> Bool {
        guard isOnScreen else { return false }
        let menuLayers = [levels.popUpMenu, levels.popUpMenu - 1, levels.status, levels.mainMenu]
        return menuLayers.contains(layer) || isAppActive
    }
}
