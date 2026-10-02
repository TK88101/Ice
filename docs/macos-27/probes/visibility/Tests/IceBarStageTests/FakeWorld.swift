// A simulated bar for the step's integration tests (docs/plans/2026-10-03-
// icebar-c-runner.md, T7): helpers pack right to left from the agent items,
// the spacer pushes the members left, a member left of `hiddenEdgePt` is
// pushed off (not drawn, window off-screen), and `«` appears when the members
// at rest overflow. Pixels are drawn from the oracle's own templates, so the
// real oracle, the frozen assessor and the claim run unchanged on them. A
// virtual clock makes every wait instant. Faults are injected by capture index.
import C2Core
import Darwin
import IceBarOracle
import IceBarRunCore
@testable import IceBarStage
import IceCore
import MenuBarCapture

enum Fault: Equatable {
    case windowMissing(String)
    /// The second helper's window overlaps the first's by `amount` pt on x (fully on y).
    case windowOverlap(String, String, Double)
    /// `«` listed by AX in the read that follows this capture, not drawn.
    case chevronOnlyInAX
    /// The member is not drawn in this capture (it still has its frame).
    case memberUndrawn(String)
}

final class FakeWorld {
    static let geometry = BarGeometry(widthPt: 400, heightPt: 24, scale: 2, notch: PtSpan(lo: 100, hi: 160))
    static let rightEdgePt = 360.0
    static let itemWidthPt = 12.0
    static let gapPt = 2.0
    static let agentFrames = [AgentFrame(minX: 370, minY: 0, width: 12), AgentFrame(minX: 386, minY: 0, width: 8)]
    static let chevronFrame = AgentFrame(minX: 176, minY: 0, width: 17.5)

    let templates: StageTemplates
    var backdrop: (UInt8, UInt8, UInt8) = (40, 40, 40)
    /// A member left of this edge is pushed off: not drawn.
    var hiddenEdgePt = 172.0
    /// A bar that puts each new item right of the others (the placement gate's failure).
    var newestRightmost = false
    /// The spacer moves nothing (a bar with no room: the members stay where they are).
    var spacerPushes = true
    /// Members whose rest position is left of this edge overflow and raise `«`.
    var chevronWhenRestBelowPt = 172.0
    var faults: [Int: Fault] = [:]

    private(set) var now = 0.0
    private(set) var captures = 0
    private(set) var items = [(id: String, pid: pid_t, role: String, coloured: Bool)]()
    private(set) var spacerLength: Double?
    private var nextPID: pid_t = 1000
    private var readFault: Fault?

    init(templates: StageTemplates) {
        self.templates = templates
    }

    // MARK: - The bar

