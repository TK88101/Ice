// Replicates Ice's real discovery path on macOS 27:
//   Bridging.getMenuBarWindowList(option: .itemsOnly)  -> private CGS window-server API
//   SourcePIDCache.updatePID(for:)                     -> AXExtrasMenuBar + 1pt center match
import Cocoa
import ApplicationServices
import CoreGraphics

typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetWindowCount")
func CGSGetWindowCount(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ outCount: inout Int32) -> CGError

@_silgen_name("CGSGetOnScreenWindowCount")
func CGSGetOnScreenWindowCount(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ outCount: inout Int32) -> CGError

@_silgen_name("CGSGetOnScreenWindowList")
func CGSGetOnScreenWindowList(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ count: Int32, _ list: UnsafeMutablePointer<CGWindowID>, _ outCount: inout Int32) -> CGError

@_silgen_name("CGSGetWindowList")
func CGSGetWindowList(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ count: Int32, _ list: UnsafeMutablePointer<CGWindowID>, _ outCount: inout Int32) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
func CGSGetProcessMenuBarWindowList(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ count: Int32, _ list: UnsafeMutablePointer<CGWindowID>, _ outCount: inout Int32) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
func CGSGetScreenRectForWindow(_ cid: CGSConnectionID, _ wid: CGWindowID, _ outRect: inout CGRect) -> CGError

@_silgen_name("CGSGetWindowLevel")
func CGSGetWindowLevel(_ cid: CGSConnectionID, _ wid: CGWindowID, _ outLevel: inout CGWindowLevel) -> CGError

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

func center(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x, dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
}

let osv = ProcessInfo.processInfo.operatingSystemVersion
print("macOS \(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)  AXTrusted=\(AXIsProcessTrusted())")

let cid = CGSMainConnectionID()
print("CGSMainConnectionID = \(cid)")

var total: Int32 = 0
let errCount = CGSGetWindowCount(cid, 0, &total)
print("CGSGetWindowCount -> err=\(errCount.rawValue) count=\(total)")

var onScreenCount: Int32 = 0
_ = CGSGetOnScreenWindowCount(cid, 0, &onScreenCount)
var onScreenList = [CGWindowID](repeating: 0, count: Int(max(onScreenCount, 1)))
var onScreenOut = onScreenCount
_ = CGSGetOnScreenWindowList(cid, 0, onScreenCount, &onScreenList, &onScreenOut)
let onScreen = Set(onScreenList[..<Int(max(onScreenOut, 0))])
print("on-screen windows: \(onScreen.count)")

// ---- Ice's getProcessMenuBarWindowList() ----
var list = [CGWindowID](repeating: 0, count: Int(max(total, 1)))
var outCount = total
let errList = CGSGetProcessMenuBarWindowList(cid, 0, total, &list, &outCount)
let menuBarWindows = Array(list[..<Int(max(outCount, 0))])
print("CGSGetProcessMenuBarWindowList -> err=\(errList.rawValue) outCount=\(outCount)")

let mainMenuLevel = CGWindowLevelForKey(.mainMenuWindow)
print("kCGMainMenuWindowLevel = \(mainMenuLevel)")

print("\n=== every window returned by CGSGetProcessMenuBarWindowList ===")
struct MBWindow { let id: CGWindowID; let level: CGWindowLevel; let rect: CGRect; let onScreen: Bool }
var windows = [MBWindow]()
for wid in menuBarWindows {
    var level: CGWindowLevel = 0
    let e1 = CGSGetWindowLevel(cid, wid, &level)
    var rect = CGRect.zero
    let e2 = CGSGetScreenRectForWindow(cid, wid, &rect)
    let os = onScreen.contains(wid)
    let levelNote = e1 == .success ? "" : " (levelErr=\(e1.rawValue))"
    let rectNote = e2 == .success ? "" : " (rectErr=\(e2.rawValue))"
    print("  win=\(wid) level=\(level)\(levelNote) rect=(\(rect.minX), \(rect.minY), \(rect.width)x\(rect.height))\(rectNote) onScreen=\(os)")
    windows.append(MBWindow(id: wid, level: level, rect: rect, onScreen: os))
}

