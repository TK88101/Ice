// Spike 2 -- does Ice's hiding mechanism still work on macOS 27?
//
// Ice hides items by expanding its own NSStatusItem to 10,000pt, pushing whatever
// sits to its left out of the visible menu bar. This checks whether MenuBarAgent
// still honors that, using only this process's own status items:
//
//   spacer  -- created first, so it ends up to the RIGHT of the probe
//   probe   -- created second, lands leftmost, and is the only thing sacrificed
//
// At every step it verifies that no other app's item has left the menu bar. If one
// does, it restores immediately and aborts. The status items die with the process,
// and a watchdog force-exits in case anything wedges.
import Cocoa
import ApplicationServices

let menuBarStripHeight: CGFloat = 40

func axCopy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}

struct Observed {
    let app: String
    let pid: pid_t
    let frame: CGRect
    var isInMenuBar: Bool { frame.minY < menuBarStripHeight }
}

func observe() -> [Observed] {
    var result = [Observed]()
    // This process is an unbundled binary, so it may never appear in
    // `runningApplications`; ask Accessibility about it by pid directly.
    var targets = [(name: String, pid: pid_t)](
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .map { ($0.localizedName ?? "?", $0.processIdentifier) }
    )
    if !targets.contains(where: { $0.pid == getpid() }) {
        targets.append(("<self>", getpid()))
    }
    for app in targets {
        let axApp = AXUIElementCreateApplication(app.pid)
        guard let bar = axCopy(axApp, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
        let children = (axCopy(bar as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
        for child in children {
            guard let value = axCopy(child, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() else { continue }
            var frame = CGRect.zero
            AXValueGetValue(value as! AXValue, .cgRect, &frame)
            result.append(Observed(app: app.name, pid: app.pid, frame: frame))
        }
    }
    return result.sorted { $0.frame.minX < $1.frame.minX }
}

/// Lets the menu bar finish laying out before measuring.
func settle(_ seconds: TimeInterval = 0.45) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

/// AX reports transient frames while the menu bar is re-laying out, so only accept
/// a reading that repeats identically. Returns the stable reading, or the last one
/// tried if it never settles.
func observeStable(attempts: Int = 8) -> [Observed] {
    var previous = observe()
    for _ in 0..<attempts {
        settle(0.4)
        let current = observe()
        let a = previous.map { "\($0.pid):\(Int($0.frame.minX)):\(Int($0.frame.minY))" }
        let b = current.map { "\($0.pid):\(Int($0.frame.minX)):\(Int($0.frame.minY))" }
        if a == b { return current }
        previous = current
    }
    print("      (warning: layout never settled)")
    return previous
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.finishLaunching()

// Created first, so newly inserted items land to its left.
let spacer = NSStatusBar.system.statusItem(withLength: 1)
spacer.button?.title = "|"
// Created second, so it should be the leftmost item and the only one sacrificed.
// Several probes, so the spacer has more to squeeze than it can fit. If macOS 27
// still hides overflow, they should start dropping out of the bar one by one.
let probes: [NSStatusItem] = (0..<3).map { index in
    let item = NSStatusBar.system.statusItem(withLength: 24)
    item.button?.title = "\(index)"
    return item
}
let probe = probes[0]

var restored = false
func restore() {
    guard !restored else { return }
    restored = true
    spacer.length = 1
    NSStatusBar.system.removeStatusItem(spacer)
    for item in probes { NSStatusBar.system.removeStatusItem(item) }
}
defer { restore() }

// Independent watchdog: if anything wedges, the process dies and the status items
// go with it.
let watchdog = Thread {
    Thread.sleep(forTimeInterval: 45)
    print("\nWATCHDOG: forcing exit")
    exit(2)
}
watchdog.start()

settle(1.0)

let mine = getpid()
func describe(_ observations: [Observed]) -> String {
    observations.map { "\($0.app)@\(Int($0.frame.minX))\($0.isInMenuBar ? "" : "[parked]")" }.joined(separator: " ")
}

let baseline = observeStable()
let baselineOthers = baseline.filter { $0.pid != mine && $0.isInMenuBar }
let baselineMine = baseline.filter { $0.pid == mine }

var appMenuRightEdge: CGFloat = 0
// Where does the frontmost app's menu area end? That is the likely clamp point.
if let front = NSWorkspace.shared.frontmostApplication {
    let axFront = AXUIElementCreateApplication(front.processIdentifier)
    if let bar = axCopy(axFront, "AXMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() {
        let kids = (axCopy(bar as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
        var maxX: CGFloat = 0
        for kid in kids {
            if let v = axCopy(kid, "AXFrame"), CFGetTypeID(v) == AXValueGetTypeID() {
                var r = CGRect.zero; AXValueGetValue(v as! AXValue, .cgRect, &r); maxX = max(maxX, r.maxX)
            }
        }
        print("frontmost app: \(front.localizedName ?? "?")  app-menu right edge x=\(Int(maxX))  (\(kids.count) menus)")
        appMenuRightEdge = maxX
    }
}
print("=== baseline ===")
print("  my items:     \(describe(baselineMine))")
print("  others in bar: \(baselineOthers.count)")
print("  leftmost other: \(baselineOthers.first.map { "\($0.app)@\(Int($0.frame.minX))" } ?? "none")")

guard baselineMine.count == 4 else {
    print("  expected 4 own items, got \(baselineMine.count) -- aborting")
    restore()
    exit(1)
}
let probeIsLeftmost = baselineMine[0].frame.minX <= baselineMine[1].frame.minX
print("  my leftmost item x=\(Int(baselineMine[0].frame.minX)), my rightmost x=\(Int(baselineMine[1].frame.minX))")
print("  probe expected leftmost: \(probeIsLeftmost)")

var previousActualSpacerWidth = baselineMine.last?.frame.width ?? 0
var previousOthers = Dictionary(baselineOthers.map { ("\($0.app)-\($0.pid)", $0.frame.minX) }, uniquingKeysWith: { a, _ in a })

print("\n=== progressive widths (requested -> actual spacer width, shift of others, my probe) ===")
for requested in [CGFloat(600), 900, 1200, 1600, 2000, 2400, 3000, 4000, 5000, 10_000] {
    spacer.length = requested
    let now = observeStable()
    let mineNow = now.filter { $0.pid == mine }
    let othersNow = now.filter { $0.pid != mine }
    let othersInBar = othersNow.filter(\.isInMenuBar)

    let actualSpacerWidth = mineNow.last?.frame.width ?? 0
    let actualDelta = actualSpacerWidth - previousActualSpacerWidth

    // Measure how far other apps' items actually moved.
    var shifts = [CGFloat]()
    for item in othersInBar {
        if let old = previousOthers["\(item.app)-\(item.pid)"] {
            shifts.append(item.frame.minX - old)
        }
    }
    let medianShift = shifts.isEmpty ? 0 : shifts.sorted()[shifts.count / 2]

    let mineInBar = mineNow.filter(\.isInMenuBar)
    let mineParked = mineNow.filter { !$0.isInMenuBar }
    let probeNow = mineInBar.first

    // AppKit knows which window belongs to which item; AX does not tell them apart.
    func report(_ label: String, _ item: NSStatusItem) -> String {
        guard let frame = item.button?.window?.frame else { return "\(label)=<no window>" }
        return "\(label)=[\(Int(frame.minX))..\(Int(frame.maxX))]\(item.isVisible ? "" : "!hidden")"
    }
    // Coordinates cannot say what the user sees. Capture the strip and look.
    let shot = Process()
    shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    shot.arguments = ["-x", "-R", "0,0,1728,40", "menubar-\(Int(requested))pt.png"]
    try? shot.run()
    shot.waitUntilExit()

    var parts = [report("spacer", spacer)]
    for (index, item) in probes.enumerated() { parts.append(report("p\(index)", item)) }
    print("      appkit: \(parts.joined(separator: "  "))")

    // Overflowing items do not park below the bar -- they pile up on top of each
    // other at the left edge. Distinct x positions is what detects that.
    let myX = mineNow.map { Int($0.frame.minX) }
    let distinctX = Set(myX).count
    let obscured = myX.filter { CGFloat($0) < appMenuRightEdge }.count
    print("  \(Int(requested))pt -> my xs \(myX.sorted())  distinct=\(distinctX)/4  under-app-menus=\(obscured)  others shifted \(Int(medianShift))")
    _ = actualSpacerWidth; _ = actualDelta; _ = mineInBar; _ = probeNow

    // Safety: never push somebody else's item out of the bar.
    let lost = baselineOthers.filter { base in
        !othersInBar.contains { $0.app == base.app && $0.pid == base.pid }
    }
    if !lost.isEmpty {
        print("  ABORT: these items left the menu bar: \(lost.map(\.app).joined(separator: ", "))")
        restore()
        settle(1.0)
        let after = observe().filter { $0.pid != mine && $0.isInMenuBar }
        print("  restored; others in bar: \(after.count) (baseline was \(baselineOthers.count))")
        exit(0)
    }

    // The question this spike exists to answer.
    if false, distinctX < 4 || mineParked.count > 0 || mineNow.count < 4 {
        print("\n  >>> ITEMS STOPPED BEING LAID OUT SEPARATELY at \(Int(requested))pt")
        print("  >>> distinct positions \(distinctX)/4, parked \(mineParked.count), gone from AX \(4 - mineNow.count)")
        print("  >>> squeeze-out hiding produces overlap/parking, and AX still enumerates them")
        break
    }
    if false, let probeNow, !probeNow.isInMenuBar {
        print("\n  >>> PROBE PUSHED OUT OF THE MENU BAR at requested width \(Int(requested))pt")
        print("  >>> hidden-state AX check: probe still enumerable = true, frame = \(probeNow.frame)")
        break
    }
    if false, probeNow == nil {
        print("\n  >>> PROBE DISAPPEARED FROM AX ENTIRELY at \(Int(requested))pt")
        print("  >>> hidden items would NOT be enumerable -- discovery and hiding are incompatible")
        break
    }

    previousActualSpacerWidth = actualSpacerWidth
    previousOthers = Dictionary(othersInBar.map { ("\($0.app)-\($0.pid)", $0.frame.minX) }, uniquingKeysWith: { a, _ in a })
}

print("\n=== restoring ===")
restore()
settle(1.0)
let after = observe().filter { $0.pid != mine && $0.isInMenuBar }
print("  others in bar after restore: \(after.count) (baseline was \(baselineOthers.count))")
print("done")
