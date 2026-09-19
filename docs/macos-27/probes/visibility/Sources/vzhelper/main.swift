// vzhelper -- one sacrificial menu bar item for T13's live harness
// (docs/plans/2026-09-19-visibility-adapter.md, section 6).
//
//   vzhelper --controller <pid> --role target|reference|twin
//
// Holds exactly one NSStatusItem, drawn as a stroked template glyph -- never
// a filled block. Deviation 6 of the plan's ledger records that the old
// helper's solid two-colour square has no background pixel inside its own
// ink bounding box, so IceCore's core-background invariant
// (Packages/IceCore/Sources/IceCore/Template.swift, `.tooLittleBackground`)
// rejects it outright: a template that is all ink matches any ink blob,
// which is exactly the false positive the invariant exists to catch. This
// helper's glyph is an open bracket with a real gap and an off-centre
// accent, so its own bounding box always keeps clear background pixels.
//
// Controlled over stdin, one command per line -- never signals: a recycled
// pid would make a stray SIGUSR1 dangerous to whatever process reused it.
//   hide  -> isVisible = false
//   show  -> isVisible = true
//   quit  -> exit(0)
//   EOF   -> exit(0), same as `quit`
//
// Two more deadmen, because the user's bar must never keep this item because
// the controller crashed or forgot about it:
//   - a DispatchSource process-exit watch on --controller (mirrors
//     probes/safewidth/Sources/swhelper/main.swift's own controller watch);
//   - a fixed lifetime cap, independent of whether the controller is alive.
import AppKit

func option(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: vzhelper --controller <pid> --role target|reference|twin\n".utf8))
    exit(64)
}

func required<T>(_ value: T?) -> T {
    guard let value else { usage() }
    return value
}

enum Role: String {
    case target
    case reference
    case twin
}

// Plain globals, not `guard let` locals: the delegate class below and the
// stdin handler both need to capture them, and a top-level `guard let`
// binding is a local that an escaping closure cannot see.
let controller: pid_t = required(option("--controller").flatMap { pid_t($0) })
let role: Role = required(option("--role").flatMap(Role.init(rawValue:)))
guard kill(controller, 0) == 0 else {
    exit(0)
}

let itemLengthPt: CGFloat = 12
let lifetimeCapSeconds = 300.0

/// A stroked template glyph, sized to leave real background inside its own
/// ink bounding box. `target` and `twin` draw the identical shape on
/// purpose: the ambiguity control of the plan's step 6.1(6c) depends on the
/// matcher being unable to tell them apart. `reference` draws the mirrored
/// shape (open on the opposite side, accent in the opposite corner) so its
/// template cannot collide with target's -- TemplateBaseline's uniqueness
/// rule (plan 3.2, rule 6) rejects two accepted templates whose matches
/// overlap.
func glyphImage(for role: Role, side: CGFloat) -> NSImage {
    let drawnAsTarget = role != .reference
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
        let box = rect.insetBy(dx: 1.5, dy: 2)
        NSColor.black.setStroke()

        // An open bracket: three sides drawn, the fourth left as a gap so
        // the cut always has clear background inside its own bounding box.
        let bracket = NSBezierPath()
        bracket.lineWidth = 1.6
        bracket.lineCapStyle = .round
        bracket.lineJoinStyle = .round
        if drawnAsTarget {
            // Open on the right.
            bracket.move(to: NSPoint(x: box.maxX, y: box.maxY))
            bracket.line(to: NSPoint(x: box.minX, y: box.maxY))
            bracket.line(to: NSPoint(x: box.minX, y: box.minY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.minY))
        } else {
            // Open on the left.
            bracket.move(to: NSPoint(x: box.minX, y: box.maxY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.maxY))
            bracket.line(to: NSPoint(x: box.maxX, y: box.minY))
            bracket.line(to: NSPoint(x: box.minX, y: box.minY))
        }
        bracket.stroke()

        // An off-centre accent breaks the top/bottom symmetry the bracket
        // alone would have, and keeps the shape asymmetric end to end.
        let accent = NSBezierPath()
        accent.lineWidth = 1.6
        accent.lineCapStyle = .round
        let midY = box.midY
        if drawnAsTarget {
            accent.move(to: NSPoint(x: box.minX + 1, y: box.minY + 1))
            accent.line(to: NSPoint(x: box.minX + 3.5, y: midY))
        } else {
            accent.move(to: NSPoint(x: box.maxX - 1, y: box.maxY - 1))
            accent.line(to: NSPoint(x: box.maxX - 3.5, y: midY))
        }
        accent.stroke()
        return true
    }
    image.isTemplate = true
    return image
}

final class Delegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: itemLengthPt)
        // No autosaveName: nothing about this item's position may survive a
        // relaunch (Opus P2-13; the plan's T13 DoD says so explicitly).
        item.isVisible = true
        item.button?.image = glyphImage(for: role, side: itemLengthPt)
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityIdentifier("vz-\(role.rawValue)")
        self.item = item
        print("\(role.rawValue) up, pid \(getpid())")
        fflush(stdout)
    }

    func hide() { item?.isVisible = false }
    func show() { item?.isVisible = true }
}

let controllerExit = DispatchSource.makeProcessSource(identifier: controller, eventMask: .exit, queue: .main)
controllerExit.setEventHandler { exit(0) }
controllerExit.resume()
DispatchQueue.main.asyncAfter(deadline: .now() + lifetimeCapSeconds) { exit(0) }

let application = NSApplication.shared
let delegate = Delegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)

// The control channel: one command per line on stdin, buffered across
// partial reads. EOF is the same exit path as an explicit `quit` line.
let stdinSource = DispatchSource.makeReadSource(fileDescriptor: FileHandle.standardInput.fileDescriptor, queue: .main)
var inputBuffer = Data()
stdinSource.setEventHandler {
    let chunk = FileHandle.standardInput.availableData
    guard !chunk.isEmpty else {
        exit(0) // EOF
    }
    inputBuffer.append(chunk)
    while let newline = inputBuffer.firstIndex(of: 0x0A) {
        let lineData = inputBuffer[inputBuffer.startIndex..<newline]
        inputBuffer.removeSubrange(inputBuffer.startIndex...newline)
        guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespaces), !line.isEmpty else {
            continue
        }
        switch line {
        case "hide": delegate.hide()
        case "show": delegate.show()
        case "quit": exit(0)
        default: break
        }
    }
}
stdinSource.resume()

application.run()
