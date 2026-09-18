import Cocoa
import ApplicationServices
func axCopy(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success else { return nil }
    return v
}
struct Row { let bid: String; let ident: String; let x: Int; let w: Int; let y: Int }
func snap() -> [Row] {
    var rows = [Row]()
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = axCopy(ax, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
        for child in (axCopy(bar as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] {
            guard let v = axCopy(child, "AXFrame"), CFGetTypeID(v) == AXValueGetTypeID() else { continue }
            var r = CGRect.zero; AXValueGetValue(v as! AXValue, .cgRect, &r)
            let ident = (axCopy(child, "AXIdentifier") as? String) ?? ""
            rows.append(Row(bid: app.bundleIdentifier ?? "?", ident: ident, x: Int(r.minX), w: Int(r.width), y: Int(r.minY)))
        }
    }
    return rows.sorted { $0.x < $1.x }
}
var last: String?
var stable = 0
for i in 0..<6 {
    let rows = snap()
    let mine = rows.filter { $0.bid.hasPrefix("com.icespike3") }
    let key = rows.map { "\($0.bid):\($0.x)" }.joined(separator: ",")
    if key == last { stable += 1 } else { stable = 0 }
    last = key
    if i >= 2 {
        print("  pass \(i): stable-streak=\(stable)  mine=\(mine.map { "\($0.ident.isEmpty ? $0.bid : $0.ident)@\($0.x)w\($0.w)y\($0.y)" }.joined(separator: " "))")
    }
    Thread.sleep(forTimeInterval: 0.6)
}
let rows = snap()
let mine = rows.filter { $0.bid.hasPrefix("com.icespike3") }
print("\n  helpers found: \(mine.count)")
for m in mine { print("    \(m.ident)  bundle=\(m.bid)  x=\(m.x) w=\(m.w) y=\(m.y)") }
if mine.count == 2 {
    let t = mine.first { $0.ident.hasSuffix("-T") }, a = mine.first { $0.ident.hasSuffix("-A") }
    if let t, let a { print("  relative order: \(t.x < a.x ? "T is LEFT of A" : "A is LEFT of T")  gap=\(abs(t.x - a.x))") }
}
let neighbours = rows.filter { !$0.bid.hasPrefix("com.icespike3") && $0.y < 40 }
print("  user items in bar: \(neighbours.count)")
