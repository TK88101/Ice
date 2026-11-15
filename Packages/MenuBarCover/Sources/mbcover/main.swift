//  main.swift
//  mbcover
//
//  T3 of plan 2026-11-15-cover: the real controller over the given members on the
//  displays connected now, the daily Ice untouched.
//
//    mbcover check <member bundle id>...
//
//  Side effects: its own panels over the members for under two minutes; two sessions of
//  four image calls; its own small window brought forward on each display in turn (it
//  waits for 30 s without input first, and gives the front app back).

import AppKit
import ApplicationServices
import IceCore
import MenuBarCover

@_silgen_name("CGSMainConnectionID")
private func cgsMainConnectionID() -> Int32

@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
private func cgsCopyActiveMenuBarDisplayIdentifier(_ cid: Int32) -> Unmanaged<CFString>?

func activeMenuBarDisplay() -> UInt32? {
    guard let string = cgsCopyActiveMenuBarDisplayIdentifier(cgsMainConnectionID())?.takeRetainedValue(),
          let uuid = CFUUIDCreateFromString(nil, string) else { return nil }
    let id = CGDisplayGetDisplayIDFromUUID(uuid)
    return id == 0 ? nil : id
}

func idleSeconds() -> Double {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

func spin(_ seconds: Double) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

/// Records the strips the controller takes, so the check needs no capture of its own for "before".
final class RecordingCapturer: CoverCapturing {
    let live = LiveCoverCapturer()
    var first = [UInt32: CoverStrips]()
    var calls = 0
    var lastAt = 0.0

    func strips(of bar: CoverBar) -> CoverStrips? {
        calls += 2
        lastAt = ProcessInfo.processInfo.systemUptime
        let strips = live.strips(of: bar)
        if first[bar.displayID] == nil { first[bar.displayID] = strips }
        return strips
    }

    func underStripSignature(of bar: CoverBar) -> String { live.underStripSignature(of: bar) }
}

var failures = [String]()
func check(_ ok: Bool, _ what: String) {
    print((ok ? "ok    " : "FAIL  ") + what)
    if !ok { failures.append(what) }
}

let arguments = CommandLine.arguments
guard arguments.count >= 3, arguments[1] == "check" else {
    FileHandle.standardError.write(Data("usage: mbcover check <member bundle id>...\n".utf8))
    exit(64)
}
let bundles = Array(arguments.dropFirst(2))
let coverable = Set(bundles.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).map(\.processIdentifier) })
guard !coverable.isEmpty else {
    print("no member app is running")
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
// Without this the process is no full app and is never made active.
app.finishLaunching()
var waited = 0.0
while idleSeconds() < 30, waited < 1800 {
    spin(5)
    waited += 5
}
guard idleSeconds() >= 30 else {
    print("the Mac was never idle for 30 s")
    exit(3)
}
let front = NSWorkspace.shared.frontmostApplication

let reader = LiveCoverBarReader()
let capturer = RecordingCapturer()
let presenter = CoverPanelPresenter()
let bars = CoverBars.current()
print("bars:", bars.map { "\($0.displayID) \($0.frame) notch \($0.notch.map { "\($0)" } ?? "-")" }.joined(separator: " | "))
let agentPID = LiveCoverBarReader.agentPID() ?? -1

struct Reading {
    var slots = [CoverSlot]()
    var verified = Set<CoverSlot>()
    var blocked = 0
    var disagree = [CoverSlot]()
}

/// The tree against the hit test, with any panel of ours opened to it for the moment.
func read(_ bar: CoverBar) -> Reading {
    var reading = Reading()
    let started = CFAbsoluteTimeGetCurrent()
    guard let slots = reader.slots(of: bar) else { return reading }
    let treeMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
    reading.slots = Array(Set(slots)).sorted { $0.minX < $1.minX }
    presenter.setIgnoresMouseEvents(true, displayID: bar.displayID)
    spin(0.02)
    for slot in reading.slots {
        let hits = reader.owners(at: CoverPlan.verificationPoints(slot), of: bar)
        if CoverPlan.isVerified(owner: slot.owner, hits: hits) {
            reading.verified.insert(slot)
        } else if hits.allSatisfy({ $0.owner == nil }) {
            reading.blocked += 1
        } else {
            reading.disagree.append(slot)
        }
    }
    presenter.setIgnoresMouseEvents(false, displayID: bar.displayID)
    spin(0.05)
    print(String(format: "  bar %u: %d slots (tree %.0f ms), %d hit as listed, %d not hit (stale, empty or under another window), %d hit as another owner",
                 bar.displayID, reading.slots.count, treeMs, reading.verified.count, reading.blocked, reading.disagree.count))
    return reading
}

let systemWide = AXUIElementCreateSystemWide()

/// Whether another app's window (not the menu bar, not an item) is what a point of a bar hits.
func isForeign(_ x: Double, _ bar: CoverBar) -> Bool {
    var element: AXUIElement?
    guard AXUIElementCopyElementAtPosition(systemWide, Float(bar.frame.minX) + Float(x), Float(bar.frame.midY), &element) == .success,
          let element else { return false }
    var role: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    return !((role as? String) ?? "").hasPrefix("AXMenuBar") && pid != agentPID
}

/// The columns that differ and are not within 3 pt of a point another app's window covers.
func unexplained(_ columns: [Int], _ bar: CoverBar) -> Int {
    let points = Set(columns.map { (Double($0) / bar.scale).rounded(.down) }).sorted()
    return points.filter { x in !stride(from: x - 3, through: x + 3, by: 1).contains { isForeign($0 + 0.5, bar) } }.count
}

func members(_ reading: Reading) -> [CoverSlot] {
    reading.slots.filter { coverable.contains($0.owner) && reading.verified.contains($0) }
}

/// Brings this process's window forward on a display, so its bar is the active one.
var window: NSWindow?
func activate(on bar: CoverBar) -> Bool {
    guard let screen = NSScreen.screens.first(where: {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == bar.displayID
    }) else { return false }
    let frame = NSRect(x: screen.frame.midX - 150, y: screen.frame.midY - 50, width: 300, height: 100)
    let shown = window ?? NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
    shown.title = "mbcover check"
    shown.setFrame(frame, display: true)
    shown.makeKeyAndOrderFront(nil)
    window = shown
    app.activate(ignoringOtherApps: true)
    for _ in 0..<16 {
        spin(0.25)
        if activeMenuBarDisplay() == bar.displayID { return true }
    }
    return false
}

func checkCoverage(_ label: String) -> [UInt32: Reading] {
    var readings = [UInt32: Reading]()
    for bar in bars {
        let reading = read(bar)
        readings[bar.displayID] = reading
        let frames = (presenter.frames[bar.displayID] ?? []).map { ($0.minX - bar.frame.minX)...($0.maxX - bar.frame.minX) }
        let own = members(reading)
        check(own.allSatisfy { slot in frames.contains { $0.lowerBound <= slot.minX && slot.maxX <= $0.upperBound } },
              "\(label) bar \(bar.displayID): every hit member slot (\(own.count)) lies inside a panel (\(frames.count))")
        // A member whose app answers no hit test is covered too (Amendment B): a panel may meet any coverable owner's slot.
        let foreign = reading.slots.filter { !coverable.contains($0.owner) }
        check(!foreign.contains { slot in frames.contains { $0.lowerBound < slot.maxX && slot.minX < $0.upperBound } } || own.isEmpty,
              "\(label) bar \(bar.displayID): no panel meets a slot that is not a member's")
        // With the panels taking mouse events, nothing under them answers.
        let under = own.flatMap { reader.owners(at: CoverPlan.verificationPoints($0), of: bar) }
        check(!under.contains { $0.owner.map(coverable.contains) ?? false },
              "\(label) bar \(bar.displayID): no member is hit through a panel")
    }
    return readings
}

// --- before: the tree against the hit test, no panel
let initialActive = activeMenuBarDisplay()
print("active menu bar on display \(initialActive.map(String.init) ?? "?"); before any panel:")
var before = [UInt32: Reading]()
for bar in bars {
    before[bar.displayID] = read(bar)
    check(before[bar.displayID]!.disagree.isEmpty, "bar \(bar.displayID): no slot is hit as another owner")
}
let agentSlotsBefore = bars.map { bar in before[bar.displayID]!.slots.filter { $0.owner == agentPID }.count }

// --- the controller
let controller = CoverController(
    reader: reader, capturer: capturer, presenter: presenter,
    environment: .live(backgroundKey: { _ in "mbcover" }, canCapture: { CGPreflightScreenCaptureAccess() })
)
controller.sync(active: true, coverable: coverable)
for _ in 0..<3 {
    spin(1)
    controller.tick()
}
check(controller.notice == nil, "no notice (\(String(describing: controller.notice)))")
print("panels:", presenter.frames.map { "\($0.key): \($0.value.map { "[\(Int($0.minX)),\(Int($0.maxX))]" })" }.sorted().joined(separator: " "))
let covered = checkCoverage("first")
check(covered.values.contains { !members($0).isEmpty } == !presenter.frames.values.allSatisfy(\.isEmpty), "panels exist exactly when a member is drawn somewhere")
check(capturer.calls <= 4, "the controller made \(capturer.calls) image calls")

// --- pixels: a second session, 12 s after the first
let wait = max(0, CoverCaptureBudget.rest + 0.5 - (ProcessInfo.processInfo.systemUptime - capturer.lastAt))
print(String(format: "waiting %.1f s for the second capture session", wait))
var elapsed = 0.0
while elapsed < wait {
    spin(1)
    controller.tick()
    elapsed += 1
}
for bar in bars {
    let blocks = controller.blocks(displayID: bar.displayID)
    guard !blocks.isEmpty else { continue }
    guard let now = capturer.live.strips(of: bar), let first = capturer.first[bar.displayID],
          let same = CoverPixels.sameColumns(now.onScreen, now.below), let unchanged = CoverPixels.sameColumns(now.onScreen, first.onScreen)
    else {
        check(false, "bar \(bar.displayID): the strips could not be compared")
        continue
    }
    func columns(_ range: ClosedRange<Double>) -> Range<Int> {
        max(0, Int(range.lowerBound * bar.scale))..<min(same.count, Int(range.upperBound * bar.scale))
    }
    presenter.setIgnoresMouseEvents(true, displayID: bar.displayID)
    spin(0.02)
    for block in blocks {
        // A column that differs must lie under another app's window (Alcove's notch).
        let differing = columns(block).filter { !same[$0] }
        let loose = unexplained(differing, bar)
        check(loose == 0, "bar \(bar.displayID) block [\(Int(block.lowerBound)),\(Int(block.upperBound))]: on-screen equals below-Menubar "
              + "(\(differing.count) of \(columns(block).count) columns differ; \(loose) pt of them not under another app's window)")
        // Another block's own columns changed too, as they should.
        let elsewhere = blocks.filter { $0 != block }.map(columns)
        func changed(_ range: ClosedRange<Double>) -> [Int] {
            columns(range).filter { column in !unchanged[column] && !elsewhere.contains { $0.contains(column) } }
        }
        let left = changed(max(0, block.lowerBound - 60)...block.lowerBound)
        let right = changed(block.upperBound...min(Double(bar.frame.width), block.upperBound + 60))
        let moved = unexplained(left + right, bar)
        check(moved == 0, "bar \(bar.displayID) block: the 60 pt left and right are as before the cover "
              + "(\(left.count + right.count) columns changed; \(moved) pt of them not under another app's window)")
    }
    presenter.setIgnoresMouseEvents(false, displayID: bar.displayID)
}

// --- the other display active (D5's premise)
if let other = bars.first(where: { $0.displayID != initialActive }) {
    let became = activate(on: other)
    controller.activeDisplayChanged()
    spin(2)
    controller.tick()
    spin(1)
    print("active menu bar now on display \(activeMenuBarDisplay().map(String.init) ?? "?") (asked \(other.displayID), "
          + "\(became ? "took" : "did not take"); this app active: \(app.isActive), key window: \(window?.isKeyWindow ?? false))")
    let second = checkCoverage("second")
    for bar in bars {
        let a = members(covered[bar.displayID]!), b = members(second[bar.displayID]!)
        let equal = a.count == b.count && zip(a, b).allSatisfy { $0.owner == $1.owner && abs($0.minX - $1.minX) <= 1 && abs($0.maxX - $1.maxX) <= 1 }
        check(equal, "bar \(bar.displayID): the member slots' frames are the same in both active-display states (\(a.count), \(b.count))")
    }
}

// --- no violet block for 15 s
var grew = false
for _ in 0..<15 {
    spin(1)
    controller.tick()
    for (index, bar) in bars.enumerated() {
        if let slots = reader.slots(of: bar), Set(slots).filter({ $0.owner == agentPID }).count > agentSlotsBefore[index] { grew = true }
    }
}
check(!grew, "MenuBarAgent listed no new slot of its own in the 15 s after the captures (no capture block)")

// --- off
controller.sync(active: false, coverable: [])
spin(0.3)
check(presenter.frames.values.allSatisfy(\.isEmpty), "no panel is left")
window?.orderOut(nil)
front?.activate()
spin(0.3)
print(failures.isEmpty ? "RESULT: PASS" : "RESULT: FAIL (\(failures.count))")
exit(failures.isEmpty ? 0 : 1)
