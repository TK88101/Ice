// swhelper — a sacrificial menu bar item in its own process: T (the target) or
// P (the protected proxy), chosen by the bundle identifier's last component.
//
//   swhelper --controller <pid> --left RRGGBB --right RRGGBB [--length 16] [--lifetime 1800]
//
// Holds exactly one NSStatusItem showing a two-colour marker the controller can
// find in a screen capture. Exposes no IPC: nothing moves it but the menu bar.
// Exits when the controller exits (process-exit source on its pid, which works
// without a parent relationship because helpers are started through `open`),
// and in any case after its lifetime.
import AppKit
import SafeWidthCore

func option(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

func colour(_ hex: String?) -> NSColor? {
    guard let hex, hex.count == 6, let value = UInt32(hex, radix: 16) else {
        return nil
    }
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

/// Left half one colour, right half the other. Not a template image, so the menu
/// bar draws the colours instead of tinting them.
func markerImage(left: NSColor, right: NSColor, side: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
        left.setFill()
        NSRect(x: 0, y: 0, width: rect.width / 2, height: rect.height).fill()
        right.setFill()
        NSRect(x: rect.width / 2, y: 0, width: rect.width / 2, height: rect.height).fill()
        return true
    }
    image.isTemplate = false
    return image
}

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: swhelper --controller <pid> --left RRGGBB --right RRGGBB\n".utf8))
    exit(64)
}

func required<T>(_ value: T?) -> T {
    guard let value else {
        usage()
    }
    return value
}

// Plain globals rather than `guard let` bindings: top-level `guard let` names are
// locals, which the delegate class below cannot capture.
let controller: pid_t = required(option("--controller").flatMap { pid_t($0) })
let left: NSColor = required(colour(option("--left")))
let right: NSColor = required(colour(option("--right")))
guard kill(controller, 0) == 0 else {
    exit(0)
}

let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
let role = bundleID.components(separatedBy: ".").last ?? "unknown"
let length = option("--length").flatMap(Double.init) ?? 16
let lifetime = option("--lifetime").flatMap(Double.init) ?? 1800

let controllerExit = DispatchSource.makeProcessSource(identifier: controller, eventMask: .exit, queue: .main)
controllerExit.setEventHandler { exit(0) }
controllerExit.resume()
DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { exit(0) }

final class Delegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: CGFloat(length))
        item.autosaveName = "IceSpike4-\(role)"
        item.button?.image = markerImage(left: left, right: right, side: CGFloat(MarkerGeometry.helperSidePt))
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityIdentifier("IceSpike4-\(role)")
        self.item = item
        print("\(role) up, pid \(getpid()), bundle \(bundleID)")
    }
}

let application = NSApplication.shared
let delegate = Delegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
