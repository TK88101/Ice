// dragown -- Command-drags one of the harness's own status items across the
// other, to measure what macOS 27 remembers of a dragged position (plan
// 2026-10-07-icebar-preference-hiding, S2 design, T2b). Derived from
// inject3.swift (FINDINGS "The move primitive").
//
//   dragown read <target identifier> <anchor identifier>     no side effects
//   dragown drag <target identifier> <anchor identifier>     see below
//   dragown release                                           button up, Command up, whatever is held
//   dragown selftest                                          the rules, on made-up frames
//
// The target (T) must be the one status item with that AXIdentifier in a
// process of com.icespike4.target, the anchor (P) the one in a process of
// com.icespike4.protected. Nothing else is ever pressed or dragged; what is
// read is those two processes' own AXExtrasMenuBar and which process owns the
// element at the press and drop points.
//
// Side effects of `drag`: synthetic mouse and Command events in this login
// session and a moved cursor for about 2 s (restored). It refuses unless T and
// P are both on the bar and adjacent (their windows touch, so the path crosses
// only P), the element at the press point is T's process's and the one at the
// drop point T's or P's (the item itself, by its identifier: nothing covers the bar there), and no input arrived
// for 5 s. Before every posted event it reads the hardware idle time again and
// resolves T and P again from their pids; on hardware input, a changed
// identity, an unreadable element or -- until the button is down -- a changed
// frame or owner of those points it releases the button and Command, restores
// the cursor and ends as `aborted`. (Once the button is down the frames are
// expected to change: T follows the cursor and P gives way.) The watchdog and
// the signals release both too, under the lock every post takes, and exit
// holding it, so nothing is posted after a release (a main thread stuck in a
// post for a second is not waited for: exit 5, and the runner lets go again).
// `release` is for the runner, after a `drag` that died without letting go:
// it posts an up only for what this session holds and the hardware does not.
// Not closed, and inherent: a window that appears over T in the milliseconds
// between the last check and the press receives that press.
//
// One JSON object on stdout (`selftest`: its checks on stderr). Exit: 0 moved
// (or read / release / selftest ok), 1 not moved (or read / release / selftest
// failed), 2 usage, 3 refused, 4 aborted, 5 aborted and not let go for certain.
import ApplicationServices
import Cocoa

// MARK: - Rules (pure; `dragown selftest` checks them)

enum Rule {
    static let targetBundle = "com.icespike4.target"
    static let anchorBundle = "com.icespike4.protected"
    /// Between the AX frames of two helper items whose windows touch: each
    /// frame (14 pt) is inset 7 pt in its 28 pt window (measured with the
    /// helpers' own `frames`, 26A434, 2026-10-08). A third item between them
    /// would add its whole window; stacked (overflowed) frames have no gap.
    static let adjacentGap: CGFloat = 14
    static let gapTolerance: CGFloat = 2
    static let frameTolerance: CGFloat = 0.5
    static let barHeight: CGFloat = 40
    static let requiredIdleSeconds = 5.0
    /// The drop point, from the anchor's middle, in anchor frame widths: past
    /// its middle (where the two swap), still inside its window.
    static let dropPastAnchorMiddle: CGFloat = 0.75

    static func isOnBar(_ frame: CGRect, display: CGRect) -> Bool {
        frame.width > 0 && frame.height > 0
            && frame.minY >= display.minY && frame.maxY <= display.minY + barHeight
            && frame.minX >= display.minX && frame.maxX <= display.maxX
    }

    static func gap(_ first: CGRect, _ second: CGRect) -> CGFloat {
        max(first.minX, second.minX) - min(first.maxX, second.maxX)
    }

    static func areAdjacent(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(gap(first, second) - adjacentGap) <= gapTolerance
    }

    static func side(of target: CGRect, relativeTo anchor: CGRect) -> String {
        target.midX < anchor.midX ? "left" : "right"
    }

