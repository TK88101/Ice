// A sacrificial menu bar item in its own process, for testing whether one process
// can move another process's item. Holds exactly one NSStatusItem with a stable,
// unique accessibility identity. Does nothing else and exposes no IPC -- anything
// that moves it must do so from the outside.
import Cocoa

let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
let isTarget = bundleID.hasSuffix(".target")
let label = isTarget ? "T" : "A"

final class Delegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: 28)
        item.autosaveName = "IceSpike3-\(label)"
        item.button?.title = label
        item.button?.setAccessibilityIdentifier("IceSpike3-\(label)")
        item.button?.setAccessibilityLabel("IceSpike3 \(isTarget ? "target" : "anchor")")
        statusItem = item
        print("\(label) up, pid \(getpid()), bundle \(bundleID)")
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
