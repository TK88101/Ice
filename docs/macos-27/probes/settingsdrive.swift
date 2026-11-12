// settingsdrive -- the hands and eyes of the settings pass (plan
// 2026-11-12-settings-cleanup, section 2 and amendment 9.3). Derived from
// dragown.swift. Reads the bar and Ice's windows, and posts guarded synthetic
// input at Ice's lab copy, at the sacrificial helpers and at menu bar space
// proved empty. Never at an item of the owner's.
//
//   settingsdrive idle                                   hardware idle seconds
//   settingsdrive items                                  every status item over AX (pid, bundle, identifier, frame)
//   settingsdrive hit <x> <y>                            the element at a point and its ancestors
//   settingsdrive windows <pid>                          that process's windows (window list)
//   settingsdrive menus                                  the menu bar owner's menu titles and frames
//   settingsdrive gap [<from> <to>]                      the middle of the widest empty stretch of the bar
//   settingsdrive mean <png> [<x> <y> <w> <h>]           mean RGBA of a PNG (or of a pixel rect of it)
//   settingsdrive axdump <pid>                           the controls of that process's windows
//   settingsdrive axpress <pid> <role> <title> [<n>]     AXPress on the n-th control so named (no input event)
//   settingsdrive selftest                               the rules, on made-up frames
//
//   settingsdrive move <x> <y> [--hold <s>] [--tap hid]
//   settingsdrive click <x> <y> --expect <who> [--right] [--mods <m,..>] [--hold <s>]
//   settingsdrive scroll <x> <y> <dy> --expect <who> [--hold <s>]
//   settingsdrive key <keycode> [--mods <m,..>]
//   settingsdrive command <x> <y> <seconds>              pointer there, Command held that long
//   settingsdrive drag <x1> <y1> <x2> <y2> --expect <who> [--seconds <s>] [--command-first <s>]
//                      [--pause <s>] [--return]      (stay at the far point; come back before letting go)
//
// <who>: `empty` (menu bar space with no status item and no menu title under
// the point, of any process), `pid:<n>` (the element at the point belongs to
// that process), `bundle:<id>`. The expectation is checked by an Accessibility
// hit test and by every process's own item frames; an answer that cannot be
// read refuses. --hold keeps the pointer there that long before it is put
// back. Modifiers: cmd, opt, ctrl, shift.
//
// Side effects of the input commands: synthetic events in this login session
// and a moved cursor (restored). Each refuses unless no hardware input arrived
// for 5 s, reads the hardware idle time again before every event, and on
// hardware input lets go of button and modifiers, restores the cursor and ends
// `aborted`. A watchdog and the signals let go too.
//
// One JSON object on stdout. Exit: 0 done, 1 failed, 2 usage, 3 refused,
// 4 aborted, 5 aborted and not let go for certain.
import ApplicationServices
import Cocoa
import ImageIO

// MARK: - Rules (pure; `selftest` checks them)

enum Rule {
    static let requiredIdleSeconds = 5.0
    static let barHeight: CGFloat = 40

    static func isOnBar(_ point: CGPoint, display: CGRect) -> Bool {
        point.x >= display.minX && point.x <= display.maxX && point.y >= display.minY && point.y <= display.minY + barHeight
    }

    /// A point is empty bar space when it is on the bar and inside no item's
    /// and no menu title's frame, each widened by `margin` (an item's window
    /// is wider than its frame).
    static func isEmpty(_ point: CGPoint, display: CGRect, occupied: [CGRect], margin: CGFloat) -> Bool {
        guard isOnBar(point, display: display) else { return false }
        return !occupied.contains { $0.insetBy(dx: -margin, dy: -margin).contains(point) }
    }

    static func modifiers(_ names: String?) -> CGEventFlags? {
        guard let names, !names.isEmpty else { return [] }
        var flags = CGEventFlags()
        for name in names.split(separator: ",") {
            switch name {
            case "cmd": flags.insert(.maskCommand)
            case "opt": flags.insert(.maskAlternate)
            case "ctrl": flags.insert(.maskControl)
            case "shift": flags.insert(.maskShift)
            default: return nil
            }
        }
        return flags
    }