    static func isSameFrame(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) <= frameTolerance && abs(first.minY - second.minY) <= frameTolerance
            && abs(first.width - second.width) <= frameTolerance && abs(first.height - second.height) <= frameTolerance
    }

    static func dropPoint(target: CGRect, anchor: CGRect) -> CGPoint {
        let direction: CGFloat = target.midX < anchor.midX ? 1 : -1
        return CGPoint(x: anchor.midX + direction * anchor.width * dropPastAnchorMiddle, y: target.midY)
    }

    /// Why a drag may not start from this layout, or nil.
    static func refusal(target: CGRect, anchor: CGRect, display: CGRect, idleSeconds: Double) -> String? {
        guard isOnBar(target, display: display), isOnBar(anchor, display: display) else { return "notOnBar" }
        guard areAdjacent(target, anchor) else { return "notAdjacent" }
        guard isOnBar(CGRect(origin: dropPoint(target: target, anchor: anchor), size: CGSize(width: 1, height: 1)), display: display) else {
            return "dropPointOffBar"
        }
        guard idleSeconds >= requiredIdleSeconds else { return "hardwareInput" }
        return nil
    }
}

func selftest() -> Bool {
    let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    // The helpers as measured: 14 pt frames, 28 pt apart.
    let anchor = CGRect(x: 998, y: 4.5, width: 14, height: 24)
    let rightNeighbour = anchor.offsetBy(dx: 28, dy: 0)
    let leftNeighbour = anchor.offsetBy(dx: -28, dy: 0)
    let checks: [(String, Bool)] = [
        ("an item in the strip is on the bar", Rule.isOnBar(anchor, display: display)),
        ("a parked item (bottom left) is not", !Rule.isOnBar(CGRect(x: -1, y: 1104, width: 24, height: 24), display: display)),
        ("a frameless item is not", !Rule.isOnBar(.zero, display: display)),
        ("an item beyond the display's right edge is not", !Rule.isOnBar(CGRect(x: 1500, y: 4.5, width: 24, height: 24), display: display)),
        ("touching windows are adjacent", Rule.areAdjacent(anchor, rightNeighbour)),
        ("adjacency does not depend on the order", Rule.areAdjacent(rightNeighbour, anchor)),
        ("a third item's window between is not adjacent", !Rule.areAdjacent(anchor, anchor.offsetBy(dx: 56, dy: 0))),
        ("a gap 3 pt wider than touching is not adjacent", !Rule.areAdjacent(anchor, rightNeighbour.offsetBy(dx: 3, dy: 0))),
        ("stacked frames are not adjacent", !Rule.areAdjacent(anchor, anchor.offsetBy(dx: 2, dy: 0))),
        ("frames that touch (windows overlapping) are not adjacent", !Rule.areAdjacent(anchor, anchor.offsetBy(dx: 14, dy: 0))),
        ("left of the anchor", Rule.side(of: leftNeighbour, relativeTo: anchor) == "left"),
        ("right of the anchor", Rule.side(of: rightNeighbour, relativeTo: anchor) == "right"),
        ("a target on the right is dropped left of the anchor's middle, inside its window", Rule.dropPoint(target: rightNeighbour, anchor: anchor).x == 994.5),
        ("a target on the left is dropped right of the anchor's middle, inside its window", Rule.dropPoint(target: leftNeighbour, anchor: anchor).x == 1015.5),
        ("half a point is the same frame", Rule.isSameFrame(anchor, anchor.offsetBy(dx: 0.5, dy: 0))),
        ("one point is not", !Rule.isSameFrame(anchor, anchor.offsetBy(dx: 1, dy: 0))),
        ("adjacent, on the bar, idle: no refusal", Rule.refusal(target: rightNeighbour, anchor: anchor, display: display, idleSeconds: 5) == nil),
        ("recent hardware input refuses", Rule.refusal(target: rightNeighbour, anchor: anchor, display: display, idleSeconds: 4.9) == "hardwareInput"),
        ("a gap refuses", Rule.refusal(target: anchor.offsetBy(dx: 60, dy: 0), anchor: anchor, display: display, idleSeconds: 9) == "notAdjacent"),
        ("a parked target refuses", Rule.refusal(target: CGRect(x: -1, y: 1104, width: 24, height: 24), anchor: anchor, display: display, idleSeconds: 9) == "notOnBar"),
        ("a drop point off the display refuses", Rule.refusal(
            target: CGRect(x: 28, y: 4.5, width: 14, height: 24), anchor: CGRect(x: 0, y: 4.5, width: 14, height: 24), display: display, idleSeconds: 9
        ) == "dropPointOffBar"),
    ]
    for (name, holds) in checks {
        FileHandle.standardError.write(Data("\(holds ? "ok  " : "FAIL") \(name)\n".utf8))
    }
    return checks.allSatisfy(\.1)
}

