// T0: a simulated bar for the spike stage, after `IceBarStageTests/FakeWorld`
// (helpers pack right to left, the spacer pushes the members left, a member
// left of `hiddenEdgePt` is not drawn, `«` appears when members overflow at
// rest); plus what spike B needs: a member whose menu "opens" on a press,
// reported the way vzhelper reports it, and listed as a pop-up menu window.
import C2Core
import Darwin
import IceBarOracle
import IceBarRunCore
import IceBarStage
import IceCore
import MenuBarCapture
import SpikeCore
import SpikeStage
import VZGlyphs

enum PressBehaviour {
    case always
    case onlyWhenDrawn
    case never
}

final class SpikeFakeWorld {
    static let geometry = BarGeometry(widthPt: 400, heightPt: 24, scale: 2, notch: PtSpan(lo: 100, hi: 160))
    static let rightEdgePt = 360.0
    static let itemWidthPt = 12.0
    static let gapPt = 2.0
    static let agentFrames = [AgentFrame(minX: 370, minY: 0, width: 12), AgentFrame(minX: 386, minY: 0, width: 8)]
    static let chevronFrame = AgentFrame(minX: 176, minY: 0, width: 17.5)

    let templates: StageTemplates
    var hiddenEdgePt = 172.0
    var newestRightmost = false
    var spacerPushes = true
    var chevronWhenRestBelowPt = 172.0
    var pressBehaviour = PressBehaviour.always

    private(set) var now = 0.0
    private(set) var captures = 0
    private(set) var items = [(id: String, pid: pid_t, role: String, menu: Bool)]()
    private(set) var spacerLength: Double?
    private(set) var menuOpenPID: pid_t?
    private(set) var presses = 0
    private(set) var commands = [String]()
    private var pendingReplies = [pid_t: [[String: Any]]]()
    private var nextPID: pid_t = 1000

    init(templates: StageTemplates) {
        self.templates = templates
    }

    func layout() -> [String: Double] {
        var cursor = Self.rightEdgePt
        var minX = [String: Double]()
        for item in newestRightmost ? items.reversed() : items {
            let pushed = spacerPushes ? spacerLength : nil
            let width = item.role == "spacer" ? max(Self.itemWidthPt, pushed ?? Self.itemWidthPt) : Self.itemWidthPt
            minX[item.id] = cursor - width
            cursor -= width + Self.gapPt
        }
        return minX
    }

    func restLayout() -> [String: Double] {
        let pushed = spacerLength
        spacerLength = nil
        defer { spacerLength = pushed }
        return layout()
    }

    func isHidden(_ id: String, _ layout: [String: Double]) -> Bool {
        guard let item = items.first(where: { $0.id == id }), item.role == "member", let x = layout[id] else { return false }
        return x < hiddenEdgePt
    }

    var chevronShown: Bool {
        let rest = restLayout()
        return items.contains { $0.role == "member" && (rest[$0.id] ?? .infinity) < chevronWhenRestBelowPt }
    }

    func capture() -> StripImage {
        captures += 1
        now += 0.02
        let g = Self.geometry
        let width = g.widthPx
        let height = g.heightPx
        // The backdrop in one fill; only the notch and the stamps are painted after.
        var bytes = [UInt8](unsafeUninitializedCapacity: width * height * 4) { buffer, count in
            for i in 0..<(width * height) { (buffer[i * 4], buffer[i * 4 + 1], buffer[i * 4 + 2], buffer[i * 4 + 3]) = (40, 40, 40, 255) }
            count = width * height * 4
        }
        func set(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let i = (y * width + x) * 4
            bytes[i] = c.0
            bytes[i + 1] = c.1
            bytes[i + 2] = c.2
        }
        let notch = OracleGeometry.notchColumns(g.notch!, scale: g.scale)
        for y in 0..<height { for x in notch { set(x, y, (0, 0, 0)) } }
        func stamp(_ t: OracleTemplate, atPt x: Double) {
            let x0 = Int(x * g.scale)
            let y0 = (height - t.height) / 2
            for y in 0..<t.height { for x in 0..<t.width where t.alpha[y * t.width + x] >= 128 { set(x0 + x, y0 + y, (255, 255, 255)) } }
        }
        let layout = layout()
        for item in items where item.role != "spacer" && !isHidden(item.id, layout) {
            guard let t = templates.helpers[item.id], let x = layout[item.id] else { continue }
            stamp(t, atPt: x)
        }
        if chevronShown, let chevron = templates.chevron { stamp(chevron, atPt: Self.chevronFrame.minX) }
        return StripImage(width: width, height: height, scale: g.scale, bytes: bytes)
    }