    /// The widest gap between occupied spans of the bar from `from` to `to`,
    /// as its middle: where a press on empty space is safest.
    static func widestGapMiddle(occupied: [CGRect], from: CGFloat, to: CGFloat) -> CGFloat? {
        let spans = occupied.map { (max($0.minX, from), min($0.maxX, to)) }.filter { $0.0 < $0.1 }.sorted { $0.0 < $1.0 }
        var cursor = from
        var best: (width: CGFloat, middle: CGFloat)?
        for span in spans + [(to, to)] {
            let width = span.0 - cursor
            if width > (best?.width ?? 0) { best = (width, cursor + width / 2) }
            cursor = max(cursor, span.1)
        }
        return best?.middle
    }
}

func selftest() -> Bool {
    let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let item = CGRect(x: 1000, y: 5, width: 20, height: 24)
    let checks: [(String, Bool)] = [
        ("a point on the bar is on the bar", Rule.isOnBar(CGPoint(x: 800, y: 12), display: display)),
        ("a point under the bar is not", !Rule.isOnBar(CGPoint(x: 800, y: 60), display: display)),
        ("a point beside every item is empty", Rule.isEmpty(CGPoint(x: 900, y: 12), display: display, occupied: [item], margin: 8)),
        ("a point inside an item is not empty", !Rule.isEmpty(CGPoint(x: 1010, y: 12), display: display, occupied: [item], margin: 8)),
        ("a point inside an item's margin is not empty", !Rule.isEmpty(CGPoint(x: 995, y: 12), display: display, occupied: [item], margin: 8)),
        ("a point off the bar is not empty", !Rule.isEmpty(CGPoint(x: 900, y: 80), display: display, occupied: [], margin: 8)),
        ("modifier names parse", Rule.modifiers("cmd,opt") == [.maskCommand, .maskAlternate]),
        ("no modifiers is none", Rule.modifiers(nil) == []),
        ("an unknown modifier refuses", Rule.modifiers("cmd,fn") == nil),
        ("the widest gap's middle", Rule.widestGapMiddle(occupied: [CGRect(x: 100, y: 0, width: 100, height: 24), item], from: 0, to: 1728) == 600),
        ("a gap after the last item counts", Rule.widestGapMiddle(occupied: [CGRect(x: 0, y: 0, width: 1000, height: 24)], from: 0, to: 1728) == 1364),
        ("no gap at all is none", Rule.widestGapMiddle(occupied: [CGRect(x: 0, y: 0, width: 1728, height: 24)], from: 0, to: 1728) == nil),
    ]
    for (name, holds) in checks {
        FileHandle.standardError.write(Data("\(holds ? "ok  " : "FAIL") \(name)\n".utf8))
    }
    return checks.allSatisfy(\.1)
}

// MARK: - Reading

