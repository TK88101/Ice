// C2's menus role (docs/plans/2026-09-28-c2-protocol.md section 3, T2): the
// frontmost app of a configuration. Its own title menus are plain fixed
// titles ("M01", "M02", ...), rebuilt on each `menus <n>`; the stage reads
// their AX spans and adjusts n until the last title lands in the
// configuration's width class. Nothing here draws a status item.
import AppKit

enum MenusRole {
    static func show(count: Int) {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        appItem.submenu = appMenu
        main.addItem(appItem)
        for index in stride(from: 1, through: count, by: 1) {
            let title = String(format: "M%02d", index)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            submenu.addItem(withTitle: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        NSApplication.shared.mainMenu = main
    }
}
