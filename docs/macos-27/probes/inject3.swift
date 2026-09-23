// Spike 3 -- can a synthetic, coordinate-only event stream move another process's
// menu bar item? AX is read-only and exposes no per-item window number, so this is
// the only remaining candidate for a move primitive.
//
// Drags the target helper across the anchor helper using nothing but screen
// coordinates and the public event stream. Touches no other app's item. A watchdog
// and a defer always release the mouse button and the Command key.
import Cocoa
import ApplicationServices

func axCopy(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success else { return nil }
    return v
}

struct Helper { let id: String; let frame: CGRect }

func helpers() -> [Helper] {
    var rows = [Helper]()
    for app in NSWorkspace.shared.runningApplications
    where (app.bundleIdentifier ?? "").hasPrefix("com.icespike3") {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = axCopy(ax, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
        for child in (axCopy(bar as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] {
            guard let v = axCopy(child, "AXFrame"), CFGetTypeID(v) == AXValueGetTypeID() else { continue }
            var r = CGRect.zero
            AXValueGetValue(v as! AXValue, .cgRect, &r)
            rows.append(Helper(id: (axCopy(child, "AXIdentifier") as? String) ?? "?", frame: r))
        }
    }
    return rows.sorted { $0.frame.minX < $1.frame.minX }
}

func order() -> String { helpers().map(\.id).joined(separator: "<") }

let stateName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "combined"
let sourceState: CGEventSourceStateID = stateName == "hid" ? .hidSystemState : .combinedSessionState
let tapLocation: CGEventTapLocation = stateName == "hid" ? .cghidEventTap : .cgSessionEventTap
print("event source: \(stateName)  tap: \(stateName == "hid" ? "cghidEventTap" : "cgSessionEventTap")")

guard let source = CGEventSource(stateID: sourceState) else {
    print("cannot create event source")
    exit(1)
}

let originalCursor = CGEvent(source: nil)?.location ?? .zero
var released = false

func releaseEverything(at point: CGPoint) {
    guard !released else { return }
    released = true
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: tapLocation)
    let up = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
    up?.type = .flagsChanged
    up?.flags = []
    up?.post(tap: tapLocation)
    CGWarpMouseCursorPosition(originalCursor)
}

let before = helpers()
guard before.count == 2,
      let target = before.first(where: { $0.id.hasSuffix("-T") }),
      let anchor = before.first(where: { $0.id.hasSuffix("-A") })
else {
    print("expected both helpers, found \(before.map(\.id))")
    exit(1)
}
let orderBefore = order()
print("before: \(orderBefore)   T@\(Int(target.frame.minX)) A@\(Int(anchor.frame.minX))")

// Drag the target to the far side of the anchor, staying inside the menu bar.
let startPoint = CGPoint(x: target.frame.midX, y: target.frame.midY)
let crossing: CGFloat = target.frame.midX > anchor.frame.midX ? -1 : 1
let endPoint = CGPoint(x: anchor.frame.midX + crossing * (anchor.frame.width * 0.75), y: target.frame.midY)
print("drag: (\(Int(startPoint.x)),\(Int(startPoint.y))) -> (\(Int(endPoint.x)),\(Int(endPoint.y)))")

let watchdog = Thread {
    Thread.sleep(forTimeInterval: 20)
    print("\nWATCHDOG: releasing and exiting")
    releaseEverything(at: endPoint)
    exit(2)
}
watchdog.start()
defer { releaseEverything(at: endPoint) }

// Atomic binding check: the layout must not have moved between reading and pressing.
let recheck = helpers()
guard recheck.map(\.id) == before.map(\.id),
      let now = recheck.first(where: { $0.id.hasSuffix("-T") }),
      abs(now.frame.midX - startPoint.x) < 2
else {
    print("ABORT: layout changed between measuring and pressing")
    exit(1)
}

CGWarpMouseCursorPosition(startPoint)
Thread.sleep(forTimeInterval: 0.15)

// Command down, as a real modifier press.
let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
cmdDown?.type = .flagsChanged
cmdDown?.flags = .maskCommand
cmdDown?.post(tap: tapLocation)
Thread.sleep(forTimeInterval: 0.12)

func mouse(_ type: CGEventType, _ point: CGPoint) {
    guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
    event.flags = .maskCommand
    event.post(tap: tapLocation)
}

mouse(.leftMouseDown, startPoint)
Thread.sleep(forTimeInterval: 0.12)

// Many small steps: a pair of endpoints is not a drag.
let steps = 40
for step in 1...steps {
    let t = CGFloat(step) / CGFloat(steps)
    mouse(.leftMouseDragged, CGPoint(x: startPoint.x + (endPoint.x - startPoint.x) * t, y: startPoint.y))
    Thread.sleep(forTimeInterval: 0.012)
}
Thread.sleep(forTimeInterval: 0.25)
mouse(.leftMouseUp, endPoint)
Thread.sleep(forTimeInterval: 0.1)

let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
cmdUp?.type = .flagsChanged
cmdUp?.flags = []
cmdUp?.post(tap: tapLocation)
released = true
CGWarpMouseCursorPosition(originalCursor)

// Did it hold? Sample until stable rather than reading a transition frame.
Thread.sleep(forTimeInterval: 0.6)
var readings = [String]()
for _ in 0..<5 {
    readings.append(order())
    Thread.sleep(forTimeInterval: 0.4)
}
let after = helpers()
print("after:  \(readings.last ?? "?")   " + after.map { "\($0.id)@\(Int($0.frame.minX))" }.joined(separator: " "))
print("readings: \(readings.joined(separator: " | "))")

let stable = Set(readings).count == 1
let flipped = readings.last != orderBefore
let sameIdentities = Set(after.map(\.id)) == Set(before.map(\.id))
let inStrip = after.allSatisfy { $0.frame.minY < 40 }

print("\n  identities unchanged: \(sameIdentities)")
print("  both still in the menu bar: \(inStrip)")
print("  order flipped: \(flipped)")
print("  stable across 5 samples: \(stable)")
print(flipped && stable && sameIdentities && inStrip
      ? "\n  >>> SYNTHETIC COORDINATE-ONLY DRAG MOVED ANOTHER PROCESS'S ITEM"
      : "\n  >>> no move")