let messagingTimeout: Float = 0.25

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, messagingTimeout)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func element(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let value = attribute(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
}

func rectArray(_ rect: CGRect) -> [Double] {
    [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
}

struct BarItem {
    let pid: pid_t
    let bundle: String
    let identifier: String?
    let frame: CGRect?
}

/// Every status item of every running process, from each process's own extras bar.
func allItems() -> [BarItem] {
    var found = [BarItem]()
    for application in NSWorkspace.shared.runningApplications where !application.isTerminated {
        let pid = application.processIdentifier
        guard pid != getpid(), let bar = element(attribute(AXUIElementCreateApplication(pid), "AXExtrasMenuBar")),
              let children = attribute(bar, kAXChildrenAttribute as String) as? [AXUIElement]
        else { continue }
        for child in children {
            found.append(BarItem(
                pid: pid, bundle: application.bundleIdentifier ?? "?",
                identifier: attribute(child, "AXIdentifier") as? String, frame: frame(of: child)
            ))
        }
    }
    return found
}

/// The menu bar owner's menu titles: name and frame.
func menuTitles() -> [(title: String, frame: CGRect)]? {
    guard let owner = NSWorkspace.shared.menuBarOwningApplication,
          let bar = element(attribute(AXUIElementCreateApplication(owner.processIdentifier), kAXMenuBarAttribute as String)),
          let children = attribute(bar, kAXChildrenAttribute as String) as? [AXUIElement]
    else { return nil }
    return children.compactMap { child in
        frame(of: child).map { ((attribute(child, kAXTitleAttribute as String) as? String) ?? "", $0) }
    }
}

struct Hit {
    let pid: pid_t
    let bundle: String
    let chain: [[String: Any]]
}

func hit(at point: CGPoint) -> Hit? {
    var found: AXUIElement?
    let systemWide = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
    guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &found) == .success, var current = found else { return nil }
    var pid: pid_t = 0
    guard AXUIElementGetPid(current, &pid) == .success else { return nil }
    var chain = [[String: Any]]()
    for _ in 0..<5 {
        chain.append([
            "role": (attribute(current, kAXRoleAttribute as String) as? String) ?? NSNull(),
            "subrole": (attribute(current, kAXSubroleAttribute as String) as? String) ?? NSNull(),
            "identifier": (attribute(current, "AXIdentifier") as? String) ?? NSNull(),
            "title": (attribute(current, kAXTitleAttribute as String) as? String) ?? NSNull(),
        ])
        guard let parent = element(attribute(current, kAXParentAttribute as String)) else { break }
        current = parent
    }
    let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "?"
    return Hit(pid: pid, bundle: bundle, chain: chain)
}

/// Why input at that point would not land where `who` says, or nil.
func expectationFailure(_ who: String, at point: CGPoint) -> String? {
    let display = CGDisplayBounds(CGMainDisplayID())
    if who == "empty" {
        guard let titles = menuTitles() else { return "menusUnread" }
        let items = allItems()
        guard !items.contains(where: { $0.frame == nil }) else { return "itemFrameUnread" }
        let occupied = items.compactMap(\.frame) + titles.map(\.frame)
        guard Rule.isEmpty(point, display: display, occupied: occupied, margin: 8) else { return "notEmpty" }
        // The element there must not be a status item or a menu title of anyone's.
        guard let hit = hit(at: point) else { return "hitUnread" }
        let roles = hit.chain.compactMap { $0["role"] as? String }
        guard !roles.contains("AXMenuBarItem"), !roles.contains("AXMenuItem"), !roles.contains("AXMenu") else { return "hitIsItem(\(hit.bundle))" }
        return nil
    }
    guard let hit = hit(at: point) else { return "hitUnread" }
    if who.hasPrefix("pid:") {
        return who.dropFirst(4) == String(hit.pid) ? nil : "hitIs(\(hit.pid),\(hit.bundle))"
    }
    if who.hasPrefix("bundle:") {
        return who.dropFirst(7) == hit.bundle ? nil : "hitIs(\(hit.pid),\(hit.bundle))"
    }
    return "unknownExpectation"
}

func windows(of pid: pid_t) -> [[String: Any]] {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.filter { ($0[kCGWindowOwnerPID as String] as? Int).map { pid_t($0) } == pid }.map { window in
        let bounds = (window[kCGWindowBounds as String] as? [String: Double]) ?? [:]
        return [
            "id": window[kCGWindowNumber as String] ?? NSNull(),
            "title": window[kCGWindowName as String] ?? NSNull(),
            "layer": window[kCGWindowLayer as String] ?? NSNull(),
            "onScreen": (window[kCGWindowIsOnscreen as String] as? Bool) ?? false,
            "alpha": window[kCGWindowAlpha as String] ?? NSNull(),
            "bounds": [bounds["X"] ?? 0, bounds["Y"] ?? 0, bounds["Width"] ?? 0, bounds["Height"] ?? 0],
        ]
    }
}

func meanColour(path: String, rect: CGRect?) -> [String: Any]? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          var image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    if let rect {
        guard let cropped = image.cropping(to: rect) else { return nil }
        image = cropped
    }
    let width = image.width, height = image.height
    guard width > 0, height > 0 else { return nil }
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var sums = [Double](repeating: 0, count: 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        for channel in 0..<4 { sums[channel] += Double(pixels[index + channel]) }
    }
    let count = Double(width * height)
    return ["width": width, "height": height, "mean": sums.map { ($0 / count * 100).rounded() / 100 }]
}

// MARK: - A process's windows and menus over Accessibility

func describe(_ element: AXUIElement, depth: Int, into rows: inout [[String: Any]], limit: Int) {
    guard rows.count < limit, depth < 40 else { return }
    let role = attribute(element, kAXRoleAttribute as String) as? String ?? "?"
    var row: [String: Any] = ["role": role, "depth": depth]
    for (key, name) in [("title", kAXTitleAttribute as String), ("description", kAXDescriptionAttribute as String),
                        ("identifier", "AXIdentifier"), ("help", kAXHelpAttribute as String)] {
        if let text = attribute(element, name) as? String, !text.isEmpty { row[key] = text }
    }
    if let value = attribute(element, kAXValueAttribute as String) {
        if let text = value as? String { row["value"] = text } else if let number = value as? NSNumber { row["value"] = number }
    }
    if let rect = frame(of: element) { row["frame"] = rectArray(rect) }
    if row.count > 2 || ["AXWindow", "AXMenu"].contains(role) { rows.append(row) }
    for child in (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] {
        describe(child, depth: depth + 1, into: &rows, limit: limit)
    }
}