    /// Items oldest first; each new one sits left of the previous ones.
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
        let fault = faults[captures]
        captures += 1
        now += 0.02
        if fault == .chevronOnlyInAX { readFault = fault }
        let g = Self.geometry
        let width = g.widthPx
        let height = g.heightPx
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        func set(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let i = (y * width + x) * 4
            bytes[i] = c.0
            bytes[i + 1] = c.1
            bytes[i + 2] = c.2
        }
        for y in 0..<height { for x in 0..<width { set(x, y, backdrop) } }
        let notch = OracleGeometry.notchColumns(g.notch!, scale: g.scale)
        for y in 0..<height { for x in notch { set(x, y, (0, 0, 0)) } }
        func stamp(_ t: OracleTemplate, atPt x: Double, ink: (UInt8, UInt8, UInt8)) {
            let x0 = Int(x * g.scale)
            let y0 = (height - t.height) / 2
            for y in 0..<t.height { for x in 0..<t.width where t.alpha[y * t.width + x] >= 128 { set(x0 + x, y0 + y, ink) } }
        }
        let layout = layout()
        for item in items where item.role != "spacer" && !isHidden(item.id, layout) {
            if fault == .memberUndrawn(item.id) { continue }
            guard let t = templates.helpers[item.id], let x = layout[item.id] else { continue }
            stamp(t, atPt: x, ink: item.coloured ? (255, 0, 0) : (255, 255, 255))
        }
        if chevronShown, let chevron = templates.chevron { stamp(chevron, atPt: Self.chevronFrame.minX, ink: (255, 255, 255)) }
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
        if chevronShown || readFault == .chevronOnlyInAX { agents.append(Self.chevronFrame) }
        readFault = nil
        return MenuBarAXSnapshot(itemFrames: frames, agentFrames: agents)
    }

    func windows(owners: Set<Int32>) -> [WindowEntry] {
        let fault = faults[captures - 1]
        let layout = layout()
        var entries = [WindowEntry]()
        for item in items where item.role != "spacer" && owners.contains(item.pid) {
            if fault == .windowMissing(item.id) { continue }
            // A pushed-off item keeps its own (off-region) position, distinct from the others'.
            var x = layout[item.id] ?? -500
            if case .windowOverlap(let a, let b, let amount) = fault, item.id == b, let ax = layout[a] { x = ax + Self.itemWidthPt - amount }
            entries.append(WindowEntry(pid: item.pid, layer: StatusWindows.statusLayer, bounds: WindowBounds(x: x, y: 0, width: Self.itemWidthPt, height: 24)))
        }
        return entries
    }

    // MARK: - Helpers

    func launch(arguments: [String]) -> FakeHelper {
        nextPID += 1
        let id: String
        let role: String
        if arguments.contains("spacer") {
            (id, role) = ("spacer", "spacer")
        } else {
            let glyph = arguments[arguments.firstIndex(of: "--glyphs")! + 1]
            (id, role) = (glyph, Roster.visibleGlyphs.contains(glyph) ? "visible" : "member")
        }
        items.append((id, nextPID, role, arguments.contains("--coloured")))
        return FakeHelper(world: self, pid: nextPID)
    }

    func quit(_ pid: pid_t) { items.removeAll { $0.pid == pid } }
    func isRunning(_ pid: pid_t) -> Bool { items.contains { $0.pid == pid } }

    func send(_ line: String, from pid: pid_t) {
        guard items.contains(where: { $0.pid == pid && $0.role == "spacer" }) else { return }
        let words = line.split(separator: " ")
        if words.first == "rest" { spacerLength = nil }
        if words.first == "length", words.count == 2 { spacerLength = Double(words[1]) }
    }

    func sleep(until time: Double) { now = max(now, time) }

    var owners: [BarOwner] {
        [BarOwner(bundleID: "com.apple.controlcenter", pid: 90)] + items.map { BarOwner(bundleID: $0.role == "member" ? "com.icespike4.target" : "com.icespike4.protected", pid: $0.pid) }
    }
}

final class FakeHelper: IceBarHelper {
    let world: FakeWorld
    let pid: pid_t

    init(world: FakeWorld, pid: pid_t) {
        self.world = world
        self.pid = pid
    }

    var isRunning: Bool { world.isRunning(pid) }
    func send(_ line: String) { world.send(line, from: pid) }
    func awaitUp(timeout: Double) -> Bool { true }
    func quit(timeout: Double) { world.quit(pid) }
}

struct FakeCapturer: StripCapturing, @unchecked Sendable {
    let world: FakeWorld
    func capture() -> StripImage? { world.capture() }
}

struct FakeReader: MenuBarAXReading, @unchecked Sendable {
    let world: FakeWorld
    func read(items: [String: pid_t]) -> MenuBarAXSnapshot? { world.read(items: items) }
}

struct FakeSeams: IceBarWindowListing, IceBarHelperLaunching, IceBarClock, IceBarMenus {
    let world: FakeWorld
    func windows(owners: Set<Int32>) -> [WindowEntry] { world.windows(owners: owners) }
    func launch(app: String, bundleID: String, arguments: [String]) -> IceBarHelper? { world.launch(arguments: arguments) }
    func now() -> Double { world.now }
    func sleep(until time: Double) { world.sleep(until: time) }
    func launchAndCalibrate(_ width: C2MenuWidth) -> String? { nil }
    func stillInPlace() -> Bool { true }
    func quit() {}
}

final class FakeEvidence: IceBarEvidence {
    private(set) var kinds = [String]()
    private(set) var log = [String]()
    private(set) var kept = 0
    func record(_ kind: String, _ fields: [String: Any]) {
        kinds.append(kind)
        if kind != "sample" { log.append("\(kind) \(fields)") }
    }
    func keep(_ image: StripImage, label: String) { kept += 1 }
}

enum Fake {
    static func environment(_ world: FakeWorld, evidence: FakeEvidence = FakeEvidence()) -> IceBarEnvironment {
        let seams = FakeSeams(world: world)
        return IceBarEnvironment(capturer: FakeCapturer(world: world), axReader: FakeReader(world: world), windows: seams,
                                 launcher: seams, menus: seams, clock: seams, evidence: evidence, geometry: FakeWorld.geometry,
                                 barOwners: { world.owners }, forgetDomain: { _ in true }, domainKeys: { _ in [] })
    }

    static func plan(_ kind: StepKind, members: Int = 2) -> StepPlan {
        StepPlan(kind: kind, members: members, menu: .short, glyphOrder: StageFixtures.glyphOrder, helperLifetimeSeconds: 900)
    }
}
