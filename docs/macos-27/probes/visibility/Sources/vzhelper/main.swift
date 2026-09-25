// vzhelper -- sacrificial menu bar items for the live harnesses
// (docs/plans/2026-09-19-visibility-adapter.md section 6, and
// docs/plans/2026-09-23-ax-discovery.md section 6 / T8a).
//
//   vzhelper --controller <pid> --role target|reference|twin
//       one item, identifier "vz-<role>", the role's glyph (2026-09-19 form)
//   vzhelper --controller <pid> --role spacer
//       C1 (docs/plans/2026-09-26-c1-protocol.md section 2): one status
//       item resting as Ice's own control item rests (`variableLength` plus
//       a chevron image, no marker views). Controlled by two more stdin
//       commands, parsed by C1Core's own `SpacerCommandParser`:
//         length <pt>  -> image = nil, length = pt (0-1000, else refused)
//         rest         -> image = chevron, length = variableLength
//
//   vzhelper --controller <pid> --items 1|2 --identifiers none|<a>[,<b>]
//            [--glyphs <g>[,<g>]] [--mimic-nodivider] [--autosave <name>]
//            [--lifetime <seconds>]
//       --glyphs      target | reference | alt, one per item (not needed
//                     with --mimic-nodivider, which draws nothing)
//       --identifiers `none` sets no AXIdentifier at all
//       --mimic-nodivider  each item is put into Ice's `.noDivider` shown
//                     state exactly as ControlItem.swift does it (af4baf1,
//                     :69-86, :337-339, :369-374, :408-428)
//       --autosave    only for T8b step 10; one item only; written to this
//                     bundle id's own defaults domain, which the harness
//                     deletes before and after
//
// Never a filled block: every glyph is VZGlyphs' stroked shape.
//
// Controlled over stdin, one command per line -- never signals: a recycled
// pid would make a stray SIGUSR1 dangerous to whatever process reused it.
//   hide [<i>]  -> isVisible = false (every item, or item <i>)
//   show [<i>]  -> isVisible = true
//   frames      -> one `frames <json>` line: each item's own AppKit state
//   selfread    -> one `selfread <json>` line: this process reads its own
//                  AXExtrasMenuBar from a background queue while the main
//                  thread keeps running the app (plan 6 step 10)
//   stall <s>   -> `stalling {"seconds":s}`, then the main thread sleeps s
//                  seconds (0 < s <= 30), then `resumed {"seconds":s}`: a
//                  process whose Accessibility requests go unanswered, for the
//                  responsiveness-quarantine live checks (2026-09-25 plan,
//                  section 6). All three deadmen below, and EOF, run on the main
//                  queue, so during a stall they fire late; stalls add up to at
//                  most 60 s over the helper's life, so never later than that.
//   quit, EOF   -> exit(0)
// Replies go to stdout, one line each, written unbuffered.
//
// Two more deadmen, because the user's bar must never keep these items
// because the controller crashed or forgot about them:
//   - a DispatchSource process-exit watch on --controller;
//   - a lifetime cap (default 300 s), independent of the controller.
import AppKit
import ApplicationServices
import C1Core
import VZGlyphs

