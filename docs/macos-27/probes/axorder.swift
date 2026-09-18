// READ-ONLY. Samples the left-to-right order of the extras menu bar every second
// and reports whether it changes on its own. Tests the claim that macOS 27's
// MenuBarAgent reorders items by itself, which would break any scheme that infers
// section membership from position. Changes nothing.
import Cocoa
import ApplicationServices

func axCopy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let value = axCopy(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
    return rect
}

/// One sample: every extras menu bar item, left to right.
func sample() -> [(app: String, minX: CGFloat)] {
    var entries = [(app: String, minX: CGFloat)]()
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = axCopy(axApp, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
        let children = (axCopy(bar as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
        for child in children {
            guard let frame = axFrame(child), frame.minY < 40 else { continue }
            entries.append((app.localizedName ?? "?", frame.minX))
        }
    }
    return entries.sorted { $0.minX < $1.minX }
}

let seconds = 30
print("sampling the extras menu bar once per second for \(seconds)s, touching nothing\n")

var previousOrder: [String]?
var previousPositions: [String: CGFloat]?
var orderChanges = 0
var positionChanges = 0

for tick in 0..<seconds {
    let entries = sample()
    let order = entries.map(\.app)
    let positions = Dictionary(entries.map { ($0.app, $0.minX) }, uniquingKeysWith: { a, _ in a })

    if let previousOrder, previousOrder != order {
        orderChanges += 1
        print("t=\(tick)s ORDER CHANGED")
        print("   before: \(previousOrder.joined(separator: " | "))")
        print("   after:  \(order.joined(separator: " | "))")
    }
    if let previousPositions {
        let moved = positions.filter { key, value in
            guard let old = previousPositions[key] else { return false }
            return abs(old - value) > 1
        }
        if !moved.isEmpty {
            positionChanges += 1
            print("t=\(tick)s MOVED: \(moved.keys.sorted().joined(separator: ", "))")
        }
    }
    if tick == 0 {
        print("baseline (\(order.count) items, left to right):")
        for entry in entries {
            print("   x=\(Int(entry.minX))  \(entry.app)")
        }
        print("")
    }

    previousOrder = order
    previousPositions = positions
    Thread.sleep(forTimeInterval: 1)
}

print("\nsummary over \(seconds)s: order changed \(orderChanges) time(s), positions shifted \(positionChanges) time(s)")