// Ice's .itemsOnly filter drops anything at the main menu level.
let itemsOnly = windows.filter { $0.level != mainMenuLevel }
print("\nafter Ice's .itemsOnly filter (level != \(mainMenuLevel)): \(itemsOnly.count) window(s)")
for w in itemsOnly.sorted(by: { $0.rect.minX < $1.rect.minX }) {
    print("  win=\(w.id) level=\(w.level) rect=(\(w.rect.minX), \(w.rect.minY), \(w.rect.width)x\(w.rect.height)) center=\(center(w.rect))")
}

// ---- AX side ----
struct AXChild { let app: String; let pid: pid_t; let frame: CGRect; let enabled: Bool }
var axChildren = [AXChild]()
for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    guard let barValue = axCopy(axApp, "AXExtrasMenuBar"), CFGetTypeID(barValue) == AXUIElementGetTypeID() else { continue }
    let children = (axCopy(barValue as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    for child in children {
        guard let frame = axFrame(child) else { continue }
        let enabled = (axCopy(child, kAXEnabledAttribute as String) as? Bool) ?? false
        axChildren.append(AXChild(app: app.localizedName ?? "?", pid: app.processIdentifier, frame: frame, enabled: enabled))
    }
}
print("\nAX extras-menu-bar children discovered: \(axChildren.count) (enabled: \(axChildren.filter(\.enabled).count))")

// ---- Ice's matching rule ----
print("\n=== Ice's rule: enabled AX child center within 1pt of the item window center ===")
var matched = 0
for w in itemsOnly.sorted(by: { $0.rect.minX < $1.rect.minX }) {
    let wc = center(w.rect)
    var best: (AXChild, CGFloat)?
    for child in axChildren where child.enabled {
        let d = dist(center(child.frame), wc)
        if best == nil || d < best!.1 { best = (child, d) }
    }
    if let (child, d) = best {
        print("  win=\(w.id) center=\(wc) -> closest '\(child.app)' distance=\(d) [\(d <= 1 ? "MATCH" : "NO MATCH")]")
        if d <= 1 { matched += 1 }
    } else {
        print("  win=\(w.id) -> no enabled AX children")
    }
}
print("\nSUMMARY: \(matched)/\(itemsOnly.count) item windows resolved to a source PID under Ice's rule")

// ---- Do per-item windows still exist ANYWHERE in the window server? ----
// Distinguishes "items are no longer windows" from "items are windows this API stopped listing".
print("\n=== every window server window whose rect sits in the menu bar strip (y < 40, height <= 40) ===")
var allList = [CGWindowID](repeating: 0, count: Int(max(total, 1)))
var allOut = total
_ = CGSGetWindowList(cid, 0, total, &allList, &allOut)
let allWindows = Array(allList[..<Int(max(allOut, 0))])
print("total windows from CGSGetWindowList: \(allWindows.count)")

let infoAll = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
var ownerByID = [CGWindowID: (String, Int32, Int)]()
for w in infoAll {
    guard let id = w[kCGWindowNumber as String] as? UInt32 else { continue }
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? "?"
    let pid = (w[kCGWindowOwnerPID as String] as? Int32) ?? 0
    let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
    ownerByID[id] = (owner, pid, layer)
}
print("CGWindowListCopyWindowInfo(.optionAll) returned \(infoAll.count) windows")

var strip = 0
for wid in allWindows {
    var rect = CGRect.zero
    guard CGSGetScreenRectForWindow(cid, wid, &rect) == .success else { continue }
    guard rect.minY < 40, rect.height <= 40, rect.width > 0 else { continue }
    var level: CGWindowLevel = 0
    _ = CGSGetWindowLevel(cid, wid, &level)
    let (owner, pid, layer) = ownerByID[wid] ?? ("<not in public list>", 0, -999)
    print("  win=\(wid) level=\(level) publicLayer=\(layer) owner=\(owner) pid=\(pid) rect=(\(rect.minX), \(rect.minY), \(rect.width)x\(rect.height))")
    strip += 1
}
print("windows in the menu bar strip: \(strip)")