func option(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

func usage(_ problem: String) -> Never {
    FileHandle.standardError.write(Data("vzhelper: \(problem)\nusage: vzhelper --controller <pid> (--role target|reference|twin|spacer | --items 1|2 --identifiers none|<a>[,<b>] [--glyphs <g>[,<g>]] [--mimic-nodivider] [--autosave <name>]) [--lifetime <s>]\n".utf8))
    exit(64)
}

struct ItemSpec {
    let identifier: String?
    let glyph: Glyph?
}

struct Config {
    let items: [ItemSpec]
    let mimicNoDivider: Bool
    let autosave: String?
    let lifetime: Double
    /// C1's spacer role (I2): `items` is empty and `mimicNoDivider` is
    /// irrelevant -- the spacer is neither a glyph item nor a `.noDivider`
    /// stand-in, it is driven by `length`/`rest` alone.
    let spacer: Bool
}

func parseConfig() -> Config {
    let lifetime = option("--lifetime").flatMap(Double.init) ?? 300
    guard lifetime > 0, lifetime <= 1800 else { usage("--lifetime must be in (0, 1800]") }

    if let roleName = option("--role") {
        if roleName == "spacer" {
            return Config(items: [], mimicNoDivider: false, autosave: nil, lifetime: lifetime, spacer: true)
        }
        let glyph: Glyph
        switch roleName {
        case "target", "twin": glyph = .target
        case "reference": glyph = .reference
        default: usage("unknown --role \(roleName)")
        }
        return Config(items: [ItemSpec(identifier: "vz-\(roleName)", glyph: glyph)], mimicNoDivider: false, autosave: nil, lifetime: lifetime, spacer: false)
    }

    guard let count = option("--items").flatMap(Int.init), (1...2).contains(count) else {
        usage("--items must be 1 or 2")
    }
    guard let identifierList = option("--identifiers") else { usage("missing --identifiers") }
    let identifiers: [String?] = identifierList == "none"
        ? Array(repeating: nil, count: count)
        : identifierList.split(separator: ",").map { String($0) }
    guard identifiers.count == count else { usage("--identifiers needs \(count) entries or `none`") }

    let mimic = CommandLine.arguments.contains("--mimic-nodivider")
    var glyphs = [Glyph?](repeating: nil, count: count)
    if let glyphList = option("--glyphs") {
        let parsed = glyphList.split(separator: ",").map { Glyph(rawValue: String($0)) }
        guard parsed.count == count, parsed.allSatisfy({ $0 != nil }) else { usage("--glyphs needs \(count) of target|reference|alt") }
        glyphs = parsed
    } else if !mimic {
        usage("--glyphs is required unless --mimic-nodivider")
    }

    let autosave = option("--autosave")
    if autosave != nil, count != 1 { usage("--autosave takes one item only") }

    let items = zip(identifiers, glyphs).map { ItemSpec(identifier: $0, glyph: $1) }
    return Config(items: items, mimicNoDivider: mimic, autosave: autosave, lifetime: lifetime, spacer: false)
}

// Plain globals, not `guard let` locals: the delegate class and the stdin
// handler both need to capture them.
guard let controller = option("--controller").flatMap({ pid_t($0) }) else { usage("missing --controller") }
let config = parseConfig()
guard kill(controller, 0) == 0 else {
    exit(0)
}

let itemLengthPt: CGFloat = 12

func reply(_ kind: String, _ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8)
    else {
        FileHandle.standardOutput.write(Data("\(kind) {\"error\":\"unencodable\"}\n".utf8))
        return
    }
    FileHandle.standardOutput.write(Data("\(kind) \(text)\n".utf8))
}