func axWindows(_ pid: pid_t) -> [AXUIElement] {
    (attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
}

func find(in element: AXUIElement, role: String, title: String, depth: Int = 0, into found: inout [AXUIElement]) {
    guard depth < 40 else { return }
    if attribute(element, kAXRoleAttribute as String) as? String == role {
        let names = [kAXTitleAttribute as String, kAXDescriptionAttribute as String, "AXIdentifier"].compactMap { attribute(element, $0) as? String }
        if names.contains(title) { found.append(element) }
    }
    for child in (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] {
        find(in: child, role: role, title: title, depth: depth + 1, into: &found)
    }
}

// MARK: - Input

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

/// The kinds of input a person makes. Asked one by one: on macOS 27.0.1 the
/// "any event" counter is reset by events that are nobody's input (it read
/// under a second on an untouched Mac, 2026-11-12), and each of these is left
/// alone by events posted at the session tap (measured the same day).
let hardwareInputTypes: [CGEventType] = [
    .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .rightMouseDragged,
    .scrollWheel, .keyDown, .flagsChanged,
]

/// `--tap hid`: pointer moves are posted where a hardware mouse's enter (Ice's
/// hover reads a tap there). Such a post resets the hardware counter of mouse
/// moves (measured 2026-11-12), so that counter is left out and a person's
/// move is seen instead as the cursor being somewhere it was not put.
var postsAtHIDTap = false
let cursorTolerance: CGFloat = 3
/// A key is always posted at the HID tap: a Carbon hotkey does not hear one
/// posted at the session tap (control experiment, 2026-11-12). Such a post
/// resets the hardware key counters, so they are left out once a key went out;
/// the two events of a key are 60 ms apart.
var keyWasPosted = false
/// Function keys reach a hotkey only with the fn flag set (same experiment).
let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

/// Since the last hardware input of any of those kinds.
func hardwareIdleSeconds() -> Double {
    var types = postsAtHIDTap && cursorWasMoved ? hardwareInputTypes.filter { $0 != .mouseMoved } : hardwareInputTypes
    if keyWasPosted { types = types.filter { $0 != .keyDown && $0 != .flagsChanged } }
    let idle = types.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? 0
    if postsAtHIDTap, cursorWasMoved, let now = CGEvent(source: nil)?.location,
       abs(now.x - lastPoint.x) > cursorTolerance || abs(now.y - lastPoint.y) > cursorTolerance {
        return 0
    }
    return idle
}

let tapLocation = CGEventTapLocation.cgSessionEventTap
let eventSource = CGEventSource(stateID: .combinedSessionState)
let commandKey: CGKeyCode = 0x37

var heldButton: CGMouseButton?
var heldFlags = CGEventFlags()
var commandIsDown = false
var cursorWasMoved = false
var stopping = false
var inputIsOver = false
var lastPoint = CGPoint.zero
let originalCursor = CGEvent(source: nil)?.location ?? .zero
let eventLock = NSLock()
var watchdogSeconds = 15.0

@discardableResult
func postMouse(_ type: CGEventType, _ point: CGPoint, button: CGMouseButton = .left, flags: CGEventFlags) -> Bool {
    guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return false }
    event.flags = flags
    event.post(tap: postsAtHIDTap && type == .mouseMoved ? .cghidEventTap : tapLocation)
    lastPoint = point
    cursorWasMoved = true
    return true
}

@discardableResult
func postCommand(down: Bool) -> Bool {
    guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: commandKey, keyDown: down) else { return false }
    event.type = .flagsChanged
    event.flags = down ? .maskCommand : []
    event.post(tap: tapLocation)
    return true
}

/// With `eventLock` held.
func releaseLocked() {
    stopping = true
    if let button = heldButton {
        let type: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
        if postMouse(type, lastPoint, button: button, flags: heldFlags) { heldButton = nil }
    }
    if commandIsDown, postCommand(down: false) { commandIsDown = false }
    if cursorWasMoved {
        CGWarpMouseCursorPosition(originalCursor)
        cursorWasMoved = false
    }
}