// MARK: - Reading the two items

struct Item {
    let bundle: String
    let pid: pid_t
    let identifier: String
    let frame: CGRect
}

let messagingTimeout: Float = 0.25

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, messagingTimeout)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

/// The status items of `pid` that carry `identifier`; nil when the process's
/// extras bar cannot be read.
func items(pid: pid_t, bundle: String, identifier: String) -> [Item]? {
    let application = AXUIElementCreateApplication(pid)
    guard let bar = attribute(application, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID(),
          let children = attribute(bar as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement]
    else { return nil }
    var found = [Item]()
    for child in children where attribute(child, "AXIdentifier") as? String == identifier {
        guard let value = attribute(child, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var frame = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &frame) else { return nil }
        found.append(Item(bundle: bundle, pid: pid, identifier: identifier, frame: frame))
    }
    return found
}

/// The one item with that identifier in any running process of that bundle id.
func discover(bundle: String, identifier: String) -> Item? {
    let found = NSWorkspace.shared.runningApplications
        .filter { $0.bundleIdentifier == bundle && !$0.isTerminated }
        .flatMap { items(pid: $0.processIdentifier, bundle: bundle, identifier: identifier) ?? [] }
    return found.count == 1 ? found[0] : nil
}

/// The same item again, resolved from scratch: the pid first seen must still
/// be a process of that bundle id with exactly one item of that identifier.
func resolveAgain(_ first: Item) -> Item? {
    guard let application = NSRunningApplication(processIdentifier: first.pid),
          application.bundleIdentifier == first.bundle, !application.isTerminated,
          let found = items(pid: first.pid, bundle: first.bundle, identifier: first.identifier), found.count == 1
    else { return nil }
    return found[0]
}

// kCGAnyInputEventType
let anyInput = CGEventType(rawValue: ~0)!

/// Since the last hardware event; events posted at the session tap do not touch it.
func hardwareIdleSeconds() -> Double {
    CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
}

/// Since the last event of any origin, another tool's or a remote session's
/// included: what a drag must not start into. This probe's own events reset
/// it, so it is read before the first one only.
func sessionIdleSeconds() -> Double {
    min(hardwareIdleSeconds(), CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput))
}

/// How far above the element at a point its identified item is looked for.
let hitTestAncestors = 3

/// Whether the element at that point of the screen is that item: of its
/// process, and it or an ancestor carrying its identifier.
func isItem(_ item: Item, at point: CGPoint) -> Bool {
    var hit: AXUIElement?
    let systemWide = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
    guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success, var element = hit else { return false }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success, pid == item.pid else { return false }
    for _ in 0...hitTestAncestors {
        if attribute(element, "AXIdentifier") as? String == item.identifier { return true }
        guard let parent = attribute(element, kAXParentAttribute as String), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
        element = parent as! AXUIElement
    }
    return false
}

/// Why the press or the drop would not land on the harness's own items, or nil.
func coveredReason(target: Item, anchor: Item, from start: CGPoint, to end: CGPoint) -> String? {
    guard isItem(target, at: start) else { return "pressPointNotTarget" }
    guard isItem(anchor, at: end) || isItem(target, at: end) else { return "dropPointNotOurs" }
    return nil
}