@Sendable func rectArray(_ rect: CGRect) -> [Double] {
    [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
}

final class HelperItem {
    let index: Int
    let spec: ItemSpec
    let statusItem: NSStatusItem
    /// The content view's width constraint that Ice deactivates in the
    /// `.noDivider` shown state -- found only with --mimic-nodivider.
    let constraint: NSLayoutConstraint?
    /// How many constraints matched Ice's predicate (1 is what Ice asserts).
    let matchingConstraints: Int

    init(index: Int, spec: ItemSpec, statusItem: NSStatusItem, constraint: NSLayoutConstraint?, matchingConstraints: Int = 0) {
        self.index = index
        self.spec = spec
        self.statusItem = statusItem
        self.constraint = constraint
        self.matchingConstraints = matchingConstraints
    }

    /// Whether the item ended in Ice's `.noDivider` shown state: length 0,
    /// the width constraint inactive, a 1 pt window.
    var reachedNoDividerState: Bool {
        guard let constraint, !constraint.isActive, statusItem.length == 0,
              let window = statusItem.button?.window else { return false }
        return window.frame.width == 1
    }

    func state() -> [String: Any] {
        var object: [String: Any] = [
            "index": index,
            "identifier": spec.identifier ?? NSNull(),
            "isVisible": statusItem.isVisible,
            "length": Double(statusItem.length),
            "autosaveName": statusItem.autosaveName as String,
            "constraintFound": constraint != nil,
            "constraintActive": constraint?.isActive ?? NSNull(),
            "matchingConstraints": matchingConstraints,
            "reachedNoDividerState": reachedNoDividerState,
        ]
        if let button = statusItem.button {
            object["buttonAXIdentifier"] = button.accessibilityIdentifier()
            if let window = button.window {
                object["windowFrame"] = rectArray(window.frame)
                object["screenFrame"] = window.screen.map { rectArray($0.frame) } ?? NSNull()
            }
        }
        return object
    }
}

/// A plain status item with a glyph. With --autosave, the name is set right
/// after creation, as `ControlItem.swift:69-70` does, then the identifier
/// inside `if let button`, where plan 4.4 puts D9's line.
func makePlainItem(index: Int, spec: ItemSpec) -> HelperItem {
    let item = NSStatusBar.system.statusItem(withLength: itemLengthPt)
    if let autosave = config.autosave {
        item.autosaveName = autosave
    }
    if let button = item.button {
        if let identifier = spec.identifier {
            button.setAccessibilityIdentifier(identifier)
        }
        if let glyph = spec.glyph {
            button.image = Glyphs.image(glyph, side: itemLengthPt)
        }
        button.imagePosition = .imageOnly
    }
    item.isVisible = true
    return HelperItem(index: index, spec: spec, statusItem: item, constraint: nil)
}

/// Ice's hidden divider in the `.showSection` state with the default
/// `.noDivider` style, from `ControlItem.swift` at af4baf1, reached the way
/// Ice reaches it without an expansion: the item is created at length 0
/// (:69-72, with the button's target and action as :91-93 set them); on
/// the next main-queue turn it takes `updateStatusItemVisibility(true)` with
/// the standard length (:413-415 -- the `.chevron` style's shown state), and
/// on the turn after that the style's `.noDivider` sequence (:337-339,
/// :369-374, :416-428), so `length = 0` is a real change, as it is in Ice.
/// Ice's `.hideSection` length (10 000 pt) is never used: no experiment may
/// expand a spacer.
func makeNoDividerItem(index: Int, spec: ItemSpec, target: Delegate) -> HelperItem {
    let item = NSStatusBar.system.statusItem(withLength: 0)
    if let autosave = config.autosave {
        item.autosaveName = autosave
    }

    var constraint: NSLayoutConstraint?
    var matching = 0
    if let button = item.button {
        // D9 (plan 4.4): the identifier inside the existing `if let button`.
        if let identifier = spec.identifier {
            button.setAccessibilityIdentifier(identifier)
        }
        // :81-86 with Predicates.swift:40-44. Ice's `assert` of exactly one
        // match is compiled out of a release build, so Ice takes the first;
        // the count is recorded so an ambiguous layout is visible.
        if let constraints = button.window?.contentView?.constraintsAffectingLayout(for: .horizontal) {
            let found = constraints.filter { $0.secondItem === button.superview }
            matching = found.count
            constraint = found.first
        }
        button.target = target
        button.action = #selector(Delegate.performAction)
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
    }
    return HelperItem(index: index, spec: spec, statusItem: item, constraint: constraint, matchingConstraints: matching)
}

/// `updateStatusItemVisibility(true)` with the standard length.
func applyStandardLength(_ helperItem: HelperItem) {
    helperItem.constraint?.isActive = true
    helperItem.statusItem.length = NSStatusItem.variableLength
}

/// `updateStatusItem()` for `.hidden` in `.showSection` with `.noDivider`,
/// no drag in progress.
func applyNoDivider(_ helperItem: HelperItem) {
    let item = helperItem.statusItem
    guard let button = item.button else { return }
    // :337-339
    button.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
    button.title = ""
    button.image = nil
    // :372 -> :416-428 (shouldShow == false)
    helperItem.constraint?.isActive = false
    item.length = 0
    if let window = button.window {
        var size = window.frame.size
        size.width = 1
        window.setContentSize(size)
    }
    // :373-374
    button.appearsDisabled = true
    button.isHighlighted = false
}

/// Reads this process's own `AXExtrasMenuBar` -- read-only, with the
/// messaging timeout set on every element (it does not carry over).
func selfRead() -> [String: Any] {
    let timeout: Float = 0.25
    let start = DispatchTime.now()
    var object: [String: Any] = [
        "trusted": AXIsProcessTrusted(),
        "isMainThread": Thread.isMainThread,
    ]

    let app = AXUIElementCreateApplication(getpid())
    AXUIElementSetMessagingTimeout(app, timeout)
    var barValue: CFTypeRef?
    let barError = AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &barValue)
    object["extrasError"] = Int(barError.rawValue)

    if barError == .success, let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID() {
        let bar = barValue as! AXUIElement
        AXUIElementSetMessagingTimeout(bar, timeout)
        var childrenValue: CFTypeRef?
        let childrenError = AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenValue)
        object["childrenError"] = Int(childrenError.rawValue)
        let children = (childrenValue as? [AXUIElement]) ?? []
        object["children"] = children.map { child -> [String: Any] in
            AXUIElementSetMessagingTimeout(child, timeout)
            var entry = [String: Any]()
            var identifier: CFTypeRef?
            let identifierError = AXUIElementCopyAttributeValue(child, "AXIdentifier" as CFString, &identifier)
            entry["identifierError"] = Int(identifierError.rawValue)
            entry["identifier"] = (identifier as? String) ?? NSNull()
            var frameValue: CFTypeRef?
            let frameError = AXUIElementCopyAttributeValue(child, "AXFrame" as CFString, &frameValue)
            entry["frameError"] = Int(frameError.rawValue)
            if frameError == .success, let frameValue, CFGetTypeID(frameValue) == AXValueGetTypeID() {
                var rect = CGRect.zero
                AXValueGetValue(frameValue as! AXValue, .cgRect, &rect)
                entry["frame"] = rectArray(rect)
            }
            return entry
        }
    }
    object["elapsedMs"] = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    return object
}

