// swfront — F, the frontmost app whose menu width the experiment controls.
//
//   swfront --controller <pid> --menus <n> --title <text> [--lifetime 1800]
//
// A regular app with the app menu plus `n` menus titled `text` followed by a
// number, so the right edge of the app menus moves with n and the title length.
// Exits with the controller or after its lifetime.
import AppKit

func option(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

guard let controllerText = option("--controller"), let controller = pid_t(controllerText) else {
    FileHandle.standardError.write(Data("usage: swfront --controller <pid> --menus <n> --title <text>\n".utf8))
    exit(64)
}
guard kill(controller, 0) == 0 else {
    exit(0)
}

let menuCount = option("--menus").flatMap(Int.init) ?? 0
let title = option("--title") ?? "Menu"
let lifetime = option("--lifetime").flatMap(Double.init) ?? 1800

let controllerExit = DispatchSource.makeProcessSource(identifier: controller, eventMask: .exit, queue: .main)
controllerExit.setEventHandler { exit(0) }
controllerExit.resume()
DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { exit(0) }

func buildMainMenu() -> NSMenu {
    let main = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    main.addItem(appItem)
    for index in 0..<menuCount {
        let item = NSMenuItem()
        let menu = NSMenu(title: "\(title)\(index + 1)")
        menu.addItem(withTitle: "Item", action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
    return main
}

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        // A window, far from the menu bar: an app with no windows loses the front
        // as soon as anything else is launched, and then its menus are not the ones
        // on the bar. The bottom-left corner keeps it away from the strip we capture
        // and from what shows through the translucent bar.
        let window = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 160, height: 90),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = "F"
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate()
        print("F up, pid \(getpid()), \(menuCount) menus titled \(title)")
    }

    /// Something else took the front; take it back, so the menus on the bar stay
    /// this config's. The controller voids any trial where this did not hold.
    func applicationDidResignActive(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            NSApp.activate()
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }
}

let application = NSApplication.shared
let delegate = Delegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
