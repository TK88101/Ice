//  BlindPopover.swift
//  dualband
//
//  A sacrificial status item that opens a popover, not a menu (plan
//  2026-11-15-blind-at-length, R4): pressing it returns at once with the
//  popover up. Run from its own bundle (`run-blind.sh` assembles it under
//  `com.icespike4.protected`), controlled over stdin, never by signals.
//
//    dualband blind-popover --controller <pid> --identifier <id> --autosave <name>
//    stdin: `close` closes the popover; `quit` or end of input exits.
//    stdout: `popover open`, `popover close`.

import AppKit

final class BlindPopover: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let identifier: String
    private let autosave: String
    private var item: NSStatusItem?
    private let popover = NSPopover()

    init(identifier: String, autosave: String) {
        self.identifier = identifier
        self.autosave = autosave
    }

    static func say(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    /// Runs the helper until its controller ends, its input ends, or 15 minutes pass.
    static func main(arguments: [String]) -> Never {
        func option(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        guard let controller = option("--controller").flatMap({ pid_t($0) }), let identifier = option("--identifier"),
              let autosave = option("--autosave"), kill(controller, 0) == 0
        else {
            fail("usage: dualband blind-popover --controller <pid> --identifier <id> --autosave <name>")
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = BlindPopover(identifier: identifier, autosave: autosave)
        application.delegate = delegate

        // The owner's bar must never keep this item: the controller's end, the input's end and a cap all end it.
        let watch = DispatchSource.makeProcessSource(identifier: controller, eventMask: .exit, queue: .main)
        watch.setEventHandler { exit(0) }
        watch.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + 900) { exit(0) }
        let input = DispatchSource.makeReadSource(fileDescriptor: FileHandle.standardInput.fileDescriptor, queue: .main)
        var buffer = Data()
        input.setEventHandler {
            let chunk = FileHandle.standardInput.availableData
            guard !chunk.isEmpty else { exit(0) }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(data: buffer[buffer.startIndex..<newline], encoding: .utf8)?.trimmingCharacters(in: .whitespaces)
                buffer.removeSubrange(buffer.startIndex...newline)
                switch line {
                case "close": delegate.popover.performClose(nil)
                case "quit": exit(0)
                default: break
                }
            }
        }
        input.resume()
        withExtendedLifetime((watch, input, delegate)) {
            application.run()
        }
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: 22)
        item.autosaveName = autosave
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
        item.button?.setAccessibilityIdentifier(identifier)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        self.item = item
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: 60))
        popover.contentViewController = controller
        // Stays up until told to close: the runner decides how long it shows.
        popover.behavior = .applicationDefined
        popover.delegate = self
        Self.say("up {\"pid\":\(getpid())}")
    }

    @objc private func toggle() {
        guard let button = item?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        Self.say("popover open")
    }

    func popoverDidClose(_ notification: Notification) {
        Self.say("popover close")
    }
}