/// C1's spacer role (I2, section 2): rests exactly as Ice's own control
/// item rests -- `variableLength` plus a chevron-sized template image, the
/// same rest shape `probes/safewidth/Sources/swctl/Spacer.swift` uses for
/// its own instrumented spacer -- but with no marker views: I2 only needs
/// the rest/expand behaviour the C1 discoverer and the preflight order
/// check read, not safewidth's own pixel instrumentation.
final class SpacerItem {
    static let identifier = "vz-spacer"

    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.setAccessibilityIdentifier(Self.identifier)
        rest()
    }

    func apply(_ command: SpacerCommand) {
        switch command {
        case .rest: rest()
        case .length(let pt): expand(to: pt)
        }
    }

    func state() -> [String: Any] {
        [
            "identifier": Self.identifier,
            "isVisible": statusItem.isVisible,
            "length": Double(statusItem.length),
            "resting": statusItem.length == NSStatusItem.variableLength,
        ]
    }

    private func rest() {
        statusItem.button?.image = Self.restImage
        statusItem.length = NSStatusItem.variableLength
    }

    private func expand(to pt: Double) {
        statusItem.button?.image = nil
        statusItem.length = CGFloat(pt)
    }

    /// A chevron glyph about the width of Ice's; a template image, so it is
    /// drawn in the bar's own tint and never matches a marker colour.
    private static let restImage: NSImage? = {
        let image = NSImage(systemSymbolName: "chevron.left.2", accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }()
}