func releaseEverything() {
    eventLock.lock()
    releaseLocked()
    eventLock.unlock()
}

func releaseAndExit(reason: String) -> Never {
    let locked = eventLock.lock(before: Date().addingTimeInterval(1))
    if locked, inputIsOver { _exit(4) }
    releaseLocked()
    let letGo = locked && heldButton == nil && !commandIsDown
    emit(["result": "aborted", "reason": letGo ? reason : "\(reason), not let go for certain"])
    _exit(letGo ? 4 : 5)
}

var signalSources = [DispatchSourceSignal]()

func armReleases() {
    let watchdog = Thread {
        Thread.sleep(forTimeInterval: watchdogSeconds)
        releaseAndExit(reason: "watchdog")
    }
    watchdog.start()
    for number in [SIGINT, SIGTERM, SIGHUP, SIGALRM] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { releaseAndExit(reason: "signal \(number)") }
        source.resume()
        signalSources.append(source)
    }
}

/// One run of posted events: each step waits, checks the hardware is still
/// idle, and posts under the lock.
final class Burst {
    private(set) var aborted: String?

    @discardableResult
    func step(after pause: TimeInterval, _ post: () -> Void) -> Bool {
        guard aborted == nil else { return false }
        // A long pause is slept in slices, so hardware input ends it early.
        var remaining = pause
        while remaining > 0 {
            let slice = min(remaining, 0.1)
            Thread.sleep(forTimeInterval: slice)
            remaining -= slice
            if hardwareIdleSeconds() < Rule.requiredIdleSeconds { break }
        }
        let idle = hardwareIdleSeconds()
        guard idle >= Rule.requiredIdleSeconds else {
            aborted = "hardwareInput (idle \(idle) s)"
            releaseEverything()
            return false
        }
        eventLock.lock()
        defer { eventLock.unlock() }
        guard !stopping else {
            aborted = "released"
            return false
        }
        post()
        return true
    }

    func finish() {
        eventLock.lock()
        releaseLocked()
        inputIsOver = true
        eventLock.unlock()
    }
}

// MARK: - Commands

let arguments = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func number(_ index: Int) -> CGFloat? {
    index < arguments.count ? Double(arguments[index]).map { CGFloat($0) } : nil
}

func usage() -> Never {
    FileHandle.standardError.write(Data("settingsdrive: see the header of settingsdrive.swift\n".utf8))
    exit(2)
}

/// Runs an input command: the shared refusals, then `body`, then the report.
func runInput(_ mode: String, point: CGPoint?, expect: String?, hold: Double, _ body: (Burst) -> Void) -> Int32 {
    var report: [String: Any] = ["mode": mode, "idleAtStart": hardwareIdleSeconds()]
    func finish(_ result: String, _ reason: String?, _ code: Int32) -> Int32 {
        report["result"] = result
        report["reason"] = reason ?? NSNull()
        emit(report)
        return code
    }
    guard AXIsProcessTrusted(), eventSource != nil else { return finish("refused", "notTrusted", 3) }
    guard hardwareIdleSeconds() >= Rule.requiredIdleSeconds else { return finish("refused", "hardwareInput", 3) }
    if let expect, let point, let failure = expectationFailure(expect, at: point) {
        return finish("refused", failure, 3)
    }
    watchdogSeconds += hold
    armReleases()
    defer { releaseEverything() }
    let burst = Burst()
    report["postedAt"] = ProcessInfo.processInfo.systemUptime
    body(burst)
    if hold > 0 { burst.step(after: hold) { } }
    report["endedAt"] = ProcessInfo.processInfo.systemUptime
    burst.finish()
    guard heldButton == nil, !commandIsDown else { return finish("aborted", "notLetGo", 5) }
    if let aborted = burst.aborted { return finish("aborted", aborted, 4) }
    return finish("done", nil, 0)
}