func rectArray(_ rect: CGRect) -> [Double] {
    [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
}

func layout(target: Item, anchor: Item, display: CGRect) -> [String: Any] {
    [
        "target": ["pid": Int(target.pid), "frame": rectArray(target.frame), "onBar": Rule.isOnBar(target.frame, display: display)],
        "anchor": ["pid": Int(anchor.pid), "frame": rectArray(anchor.frame), "onBar": Rule.isOnBar(anchor.frame, display: display)],
        "side": Rule.side(of: target.frame, relativeTo: anchor.frame),
        "gap": Double(Rule.gap(target.frame, anchor.frame)),
        "adjacent": Rule.areAdjacent(target.frame, anchor.frame),
    ]
}

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

// MARK: - The drag

let tapLocation = CGEventTapLocation.cgSessionEventTap
let eventSource = CGEventSource(stateID: .combinedSessionState)
let commandKey: CGKeyCode = 0x37
let watchdogSeconds = 10.0
let dragSteps = 40

/// What is held down right now, so that every exit can let go of it. Set
/// before the event that holds it is posted, and read and written, like every
/// post, with `eventLock` held: a release from the watchdog or a signal waits
/// for the event being posted, and nothing is posted after it (`stopping`).
var buttonIsDown = false
var commandIsDown = false
var cursorWasMoved = false
var stopping = false
/// Every event is posted and nothing is held: the watchdog has nothing left to do.
var dragIsOver = false
var lastPoint = CGPoint.zero
let originalCursor = CGEvent(source: nil)?.location ?? .zero
let eventLock = NSLock()

/// Both posts say whether the event could be made and was posted: what is
/// held counts as let go only when its up event went out.
@discardableResult
func postMouse(_ type: CGEventType, _ point: CGPoint, command: Bool) -> Bool {
    guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return false }
    event.flags = command ? .maskCommand : []
    event.post(tap: tapLocation)
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

/// With `eventLock` held. What could not be let go of stays marked as held.
func releaseLocked() {
    stopping = true
    if buttonIsDown, postMouse(.leftMouseUp, lastPoint, command: commandIsDown) {
        buttonIsDown = false
    }
    if commandIsDown, postCommand(down: false) {
        commandIsDown = false
    }
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

/// How long the watchdog and the signals wait for a main thread that is
/// inside a post before going on without the lock.
let lockPatience: TimeInterval = 1

/// From the watchdog or a signal, on their own threads: lets go of everything
/// and exits still holding the lock, so the main thread cannot post again.
/// Without the lock (a main thread stuck inside a post) it lets go all the
/// same, and says so by its exit code: that post may still land afterwards.
/// Once the drag is over nothing is held and the main thread reports.
func releaseAndExit(reason: String) -> Never {
    let locked = eventLock.lock(before: Date().addingTimeInterval(lockPatience))
    if locked, dragIsOver { _exit(4) }
    releaseLocked()
    let letGo = locked && !buttonIsDown && !commandIsDown
    emit(["mode": "drag", "result": "aborted", "reason": letGo ? reason : "\(reason), not let go for certain"])
    // At once, without the exit handlers: the less time a stuck post has to land.
    _exit(letGo ? 4 : 5)
}

/// Posts under the lock; false when a release has already happened.
func postUnlessStopping(_ post: () -> Void) -> Bool {
    eventLock.lock()
    defer { eventLock.unlock() }
    guard !stopping else { return false }
    post()
    return true
}

/// Why the drag must stop before the next event, or nil.
func stopReason(target: Item, anchor: Item, pressed: Bool, from start: CGPoint, to end: CGPoint) -> String? {
    let idle = hardwareIdleSeconds()
    guard idle >= Rule.requiredIdleSeconds else { return "hardwareInput (idle \(idle) s)" }
    guard let targetNow = resolveAgain(target), let anchorNow = resolveAgain(anchor) else { return "unresolved" }
    guard !pressed else { return nil }
    guard Rule.isSameFrame(targetNow.frame, target.frame), Rule.isSameFrame(anchorNow.frame, anchor.frame) else { return "layoutChanged" }
    return coveredReason(target: target, anchor: anchor, from: start, to: end)
}

/// Posts the Command-drag; returns why it was aborted, or nil when every event was posted.
func performDrag(target: Item, anchor: Item, from start: CGPoint, to end: CGPoint) -> String? {
    var aborted: String?
    var pressed = false
    func step(after pause: TimeInterval, _ post: () -> Void) -> Bool {
        guard aborted == nil else { return false }
        Thread.sleep(forTimeInterval: pause)
        if let reason = stopReason(target: target, anchor: anchor, pressed: pressed, from: start, to: end) {
            aborted = reason
            releaseEverything()
            return false
        }
        guard postUnlessStopping(post) else {
            aborted = "released"
            return false
        }
        return true
    }
    // The cursor goes to T by an event, not a warp, so nothing touches the hardware state.
    _ = step(after: 0) { postMouse(.mouseMoved, start, command: false) }
    _ = step(after: 0.15) { commandIsDown = true; postCommand(down: true) }
    pressed = step(after: 0.12) { buttonIsDown = true; postMouse(.leftMouseDown, start, command: true) }
    // Many small steps: a pair of endpoints is not a drag.
    for index in 1...dragSteps {
        let fraction = CGFloat(index) / CGFloat(dragSteps)
        let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y)
        guard step(after: index == 1 ? 0.12 : 0.012, { postMouse(.leftMouseDragged, point, command: true) }) else { break }
    }
    _ = step(after: 0.25) { if postMouse(.leftMouseUp, end, command: true) { buttonIsDown = false } }
    _ = step(after: 0.1) { if postCommand(down: false) { commandIsDown = false } }
    eventLock.lock()
    releaseLocked()
    dragIsOver = true
    eventLock.unlock()
    return aborted
}

/// Kept alive for the process's life.
var signalSources = [DispatchSourceSignal]()

/// The watchdog and the signals: each lets go of everything, then exits.
func armReleases() {
    let watchdog = Thread {
        Thread.sleep(forTimeInterval: watchdogSeconds)
        releaseAndExit(reason: "watchdog")
    }
    watchdog.start()
    // Not C handlers: letting go posts events, which is not async-signal-safe.
    for number in [SIGINT, SIGTERM, SIGHUP, SIGALRM] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { releaseAndExit(reason: "signal \(number)") }
        source.resume()
        signalSources.append(source)
    }
}

