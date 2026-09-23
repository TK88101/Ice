// Polls the two helper items at 5Hz and reports every change in their order or
// position. This catches a swap even if it is transient or gets undone, which an
// event tap without Input Monitoring permission cannot do.
import Cocoa
import ApplicationServices

func axCopy(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success else { return nil }
    return v
}

func helpers() -> [(id: String, x: Int, y: Int)] {
    var rows = [(id: String, x: Int, y: Int)]()
    for app in NSWorkspace.shared.runningApplications
    where (app.bundleIdentifier ?? "").hasPrefix("com.icespike3") {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = axCopy(ax, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
        for child in (axCopy(bar as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] {
            guard let v = axCopy(child, "AXFrame"), CFGetTypeID(v) == AXValueGetTypeID() else { continue }
            var r = CGRect.zero
            AXValueGetValue(v as! AXValue, .cgRect, &r)
            let id = (axCopy(child, "AXIdentifier") as? String) ?? "?"
            rows.append((id, Int(r.minX), Int(r.minY)))
        }
    }
    return rows.sorted { $0.x < $1.x }
}

let seconds = Int(CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 90 : 90)
print("watching the two helpers at 5Hz for \(seconds)s -- every change is printed")
let start = Date()
var last = ""
var changes = 0
var orderFlips = 0
var lastOrder = ""

while Date().timeIntervalSince(start) < Double(seconds) {
    let rows = helpers()
    let key = rows.map { "\($0.id)@\($0.x),\($0.y)" }.joined(separator: " ")
    let order = rows.map(\.id).joined(separator: "<")
    if key != last {
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        var note = ""
        if !lastOrder.isEmpty, order != lastOrder {
            orderFlips += 1
            note = "   *** ORDER CHANGED: \(lastOrder) -> \(order) ***"
        }
        print("  t=\(ms)ms  \(key)\(note)")
        last = key
        lastOrder = order
        changes += 1
    }
    Thread.sleep(forTimeInterval: 0.2)
}
print("\n  \(changes) position change(s), \(orderFlips) order flip(s) in \(seconds)s")