final class Delegate: NSObject, NSApplicationDelegate {
    var items = [HelperItem]()
    var spacer: SpacerItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !config.spacer else {
            let item = SpacerItem()
            spacer = item
            reply("up", ["pid": Int(getpid()), "items": 1, "spacer": true])
            return
        }
        guard config.mimicNoDivider else {
            for (index, spec) in config.items.enumerated() {
                items.append(makePlainItem(index: index, spec: spec))
            }
            reply("up", ["pid": Int(getpid()), "items": items.count, "mimicNoDivider": false])
            return
        }
        for (index, spec) in config.items.enumerated() {
            items.append(makeNoDividerItem(index: index, spec: spec, target: self))
        }
        // One main-queue turn per state, as Ice's `$state` sink delivers.
        DispatchQueue.main.async {
            self.items.forEach(applyStandardLength)
            DispatchQueue.main.async {
                self.items.forEach(applyNoDivider)
                DispatchQueue.main.async {
                    reply("up", ["pid": Int(getpid()), "items": self.items.count, "mimicNoDivider": true])
                }
            }
        }
    }

    /// The button's action, as Ice wires it; nothing here ever clicks it.
    @objc func performAction() {}

    func setVisible(_ visible: Bool, index: Int?) {
        for item in items where index == nil || item.index == index {
            item.statusItem.isVisible = visible
        }
    }

    func reportFrames() {
        reply("frames", ["items": items.map { $0.state() }])
    }
}

let controllerExit = DispatchSource.makeProcessSource(identifier: controller, eventMask: .exit, queue: .main)
controllerExit.setEventHandler { exit(0) }
controllerExit.resume()
DispatchQueue.main.asyncAfter(deadline: .now() + config.lifetime) { exit(0) }

let application = NSApplication.shared
let delegate = Delegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)

let selfReadQueue = DispatchQueue(label: "vzhelper.selfread", qos: .userInitiated)

// The control channel: one command per line on stdin, buffered across
// partial reads. EOF is the same exit path as an explicit `quit` line.
/// Every stall so far: bounded, because each one delays every deadman.
var stalledTotal = 0.0
let stdinSource = DispatchSource.makeReadSource(fileDescriptor: FileHandle.standardInput.fileDescriptor, queue: .main)
var inputBuffer = Data()
stdinSource.setEventHandler {
    let chunk = FileHandle.standardInput.availableData
    guard !chunk.isEmpty else {
        exit(0) // EOF
    }
    inputBuffer.append(chunk)
    while let newline = inputBuffer.firstIndex(of: 0x0A) {
        let lineData = inputBuffer[inputBuffer.startIndex..<newline]
        inputBuffer.removeSubrange(inputBuffer.startIndex...newline)
        guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespaces), !line.isEmpty else {
            continue
        }
        let words = line.split(separator: " ").map(String.init)
        let index = words.count > 1 ? Int(words[1]) : nil
        switch words[0] {
        case "hide": delegate.setVisible(false, index: index)
        case "show": delegate.setVisible(true, index: index)
        case "frames": delegate.reportFrames()
        case "selfread":
            // Off the main thread on purpose: Ice must read its own dividers
            // from a background queue, and the main thread has to stay free
            // to answer the request.
            selfReadQueue.async {
                let result = selfRead()
                reply("selfread", result)
            }
        case "stall":
            // The main thread is what answers Accessibility, so sleeping it is
            // the stall. Bounded, because every deadman waits behind it.
            guard words.count > 1, let seconds = Double(words[1]), seconds > 0, seconds <= 30 else {
                reply("stall", ["error": "want 0 < seconds <= 30"])
                break
            }
            guard stalledTotal + seconds <= 60 else {
                reply("stall", ["error": "at most 60 s of stalls per helper"])
                break
            }
            stalledTotal += seconds
            reply("stalling", ["seconds": seconds])
            Thread.sleep(forTimeInterval: seconds)
            reply("resumed", ["seconds": seconds])
        case "length", "rest":
            // C1's spacer commands (I2, section 2), parsed once by
            // C1Core's own pure parser so the range check (0-1000, else
            // refused) lives in exactly one, fully tested place.
            guard config.spacer, let spacer = delegate.spacer else { break }
            switch SpacerCommandParser.parse(line) {
            case .success(let command):
                spacer.apply(command)
                reply("spacer", spacer.state())
            case .failure(let error):
                reply("refused", ["command": line, "reason": "\(error)"])
            }
        case "quit": exit(0)
        default: break
        }
    }
}
stdinSource.resume()

application.run()