func main() -> Int32 {
    guard let mode = arguments.first else { usage() }
    let hold = option("--hold").flatMap(Double.init) ?? 0
    postsAtHIDTap = option("--tap") == "hid"
    switch mode {
    case "selftest":
        return selftest() ? 0 : 1
    case "idle":
        emit(["hardwareIdle": hardwareIdleSeconds()])
        return 0
    case "items":
        emit(["items": allItems().map { item -> [String: Any] in
            ["pid": Int(item.pid), "bundle": item.bundle, "identifier": item.identifier ?? NSNull(), "frame": item.frame.map(rectArray) ?? NSNull()]
        }])
        return 0
    case "menus":
        guard let titles = menuTitles() else {
            emit(["error": "unread"])
            return 1
        }
        emit([
            "owner": NSWorkspace.shared.menuBarOwningApplication?.bundleIdentifier ?? NSNull(),
            "front": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? NSNull(),
            "titles": titles.map { ["title": $0.title, "frame": rectArray($0.frame)] },
        ])
        return 0
    case "hit":
        guard let x = number(1), let y = number(2) else { usage() }
        guard let found = hit(at: CGPoint(x: x, y: y)) else {
            emit(["error": "unread"])
            return 1
        }
        emit(["pid": Int(found.pid), "bundle": found.bundle, "chain": found.chain])
        return 0
    case "gap":
        guard let titles = menuTitles() else {
            emit(["error": "menusUnread"])
            return 1
        }
        let display = CGDisplayBounds(CGMainDisplayID())
        let occupied = allItems().compactMap(\.frame).filter { $0.minY < Rule.barHeight } + titles.map(\.frame)
        let from = number(1) ?? (titles.map(\.frame.maxX).max() ?? 0)
        let to = number(2) ?? display.maxX
        guard let middle = Rule.widestGapMiddle(occupied: occupied.map { $0.insetBy(dx: -10, dy: 0) }, from: from, to: to) else {
            emit(["error": "noGap"])
            return 1
        }
        emit(["x": Double(middle), "y": 12])
        return 0
    case "windows":
        guard arguments.count > 1, let pid = pid_t(arguments[1]) else { usage() }
        emit(["windows": windows(of: pid)])
        return 0
    case "mean":
        guard arguments.count > 1 else { usage() }
        var rect: CGRect?
        if let x = number(2), let y = number(3), let width = number(4), let height = number(5) {
            rect = CGRect(x: x, y: y, width: width, height: height)
        }
        guard let result = meanColour(path: arguments[1], rect: rect) else {
            emit(["error": "unread"])
            return 1
        }
        emit(result)
        return 0
    case "axdump":
        guard arguments.count > 1, let pid = pid_t(arguments[1]) else { usage() }
        // The process's windows only: its menu bar holds the system's own
        // menus (recent documents among them), which are nobody's to dump.
        var rows = [[String: Any]]()
        for window in axWindows(pid) { describe(window, depth: 0, into: &rows, limit: 2500) }
        emit(["rows": rows])
        return 0
    case "axpress":
        guard arguments.count > 3, let pid = pid_t(arguments[1]) else { usage() }
        var found = [AXUIElement]()
        for window in axWindows(pid) { find(in: window, role: arguments[2], title: arguments[3], into: &found) }
        let index = arguments.count > 4 ? Int(arguments[4]) ?? 0 : 0
        guard index < found.count else {
            emit(["result": "failed", "reason": "notFound", "matches": found.count])
            return 1
        }
        let error = AXUIElementPerformAction(found[index], kAXPressAction as CFString)
        emit(["result": error == .success ? "done" : "failed", "error": Int(error.rawValue), "matches": found.count])
        return error == .success ? 0 : 1
    case "move":
        guard let x = number(1), let y = number(2) else { usage() }
        let point = CGPoint(x: x, y: y)
        return runInput(mode, point: point, expect: nil, hold: hold) { burst in
            // Two events: a tracker wants to see the pointer arrive.
            burst.step(after: 0) { postMouse(.mouseMoved, CGPoint(x: point.x - 6, y: point.y), flags: []) }
            burst.step(after: 0.05) { postMouse(.mouseMoved, point, flags: []) }
        }
    case "click":
        guard let x = number(1), let y = number(2), let expect = option("--expect"), let flags = Rule.modifiers(option("--mods")) else { usage() }
        let point = CGPoint(x: x, y: y)
        let right = arguments.contains("--right")
        let button: CGMouseButton = right ? .right : .left
        return runInput(mode, point: point, expect: expect, hold: hold) { burst in
            burst.step(after: 0) { postMouse(.mouseMoved, point, flags: flags) }
            burst.step(after: 0.15) {
                heldButton = button
                heldFlags = flags
                postMouse(right ? .rightMouseDown : .leftMouseDown, point, button: button, flags: flags)
            }
            burst.step(after: 0.08) {
                if postMouse(right ? .rightMouseUp : .leftMouseUp, point, button: button, flags: flags) { heldButton = nil }
            }
        }
    case "scroll":
        guard let x = number(1), let y = number(2), let delta = number(3), let expect = option("--expect") else { usage() }
        let point = CGPoint(x: x, y: y)
        return runInput(mode, point: point, expect: expect, hold: hold) { burst in
            burst.step(after: 0) { postMouse(.mouseMoved, point, flags: []) }
            for _ in 0..<3 {
                burst.step(after: 0.08) {
                    // Pixel units, as a trackpad sends: Ice reads the scrolling deltas.
                    let event = CGEvent(scrollWheelEvent2Source: eventSource, units: .pixel, wheelCount: 1, wheel1: Int32(delta), wheel2: 0, wheel3: 0)
                    event?.location = point
                    event?.post(tap: tapLocation)
                }
            }
        }
    case "key":
        guard arguments.count > 1, let code = UInt16(arguments[1]), let flags = Rule.modifiers(option("--mods")) else { usage() }
        return runInput(mode, point: nil, expect: nil, hold: hold) { burst in
            for down in [true, false] {
                burst.step(after: 0.06) {
                    let event = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down)
                    event?.flags = functionKeyCodes.contains(code) ? flags.union(.maskSecondaryFn) : flags
                    keyWasPosted = true
                    event?.post(tap: .cghidEventTap)
                }
            }
        }
    case "command":
        guard let x = number(1), let y = number(2), let seconds = number(3) else { usage() }
        let point = CGPoint(x: x, y: y)
        watchdogSeconds += Double(seconds)
        return runInput(mode, point: nil, expect: nil, hold: hold) { burst in
            burst.step(after: 0) { postMouse(.mouseMoved, point, flags: []) }
            burst.step(after: 0.2) { commandIsDown = true; postCommand(down: true) }
            burst.step(after: Double(seconds)) { if postCommand(down: false) { commandIsDown = false } }
        }
    case "drag":
        guard let x1 = number(1), let y1 = number(2), let x2 = number(3), let y2 = number(4), let expect = option("--expect") else { usage() }
        let start = CGPoint(x: x1, y: y1), end = CGPoint(x: x2, y: y2)
        let seconds = option("--seconds").flatMap(Double.init) ?? 0.8
        let commandFirst = option("--command-first").flatMap(Double.init) ?? 0.12
        let pause = option("--pause").flatMap(Double.init) ?? 0
        let returns = arguments.contains("--return")
        let steps = 30
        watchdogSeconds += seconds * 2 + commandFirst + pause
        var refusedAfterCommand: String?
        // The expectation is checked once Command is down: an item Ice hides
        // is on the bar only then.
        let code = runInput(mode, point: nil, expect: nil, hold: hold) { burst in
            func leg(from: CGPoint, to: CGPoint) {
                for index in 1...steps {
                    let fraction = CGFloat(index) / CGFloat(steps)
                    let point = CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
                    guard burst.step(after: seconds / Double(steps), { postMouse(.leftMouseDragged, point, flags: .maskCommand) }) else { break }
                }
            }
            burst.step(after: 0) { postMouse(.mouseMoved, start, flags: []) }
            burst.step(after: 0.1) { commandIsDown = true; postCommand(down: true) }
            burst.step(after: commandFirst) { refusedAfterCommand = expectationFailure(expect, at: start) }
            if refusedAfterCommand == nil {
                burst.step(after: 0.02) {
                    heldButton = .left
                    heldFlags = .maskCommand
                    postMouse(.leftMouseDown, start, flags: .maskCommand)
                }
                leg(from: start, to: end)
                if pause > 0 { burst.step(after: pause) { } }
                if returns { leg(from: end, to: start) }
                burst.step(after: 0.05) { if postMouse(.leftMouseUp, returns ? start : end, flags: .maskCommand) { heldButton = nil } }
            }
            burst.step(after: 0.08) { if postCommand(down: false) { commandIsDown = false } }
        }
        if let refusedAfterCommand, code == 0 {
            emit(["mode": mode, "result": "refused", "reason": refusedAfterCommand])
            return 3
        }
        return code
    default:
        usage()
    }
}

exit(main())
