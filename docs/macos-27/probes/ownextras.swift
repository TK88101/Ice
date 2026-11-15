// Read-only probe for the 27.2 own-divider question.
//   ownextras watch <icePid> <seconds>   polls, prints a line only when it changes:
//       own   Ice's AXExtrasMenuBar children          [identifier x w]
//       win   Ice's on-screen windows above layer 0   [layer x w]
//       all   every other app's extras, by x          pid:x:w
//   ownextras quit <pid> <expected bundle path>       asks that app to quit (NSRunningApplication.terminate)
import AppKit
import ApplicationServices
import Foundation

func attr(_ element: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return (error, value)
}

struct Extra {
    let identifier: String
    let x: Int
    let width: Int
}

/// `nil` when the extras bar could not be read; the string says why.
func extras(of pid: pid_t) -> (items: [Extra]?, error: String?) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.25)
    let (barError, bar) = attr(app, "AXExtrasMenuBar")
    guard barError == .success, let bar else { return (nil, "extras \(barError.rawValue)") }
    // swiftlint:disable:next force_cast
    let (childError, children) = attr(bar as! AXUIElement, "AXChildren")
    guard childError == .success else { return (nil, "children \(childError.rawValue)") }
    let elements = (children as? [AXUIElement]) ?? []
    return (elements.map { child in
        let identifier = attr(child, "AXIdentifier")
        var point = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        if let value = attr(child, "AXPosition").1 { AXValueGetValue(value as! AXValue, .cgPoint, &point) }
        if let value = attr(child, "AXSize").1 { AXValueGetValue(value as! AXValue, .cgSize, &size) }
        // swiftlint:enable force_cast
        return Extra(
            identifier: (identifier.1 as? String) ?? "nil(\(identifier.0.rawValue))",
            x: Int(point.x), width: Int(size.width)
        )
    }, nil)
}

func windows(of pid: pid_t) -> String {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int).map { pid_t($0) } == pid }
    let parts = mine.compactMap { info -> String? in
        guard let layer = info[kCGWindowLayer as String] as? Int, layer > 0,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? Double, let width = bounds["Width"] as? Double
        else { return nil }
        return "[L\(layer) x=\(Int(x)) w=\(Int(width))]"
    }
    return parts.sorted().joined(separator: " ")
}

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    FileHandle.standardError.write(Data("usage: ownextras watch <pid> <seconds> | quit <pid> <bundle path>\n".utf8))
    exit(2)
}

if arguments[1] == "quit" {
    guard let pid = pid_t(arguments[2]), let app = NSRunningApplication(processIdentifier: pid),
          app.bundleURL?.path == arguments[3]
    else {
        print("refused: pid is not the app at that path")
        exit(1)
    }
    print("terminate asked:", app.terminate())
    exit(0)
}

let formatter = DateFormatter()
formatter.dateFormat = "HH:mm:ss.SSS"
func stamp() -> String { formatter.string(from: Date()) }
func describe(_ pid: pid_t) -> String {
    let read = extras(of: pid)
    return read.items.map { items in
        "\(items.count) " + items.map { "[\($0.identifier) x=\($0.x) w=\($0.width)]" }.joined(separator: " ")
    } ?? (read.error ?? "?")
}

// guard <targetPid> <spacerPid>: exit 0 only when both helpers are on the bar,
// the target left of the spacer, and the spacer left of every other app's item
// (so a longer spacer pushes nothing but the target).
if arguments[1] == "guard" {
    guard let target = pid_t(arguments[2]), let spacer = pid_t(arguments[3]) else { exit(2) }
    let targetX = extras(of: target).items?.first?.x
    let spacerX = extras(of: spacer).items?.first?.x
    let others = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        .filter { $0 != target && $0 != spacer && $0 != getpid() }
        .flatMap { extras(of: $0).items ?? [] }.map(\.x).filter { $0 > 0 }
    print("guard target x:", targetX as Any, "spacer x:", spacerX as Any, "leftmost other x:", others.min() as Any)
    guard let targetX, let spacerX, let leftmost = others.min(), targetX > 0, targetX < spacerX, spacerX < leftmost else {
        print("guard: refused")
        exit(1)
    }
    print("guard: ok")
    exit(0)
}