func runDrag(targetIdentifier: String, anchorIdentifier: String) -> Int32 {
    let display = CGDisplayBounds(CGMainDisplayID())
    var report: [String: Any] = ["mode": "drag", "idleAtStart": sessionIdleSeconds()]
    func finish(_ result: String, _ reason: String?, _ code: Int32) -> Int32 {
        report["result"] = result
        report["reason"] = reason ?? NSNull()
        emit(report)
        return code
    }
    guard AXIsProcessTrusted(), eventSource != nil else { return finish("refused", "notTrusted", 3) }
    guard let target = discover(bundle: Rule.targetBundle, identifier: targetIdentifier),
          let anchor = discover(bundle: Rule.anchorBundle, identifier: anchorIdentifier)
    else { return finish("refused", "notFound", 3) }
    report["before"] = layout(target: target, anchor: anchor, display: display)
    if let refusal = Rule.refusal(target: target.frame, anchor: anchor.frame, display: display, idleSeconds: sessionIdleSeconds()) {
        return finish("refused", refusal, 3)
    }
    let start = CGPoint(x: target.frame.midX, y: target.frame.midY)
    let end = Rule.dropPoint(target: target.frame, anchor: anchor.frame)
    report["from"] = [Double(start.x), Double(start.y)]
    report["to"] = [Double(end.x), Double(end.y)]
    if let covered = coveredReason(target: target, anchor: anchor, from: start, to: end) {
        return finish("refused", covered, 3)
    }

    armReleases()
    defer { releaseEverything() }

    let aborted = performDrag(target: target, anchor: anchor, from: start, to: end)
    report["idleAtEnd"] = hardwareIdleSeconds()
    // Still marked as held: an up event could not be made. The runner lets go.
    guard !buttonIsDown, !commandIsDown else { return finish("aborted", "notLetGo", 5) }
    if let aborted { return finish("aborted", aborted, 4) }

    // Did it hold? Sampled until stable rather than read in a transition frame.
    Thread.sleep(forTimeInterval: 0.6)
    var sides = [String]()
    var last = (target: target, anchor: anchor)
    for _ in 0..<5 {
        guard let targetNow = resolveAgain(target), let anchorNow = resolveAgain(anchor) else {
            return finish("notMoved", "unresolvedAfter", 1)
        }
        sides.append(Rule.side(of: targetNow.frame, relativeTo: anchorNow.frame))
        last = (targetNow, anchorNow)
        Thread.sleep(forTimeInterval: 0.4)
    }
    report["sides"] = sides
    report["after"] = layout(target: last.target, anchor: last.anchor, display: display)
    let sideBefore = Rule.side(of: target.frame, relativeTo: anchor.frame)
    guard Set(sides).count == 1 else { return finish("notMoved", "unstable", 1) }
    guard sides[0] != sideBefore else { return finish("notMoved", "sameSide", 1) }
    guard Rule.isOnBar(last.target.frame, display: display), Rule.isOnBar(last.anchor.frame, display: display) else {
        return finish("notMoved", "offBarAfter", 1)
    }
    return finish("moved", nil, 0)
}