    func read(items ids: [String: pid_t]) -> MenuBarAXSnapshot {
        let layout = layout()
        var frames = [String: ItemFrame]()
        for (id, pid) in ids {
            guard items.contains(where: { $0.id == id && $0.pid == pid }), let x = layout[id] else { continue }
            frames[id] = ItemFrame(id: id, minX: x, minY: 0, width: Self.itemWidthPt, height: 24)
        }
        var agents = Self.agentFrames
        if chevronShown { agents.append(Self.chevronFrame) }
        return MenuBarAXSnapshot(itemFrames: frames, agentFrames: agents)
    }

    func windows(owners: Set<Int32>) -> [WindowEntry] {
        let layout = layout()
        var entries = [WindowEntry]()
        for item in items where item.role != "spacer" && owners.contains(item.pid) {
            entries.append(WindowEntry(pid: item.pid, layer: StatusWindows.statusLayer,
                                       bounds: WindowBounds(x: layout[item.id] ?? -500, y: 0, width: Self.itemWidthPt, height: 24)))
            if menuOpenPID == item.pid {
                entries.append(WindowEntry(pid: item.pid, layer: SpikeBRules.popUpMenuWindowLayer, bounds: WindowBounds(x: 150, y: 24, width: 80, height: 40)))
            }
        }
        return entries
    }

    // MARK: - Helpers

    func launch(arguments: [String]) -> SpikeFakeHelper {
        nextPID += 1
        let id: String
        let role: String
        if arguments.contains("spacer") {
            (id, role) = ("spacer", "spacer")
        } else {
            let glyph = arguments[arguments.firstIndex(of: "--glyphs")! + 1]
            (id, role) = (glyph, Roster.visibleGlyphs.contains(glyph) ? "visible" : "member")
        }
        items.append((id, nextPID, role, arguments.contains(SpikeHelperFlags.menu)))
        return SpikeFakeHelper(world: self, pid: nextPID)
    }

    func quit(_ pid: pid_t) {
        items.removeAll { $0.pid == pid }
        if menuOpenPID == pid { menuOpenPID = nil }
    }

    func isRunning(_ pid: pid_t) -> Bool { items.contains { $0.pid == pid } }

    func send(_ line: String, from pid: pid_t) {
        commands.append(line)
        if items.contains(where: { $0.pid == pid && $0.role == "spacer" }) {
            let words = line.split(separator: " ")
            if words.first == "rest" { spacerLength = nil }
            if words.first == "length", words.count == 2 { spacerLength = Double(words[1]) }
        }
        if line == SpikeHelperFlags.closeMenu, menuOpenPID == pid {
            menuOpenPID = nil
            pendingReplies[pid, default: []].append(["event": "close"])
        }
    }

    func reply(for pid: pid_t) -> [String: Any]? {
        guard var queue = pendingReplies[pid], !queue.isEmpty else { return nil }
        let first = queue.removeFirst()
        pendingReplies[pid] = queue
        return first
    }

    /// The press "arrives" at the helper: its menu opens per `pressBehaviour`.
    func press(pid: pid_t) {
        presses += 1
        guard let item = items.first(where: { $0.pid == pid }), item.menu else { return }
        let drawn = !isHidden(item.id, layout())
        let opens: Bool
        switch pressBehaviour {
        case .always: opens = true
        case .onlyWhenDrawn: opens = drawn
        case .never: opens = false
        }
        guard opens else { return }
        menuOpenPID = pid
        pendingReplies[pid, default: []].append(["event": "open"])
    }

    func sleep(until time: Double) { now = max(now, time) }

    var owners: [BarOwner] {
        [BarOwner(bundleID: "com.apple.controlcenter", pid: 90)] + items.map { BarOwner(bundleID: $0.role == "member" ? "com.icespike4.target" : "com.icespike4.protected", pid: $0.pid) }
    }
}

final class SpikeFakeHelper: IceBarHelper, SpikeReplyReading {
    let world: SpikeFakeWorld
    let pid: pid_t

    init(world: SpikeFakeWorld, pid: pid_t) {
        self.world = world
        self.pid = pid
    }

    var isRunning: Bool { world.isRunning(pid) }
    func send(_ line: String) { world.send(line, from: pid) }
    func awaitUp(timeout: Double) -> Bool { true }
    func quit(timeout: Double) { world.quit(pid) }
    func awaitReply(_ kind: String, timeout: Double) -> [String: Any]? {
        guard kind == SpikeHelperFlags.menuReply else { return nil }
        world.sleep(until: world.now + 0.01)
        return world.reply(for: pid)
    }
}