// hold <targetPid> <spacerPid> <seconds> <freshAt> <heldAt> <freshRestAt>:
// keeps the target's element as read at the start, reports both helpers'
// extras and what the held element still answers, and presses the target
// (ours) by a fresh lookup at freshAt and freshRestAt, by the held element at heldAt.
if arguments[1] == "hold" {
    guard arguments.count >= 8, let target = pid_t(arguments[2]), let spacer = pid_t(arguments[3]),
          let seconds = Double(arguments[4]), let freshAt = Double(arguments[5]),
          let heldAt = Double(arguments[6]), let freshRestAt = Double(arguments[7])
    else { exit(2) }

    func children(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let bar = attr(app, "AXExtrasMenuBar").1 else { return [] }
        // swiftlint:disable:next force_cast
        return (attr(bar as! AXUIElement, "AXChildren").1 as? [AXUIElement]) ?? []
    }
    func press(_ element: AXUIElement, _ label: String) {
        AXUIElementSetMessagingTimeout(element, 8)
        let began = Date()
        print(stamp(), label, "pressing")
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        print(stamp(), label, "returned \(error.rawValue) after \(String(format: "%.2f", Date().timeIntervalSince(began))) s")
    }

    guard let held = children(of: target).first else {
        print("hold: the target is not listed at the start")
        exit(1)
    }
    print(stamp(), "held acquired")
    let background = DispatchQueue.global(qos: .userInitiated)
    for (delay, label) in [(freshAt, "press-fresh"), (freshRestAt, "press-fresh-rest")] {
        background.asyncAfter(deadline: .now() + delay) {
            guard let fresh = children(of: target).first else {
                print(stamp(), label, "not listed, nothing to press")
                return
            }
            press(fresh, label)
        }
    }
    background.asyncAfter(deadline: .now() + heldAt) { press(held, "press-held") }

    var lastLines = [String: String]()
    let began = Date()
    while Date().timeIntervalSince(began) < seconds {
        let role = attr(held, kAXRoleAttribute)
        var point = CGPoint.zero
        let position = attr(held, "AXPosition")
        // swiftlint:disable:next force_cast
        if let value = position.1 { AXValueGetValue(value as! AXValue, .cgPoint, &point) }
        let lines = [
            "tgt": describe(target),
            "spc": describe(spacer),
            "ref": "role \(role.0.rawValue) position \(position.0.rawValue) x=\(Int(point.x))",
        ]
        for (kind, line) in lines.sorted(by: { $0.key < $1.key }) where lastLines[kind] != line {
            lastLines[kind] = line
            print(stamp(), kind, line)
        }
        usleep(150_000)
    }
    exit(0)
}

