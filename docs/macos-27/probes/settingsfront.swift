// settingsfront -- the settings pass's own front app (plan
// 2026-11-12-settings-cleanup): a regular app with three title menus and one
// small titled window, so that "a click elsewhere", "another app comes to the
// front" and "the front app's menus" have a target that is nobody's work.
//
//   settingsfront --controller <pid> [--lifetime <s>]
//
// Prints `up {"pid":..,"window":[x,y,w,h]}` (the window in screen points, top
// left origin). Ends on `quit` or EOF on stdin, when the controller exits, or
// after the lifetime (default 600 s). Side effects: a Dock icon and a window
// while it runs; it comes to the front only when something activates it.
import AppKit

func option(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

guard let controller = option("--controller").flatMap({ pid_t($0) }) else {
    FileHandle.standardError.write(Data("usage: settingsfront --controller <pid> [--lifetime <s>]\n".utf8))
    exit(2)
}
let lifetime = option("--lifetime").flatMap(Double.init) ?? 600

let application = NSApplication.shared
application.setActivationPolicy(.regular)

let main = NSMenu()
let appItem = NSMenuItem()
appItem.submenu = NSMenu()
main.addItem(appItem)
for title in ["Alpha", "Beta", "Gamma"] {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: title)
    submenu.addItem(withTitle: title, action: nil, keyEquivalent: "")
    item.submenu = submenu
    main.addItem(item)
}
application.mainMenu = main

let window = NSWindow(
    contentRect: NSRect(x: 120, y: 320, width: 320, height: 200),
    styleMask: [.titled], backing: .buffered, defer: false
)
window.title = "settingsfront"
window.isReleasedWhenClosed = false
// Above the owner's windows while their app is in front, so a click meant for
// this window cannot land in one of theirs.
window.level = .floating
window.orderFrontRegardless()

let exitWatch = DispatchSource.makeProcessSource(identifier: controller, eventMask: .exit, queue: .main)
exitWatch.setEventHandler { exit(0) }
exitWatch.resume()
DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { exit(0) }

let input = DispatchSource.makeReadSource(fileDescriptor: 0, queue: .main)
input.setEventHandler {
    let data = FileHandle.standardInput.availableData
    if data.isEmpty || String(decoding: data, as: UTF8.self).contains("quit") { exit(0) }
}
input.resume()

DispatchQueue.main.async {
    let screenHeight = NSScreen.screens.first?.frame.height ?? 0
    let frame = window.frame
    let report: [String: Any] = [
        "pid": Int(getpid()),
        "window": [Double(frame.minX), Double(screenHeight - frame.maxY), Double(frame.width), Double(frame.height)],
    ]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(Data("up ".utf8) + data + Data("\n".utf8))
    }
}
application.run()