struct SpikeFakeCapturer: StripCapturing, @unchecked Sendable {
    let world: SpikeFakeWorld
    func capture() -> StripImage? { world.capture() }
}

struct SpikeFakeReader: MenuBarAXReading, @unchecked Sendable {
    let world: SpikeFakeWorld
    func read(items: [String: pid_t]) -> MenuBarAXSnapshot? { world.read(items: items) }
}

struct SpikeFakeSeams: IceBarWindowListing, IceBarHelperLaunching, IceBarClock, IceBarMenus {
    let world: SpikeFakeWorld
    func windows(owners: Set<Int32>) -> [WindowEntry] { world.windows(owners: owners) }
    func launch(app: String, bundleID: String, arguments: [String]) -> IceBarHelper? { world.launch(arguments: arguments) }
    func now() -> Double { world.now }
    func sleep(until time: Double) { world.sleep(until: time) }
    func launchAndCalibrate(_ width: C2MenuWidth) -> String? { nil }
    func stillInPlace() -> Bool { true }
    func quit() {}
}

final class SpikeFakePress: SpikePressing {
    let world: SpikeFakeWorld
    private var result: (error: Int, seconds: Double)?

    init(world: SpikeFakeWorld) {
        self.world = world
    }

    func beginPress(pid: pid_t, identifier: String) {
        world.press(pid: pid)
        result = (0, 0.1)
    }

    func pressResult() -> (error: Int, seconds: Double)? { result }
}

final class SpikeFakeEvidence: IceBarEvidence {
    private(set) var kinds = [String]()
    private(set) var log = [String]()
    private(set) var kept = [String]()
    func record(_ kind: String, _ fields: [String: Any]) {
        kinds.append(kind)
        if kind != "bracket" { log.append("\(kind) \(fields)") }
    }
    func keep(_ image: StripImage, label: String) { kept.append(label) }
}

enum SpikeFake {
    static let glyphOrder = Glyph.allCases.map(\.rawValue)

    static let templates: StageTemplates = {
        var helpers = [String: OracleTemplate]()
        for glyph in Glyph.allCases {
            let coverage = try! GlyphRenderer.coverage(glyph, scale: 2)
            helpers[glyph.rawValue] = OracleTemplate(id: glyph.rawValue, width: coverage.sidePx, height: coverage.sidePx, alpha: coverage.alpha, scale: 2)
        }
        return StageTemplates(helpers: helpers, chevron: chevron)
    }()

    /// Two left-pointing chevrons, 2 px strokes, 30 x 24 px (as `IceBarStageTests`).
    static let chevron: OracleTemplate = {
        let width = 30
        let height = 24
        var alpha = [UInt8](repeating: 0, count: width * height)
        for x0 in [4, 16] {
            for d in 0..<8 {
                for t in 0..<2 {
                    alpha[(12 - d) * width + x0 + d + t] = 255
                    alpha[(11 + d) * width + x0 + d + t] = 255
                }
            }
        }
        return OracleTemplate(id: ChevronTemplate.id, width: width, height: height, alpha: alpha, scale: 2)
    }()

    static func environment(_ world: SpikeFakeWorld, evidence: SpikeFakeEvidence) -> IceBarEnvironment {
        let seams = SpikeFakeSeams(world: world)
        return IceBarEnvironment(capturer: SpikeFakeCapturer(world: world), axReader: SpikeFakeReader(world: world), windows: seams,
                                 launcher: seams, menus: seams, clock: seams, evidence: evidence, geometry: SpikeFakeWorld.geometry,
                                 barOwners: { world.owners }, forgetDomain: { _ in true }, domainKeys: { _ in [] })
    }

    /// Lengths 16, 48, ..., 176 on the fake bar: a member is pushed off above 132 pt.
    static func plan(members: [Int] = [1], menus: [C2MenuWidth] = [.short], runB: Bool = true) -> SpikeStagePlan {
        SpikeStagePlan(profiles: SpikeAPlan.profiles(members: members, menus: menus), lengths: SpikeLengths(from: 16, through: 176, step: 32)!,
                       runB: runB, glyphOrder: glyphOrder, helperLifetimeSeconds: 900)
    }

    static func stage(_ world: SpikeFakeWorld, plan: SpikeStagePlan, evidence: SpikeFakeEvidence = SpikeFakeEvidence()) -> SpikeStage {
        SpikeStage(environment: environment(world, evidence: evidence), templates: templates, plan: plan, press: SpikeFakePress(world: world))
    }
}