// agent <targetPid> <spacerPid> <seconds> <pressAt>: MenuBarAgent's own tree
// (one AXWindow per bar, one child per slot, the slot's child is the owning
// app's). Reports every slot as owner:x:w (T = target, S = spacer), and at
// pressAt presses the target (ours) through the slot's hosted child, then
// through the slot itself if that did not answer 0.
if arguments[1] == "agent" {
    guard arguments.count >= 6, let target = pid_t(arguments[2]), let spacer = pid_t(arguments[3]),
          let seconds = Double(arguments[4]), let pressAt = Double(arguments[5]),
          let agentApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
    else {
        print("agent: bad arguments or no MenuBarAgent")
        exit(2)
    }
    let agent = AXUIElementCreateApplication(agentApp.processIdentifier)
    AXUIElementSetMessagingTimeout(agent, 0.25)

    struct Slot {
        let element: AXUIElement
        let hosted: AXUIElement?
        let owner: pid_t
        let x: Int
        let width: Int
    }
    func elements(_ value: CFTypeRef?) -> [AXUIElement] { (value as? [AXUIElement]) ?? [] }
    func rect(_ element: AXUIElement) -> (x: Int, width: Int)? {
        var point = CGPoint.zero
        var size = CGSize.zero
        guard let position = attr(element, "AXPosition").1, let extent = attr(element, "AXSize").1 else { return nil }
        // swiftlint:disable force_cast
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(extent as! AXValue, .cgSize, &size)
        // swiftlint:enable force_cast
        return (Int(point.x), Int(size.width))
    }
    func slots() -> [Slot] {
        var result = [Slot]()
        for window in elements(attr(agent, "AXChildren").1) where attr(window, "AXRole").1 as? String == "AXWindow" {
            for child in elements(attr(window, "AXChildren").1) {
                guard let frame = rect(child) else { continue }
                let hosted = elements(attr(child, "AXChildren").1).first
                var owner = agentApp.processIdentifier
                if let hosted { AXUIElementGetPid(hosted, &owner) }
                result.append(Slot(element: child, hosted: hosted, owner: owner, x: frame.x, width: frame.width))
            }
        }
        return result.sorted { $0.x < $1.x }
    }
    func actions(_ element: AXUIElement) -> String {
        var names: CFArray?
        let error = AXUIElementCopyActionNames(element, &names)
        return "actions(\(error.rawValue)) \((names as? [String]) ?? [])"
    }
    func press(_ element: AXUIElement, _ label: String) -> AXError {
        AXUIElementSetMessagingTimeout(element, 8)
        let began = Date()
        print(stamp(), label, "pressing;", "role", attr(element, "AXRole").1 as? String ?? "nil",
              "identifier", attr(element, "AXIdentifier").1 as? String ?? "nil", actions(element))
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        print(stamp(), label, "returned \(error.rawValue) after \(String(format: "%.2f", Date().timeIntervalSince(began))) s")
        return error
    }

    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + pressAt) {
        guard let slot = slots().first(where: { $0.owner == target }) else {
            print(stamp(), "press-agent: no slot of the target in the agent's tree")
            return
        }
        print(stamp(), "press-agent: target slot x=\(slot.x) w=\(slot.width)")
        if let hosted = slot.hosted, press(hosted, "press-hosted") == .success { return }
        _ = press(slot.element, "press-slot")
    }

    var lastLine = ""
    let began = Date()
    while Date().timeIntervalSince(began) < seconds {
        let line = slots().map { slot -> String in
            let mark = slot.owner == target ? "T" : slot.owner == spacer ? "S" : slot.owner == agentApp.processIdentifier ? "A" : ""
            return "\(mark)\(slot.owner):\(slot.x):\(slot.width)"
        }.joined(separator: " ")
        if line != lastLine {
            lastLine = line
            print(stamp(), "slots", line)
        }
        usleep(150_000)
    }
    exit(0)
}

guard arguments[1] == "watch", let icePID = pid_t(arguments[2]), let seconds = Double(arguments[3]) else { exit(2) }

print("trusted:", AXIsProcessTrusted())

let others = NSWorkspace.shared.runningApplications.map(\.processIdentifier).filter { $0 != icePID && $0 != getpid() }
var last = [String: String]()
func emit(_ kind: String, _ line: String) {
    guard last[kind] != line else { return }
    last[kind] = line
    print(formatter.string(from: Date()), kind, line)
}

let start = Date()
while Date().timeIntervalSince(start) < seconds {
    let own = extras(of: icePID)
    emit("own", own.items.map { items in
        "\(items.count) " + items.map { "[\($0.identifier) x=\($0.x) w=\($0.width)]" }.joined(separator: " ")
    } ?? (own.error ?? "?"))
    emit("win", windows(of: icePID))

    var all = [(pid: pid_t, extra: Extra)]()
    for pid in others {
        for extra in extras(of: pid).items ?? [] { all.append((pid, extra)) }
    }
    emit("all", all.sorted { $0.extra.x < $1.extra.x }.map { "\($0.pid):\($0.extra.x):\($0.extra.width)" }.joined(separator: " "))
    usleep(150_000)
}
