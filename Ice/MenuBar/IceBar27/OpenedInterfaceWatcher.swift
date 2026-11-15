//
//  OpenedInterfaceWatcher.swift
//  Ice
//

import Cocoa
import IceCore

/// The live half of `OpenedInterfaceRule` (plan 2026-11-15-blind-at-length,
/// D3), on the window list upstream's own "shown for a click" uses
/// (`MenuBarItemManager.temporarilyShow`).
@available(macOS 27, *)
enum OpenedInterfaceWatcher {
    private static let levels = OpenedInterfaceRule.Levels(
        popUpMenu: Int(CGWindowLevelForKey(.popUpMenuWindow)),
        status: Int(CGWindowLevelForKey(.statusWindow)),
        mainMenu: Int(CGWindowLevelForKey(.mainMenuWindow))
    )

    /// The windows on screen now: what was up before a press.
    static func onScreenWindowIDs() -> Set<CGWindowID> {
        Set(Bridging.getWindowList(option: .onScreen))
    }

    /// The first window of `pid` on screen now that was not among `before`.
    static func opened(by pid: pid_t, before: Set<CGWindowID>) -> CGWindowID? {
        let windows = WindowInfo.createWindows(option: .onScreen).map { OpenedInterfaceRule.Window(id: $0.windowID, pid: $0.ownerPID) }
        return OpenedInterfaceRule.opened(by: pid, in: windows, before: before)
    }

    /// Whether the window still shows; a window that is gone does not.
    static func isShowing(_ windowID: CGWindowID) -> Bool {
        guard let window = WindowInfo(windowID: windowID) else {
            return false
        }
        return OpenedInterfaceRule.isShowing(
            layer: window.layer, isOnScreen: window.isOnScreen,
            isAppActive: window.owningApplication?.isActive ?? false, levels: levels
        )
    }
}
