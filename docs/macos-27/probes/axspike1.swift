// Spike 1 -- READ-ONLY survey of what Accessibility actually offers for menu bar
// items on macOS 27. Answers, with no assumptions about which attributes exist:
//   * can every item be enumerated from zero, with a usable locator?
//   * is there a per-item window number, or do they all share MenuBarAgent's?
//   * is AXPosition / AXFrame / AXSize settable?
//   * what actions are available?
//   * is identity stable across repeated enumeration?
//   * can two items of the same app with the same title be told apart?
// Sets nothing, creates no status item, activates no assertion.
import Cocoa
import ApplicationServices

func axCopy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}

func axAttributeNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success else { return [] }
    return (names as? [String]) ?? []
}

func axActionNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return (names as? [String]) ?? []
}

func axIsSettable(_ element: AXUIElement, _ attribute: String) -> String {
    var settable: DarwinBoolean = false
    let err = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
    guard err == .success else { return "err(\(err.rawValue))" }
    return settable.boolValue ? "SETTABLE" : "read-only"
}

func describe(_ value: CFTypeRef?) -> String {
    guard let value else { return "nil" }
    if CFGetTypeID(value) == AXValueGetTypeID() {
        let axValue = value as! AXValue
        switch AXValueGetType(axValue) {
        case .cgRect:
            var rect = CGRect.zero
            AXValueGetValue(axValue, .cgRect, &rect)
            return "rect(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height)))"
        case .cgPoint:
            var point = CGPoint.zero
            AXValueGetValue(axValue, .cgPoint, &point)
            return "point(\(Int(point.x)),\(Int(point.y)))"
        case .cgSize:
            var size = CGSize.zero
            AXValueGetValue(axValue, .cgSize, &size)
            return "size(\(Int(size.width))x\(Int(size.height)))"
        default:
            return "AXValue(other)"
        }
    }
    if CFGetTypeID(value) == AXUIElementGetTypeID() { return "AXUIElement" }
    let string = String(describing: value)
    return string.count > 70 ? String(string.prefix(70)) + "..." : string
}

struct Item {
    let app: String
    let bundleID: String
    let pid: pid_t
    let element: AXUIElement
    let frame: CGRect
}

/// Enumerate every extras menu bar child of every running app, left to right.
func enumerateItems() -> [Item] {
    var items = [Item]()
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = axCopy(axApp, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
        let children = (axCopy(bar as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
        for child in children {
            guard let frameValue = axCopy(child, "AXFrame"), CFGetTypeID(frameValue) == AXValueGetTypeID() else { continue }
            var frame = CGRect.zero
            AXValueGetValue(frameValue as! AXValue, .cgRect, &frame)
            items.append(Item(
                app: app.localizedName ?? "?",
                bundleID: app.bundleIdentifier ?? "<none>",
                pid: app.processIdentifier,
                element: child,
                frame: frame
            ))
        }
    }
    return items.sorted { $0.frame.minX < $1.frame.minX }
}

print("AXIsProcessTrusted: \(AXIsProcessTrusted())")

// ---- 1. Enumeration + latency ----
let clock = ContinuousClock()
var durations = [Duration]()
var passes = [[Item]]()
for _ in 0..<3 {
    let start = clock.now
    let items = enumerateItems()
    durations.append(clock.now - start)
    passes.append(items)
    Thread.sleep(forTimeInterval: 0.5)
}
print("\n=== 1. enumeration ===")
for (index, duration) in durations.enumerated() {
    print("  pass \(index): \(passes[index].count) items in \(duration)")
}

guard let items = passes.first, !items.isEmpty else {
    print("no items; aborting")
    exit(1)
}

// ---- 2. Full attribute surface of every item ----
print("\n=== 2. every attribute of every item (name = value [settable]) ===")
for item in items {
    let names = axAttributeNames(item.element)
    let actions = axActionNames(item.element)
    print("\n  --- \(item.app)  [\(item.bundleID)]  pid=\(item.pid)  x=\(Int(item.frame.minX)) ---")
    for name in names.sorted() {
        print("      \(name) = \(describe(axCopy(item.element, name)))   [\(axIsSettable(item.element, name))]")
    }
    print("      actions: \(actions.isEmpty ? "(none)" : actions.joined(separator: ", "))")
}

// ---- 3. Is there a per-item window number, or is it all MenuBarAgent's? ----
print("\n=== 3. window-number-ish attributes (false positive: all items share one) ===")
let windowishNames = ["AXWindow", "AXWindowNumber", "_AXWindowNumber", "AXTopLevelUIElement", "AXParent"]
for item in items {
    var line = "  \(item.app.padding(toLength: 22, withPad: " ", startingAt: 0))"
    for name in windowishNames {
        if let value = axCopy(item.element, name) {
            line += " \(name)=\(describe(value))"
        }
    }
    print(line)
}

// ---- 4. Settability of the attributes a mover would need ----
print("\n=== 4. settability of position/frame/size ===")
for item in items.prefix(6) {
    let checks = ["AXPosition", "AXFrame", "AXSize"].map { "\($0)=\(axIsSettable(item.element, $0))" }
    print("  \(item.app.padding(toLength: 22, withPad: " ", startingAt: 0)) \(checks.joined(separator: "  "))")
}

// ---- 5. Identity stability across repeated enumeration ----
print("\n=== 5. identity across 3 passes ===")
func fingerprint(_ item: Item) -> String {
    let title = (axCopy(item.element, kAXTitleAttribute as String) as? String) ?? ""
    let identifier = (axCopy(item.element, "AXIdentifier") as? String) ?? ""
    let description = (axCopy(item.element, kAXDescriptionAttribute as String) as? String) ?? ""
    return "\(item.bundleID)|id=\(identifier)|title=\(title)|desc=\(description)"
}
let fingerprints = passes.map { $0.map(fingerprint) }
print("  pass0 == pass1: \(fingerprints[0] == fingerprints[1])")
print("  pass0 == pass2: \(fingerprints[0] == fingerprints[2])")
print("  AXUIElement equality pass0 vs pass2:")
for (a, b) in zip(passes[0], passes[2]) where a.bundleID == b.bundleID {
    print("      \(a.app.padding(toLength: 22, withPad: " ", startingAt: 0)) CFEqual=\(CFEqual(a.element, b.element))")
}

// ---- 6. Same app, same title: can they be told apart? ----
print("\n=== 6. duplicate-identity check ===")
var byFingerprint = [String: Int]()
for item in items {
    byFingerprint[fingerprint(item), default: 0] += 1
}
let duplicates = byFingerprint.filter { $0.value > 1 }
if duplicates.isEmpty {
    print("  no two items share bundleID+identifier+title+description -- all distinguishable today")
} else {
    for (key, count) in duplicates {
        print("  AMBIGUOUS x\(count): \(key)")
    }
}