func runRead(targetIdentifier: String, anchorIdentifier: String) -> Int32 {
    guard AXIsProcessTrusted() else {
        emit(["mode": "read", "error": "notTrusted"])
        return 1
    }
    guard let target = discover(bundle: Rule.targetBundle, identifier: targetIdentifier),
          let anchor = discover(bundle: Rule.anchorBundle, identifier: anchorIdentifier)
    else {
        emit(["mode": "read", "error": "notFound"])
        return 1
    }
    var report = layout(target: target, anchor: anchor, display: CGDisplayBounds(CGMainDisplayID()))
    let idle = sessionIdleSeconds()
    let start = CGPoint(x: target.frame.midX, y: target.frame.midY)
    report["mode"] = "read"
    report["idle"] = idle
    report["idleEnough"] = idle >= Rule.requiredIdleSeconds
    report["covered"] = coveredReason(target: target, anchor: anchor, from: start, to: Rule.dropPoint(target: target.frame, anchor: anchor.frame)) ?? NSNull()
    emit(report)
    return 0
}

/// What a dead `drag` left held: what the session shows as down and the
/// hardware does not (the owner's own held button or key is theirs). The
/// cursor stays where it is.
func runRelease() -> Int32 {
    guard eventSource != nil, let cursor = CGEvent(source: nil)?.location else {
        emit(["mode": "release", "error": "noEventSource"])
        return 1
    }
    buttonIsDown = CGEventSource.buttonState(.combinedSessionState, button: .left) && !CGEventSource.buttonState(.hidSystemState, button: .left)
    commandIsDown = CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
        && !CGEventSource.flagsState(.hidSystemState).contains(.maskCommand)
    lastPoint = cursor
    var released: [String: Any] = ["mode": "release", "button": buttonIsDown, "command": commandIsDown]
    releaseEverything()
    released["letGo"] = !buttonIsDown && !commandIsDown
    emit(released)
    return buttonIsDown || commandIsDown ? 1 : 0
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch (arguments.first, arguments.count) {
case ("selftest", 1): exit(selftest() ? 0 : 1)
case ("release", 1): exit(runRelease())
case ("read", 3): exit(runRead(targetIdentifier: arguments[1], anchorIdentifier: arguments[2]))
case ("drag", 3): exit(runDrag(targetIdentifier: arguments[1], anchorIdentifier: arguments[2]))
default:
    FileHandle.standardError.write(Data("usage: dragown read|drag <target identifier> <anchor identifier> | dragown release | dragown selftest\n".utf8))
    exit(2)
}
