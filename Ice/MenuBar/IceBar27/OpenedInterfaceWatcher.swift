//
//  OpenedInterfaceWatcher.swift
//  Ice
//

import Cocoa
import IceCore

/// The live half of `OpenedInterfaceRule` (plan 2026-11-15-blind-at-length,
/// D3): the windows on screen and one window's standing, by the public
/// window list (ids, owners and layers need no Screen Recording).
@available(macOS 27, *)
enum OpenedInterfaceWatcher {
    private static let levels = OpenedInterfaceRule.Levels(
        popUpMenu: Int(CGWindowLevelForKey(.popUpMenuWindow)),
        status: Int(CGWindowLevelForKey(.statusWindow)),
        mainMenu: Int(CGWindowLevelForKey(.mainMenuWindow))
    )

    /// Every window on screen, in the window list's order.
    static func onScreenWindows() -> [OpenedInterfaceRule.Window] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard
                let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            else {
                return nil
            }
            return OpenedInterfaceRule.Window(id: id, pid: pid)
        }
    }

    /// Whether the window still shows; a window that is gone does not.
    static func isShowing(_ windowID: UInt32) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]] ?? []
        guard
            let info = list.first,
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
            let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        else {
            return false
        }
        return OpenedInterfaceRule.isShowing(
            layer: layer,
            isOnScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
            isAppActive: NSRunningApplication(processIdentifier: pid)?.isActive ?? false,
            levels: levels
        )
    }
}
