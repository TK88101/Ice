// I7: a synthesized fake bar for the orchestration test
// (`I7OrchestrationTests.swift`). Shaped after, but not copied verbatim
// from, `Packages/MenuBarDiscovery/Tests/MenuBarDetectorFeedTests/TestBar.swift`
// and `Scenario.swift` (frozen test targets this one cannot import) --
// enough real drawing to give IceCore's own ink/template rules an actual
// glyph to accept and match, real Accessibility-shaped frames, and a real
// `DiscoveredItemSet`/`DiscoveryResult`, all driven from one small, lockable
// world model so the fake capturer, the fake AX readers and the fake
// discoverer always agree with each other.
import Darwin
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDiscovery

/// Whether the spacer is at rest or has been sent a `length <pt>` -- pushing
/// Target far enough left that it falls off the left edge of the rendered
/// strip (never drawn) without needing to model the real 600-896 pt band:
/// I7 only needs "expanded -> Target undrawn," not the exact real-world
/// magnitude, since `ScanPlanner`'s own arithmetic is already 100%-covered
/// pure logic (C1CoreTests).
enum FakeSpacerState: Equatable {
    case rest
    case expanded(Double)
}

/// One synthesized bar: Target, the spacer, Protected and one owner item,
/// each a fixed, asymmetric glyph shape so the ink/template rules can find
/// and tell them apart; the capture indicator lives only in the AX-only
/// extras scan, matching the real `detectIndicatorFrame()`'s own seam. All
/// state is behind one lock so the capturer/AX-reader/discoverer fakes,
/// called from different queues, always agree.
final class FakeBarWorld: @unchecked Sendable {
    static let widthPt = 320
    static let heightPt = 12
    static let scale = 2
    static let backdrop = RGBA(40, 40, 40)
    static let ink = RGBA(255, 255, 255)

    static var geometry: BarGeometry {
        BarGeometry(widthPt: Double(widthPt), heightPt: Double(heightPt), scale: Double(scale), notch: nil)
    }

    static let bounds = BarBounds(minX: 0, maxX: Double(widthPt), minY: 0, barHeight: Double(heightPt))

    // MARK: - Fixed layout (points)

    static let targetRestX = 150.0
    static let spacerX = 190.0
    static let protectedX = 230.0
    static let ownerX = 270.0
    /// Far enough off the left edge (`widthPt` starts at 0) that none of
    /// the glyph's pixels ever land inside the rendered strip -- "pushed
    /// into the undrawn band," not merely covered.
    static let targetHiddenX = -5000.0
    static let indicatorX = 300.0
    static let indicatorWidth = 20.0 // clear of chevronWidthPt (17.5) and pillWidthPt (16)

    // MARK: - Identity

    static let protectedPID: pid_t = 9001
    static let spacerPID: pid_t = 9002
    static let targetPID: pid_t = 9003
    static let ownerPID: pid_t = 501

    static let protectedIdentifier = "vz-reference"
    static let spacerIdentifier = "vz-spacer"
    static let targetIdentifier = "vz-target"
    static let ownerIdentifier = "owner.a"

    static func key(_ role: String, pid: pid_t, identifier: String) -> ItemKey {
        ItemKey(namespace: "com.fakebar.\(role)", identifier: identifier, pid: pid, childIndex: nil)
    }

    static let protectedKey = key("protected", pid: protectedPID, identifier: protectedIdentifier)
    static let spacerKey = key("spacer", pid: spacerPID, identifier: spacerIdentifier)
    static let targetKey = key("target", pid: targetPID, identifier: targetIdentifier)
    static let ownerKey = key("owner", pid: ownerPID, identifier: ownerIdentifier)

    // MARK: - Shapes (10 px wide at scale 2 = 5 pt -- clears minTemplateWidthPt)

    static let shapeTarget: [String] = [
        "##########", "##........", "##........", "##........", "##########",
        "##########", "........##", "........##", "........##", "##########",
    ]
    static let shapeSpacer: [String] = [
        "##########", "##......##", "##......##", "##......##", "##......##",
        "##......##", "##......##", "##......##", "##......##", "##########",
    ]
    static let shapeProtected: [String] = [
        "...##.....", "...##.....", "...##.....", "##########", "##########",
        "##########", "##########", "...##.....", "...##.....", "...##.....",
    ]
    /// Asymmetric and non-periodic horizontally (unlike a checkered pattern,
    /// which can self-match at a shifted offset and read `.ambiguous`) --
    /// the owner's own item, distinct from the three helper shapes above.
    static let shapeOwner: [String] = [
        "........##", "........##", "........##", "##########", "##########",
        "##########", "##########", "##........", "##........", "##........",
    ]

    private let lock = NSLock()
    private var spacerState: FakeSpacerState = .rest
    /// Scenario 2/5: Target stays at rest regardless of the spacer.
    private var targetNeverHides = false
    private var protectedUp = false
    private var spacerUp = false
    private var targetUp = false
    /// Every helper command this world has seen, in order -- what the I7
    /// scenarios that assert "rest before quit" read.
    private var log: [String] = []
    var commandLog: [String] { lock.withLock { log } }

    /// Scenario 3: after this many `image()` captures, the owner's own item
    /// stops existing at all (in the pixels, the AX read and discovery
    /// alike) -- a credible, permanent disappearance for the latch to catch.
    private var vanishOwnerAfterCaptures: Int?
    private var captureCount = 0

    /// Scenario 3b: once armed, the spacer's rendered position no longer
    /// returns to its own rest baseline after a `rest` command (it stays
    /// offset by this many points) -- "the collapse was sent, but the
    /// spacer did not actually come back," for `confirmRestSettled`'s
    /// position-tolerance check (item 1) to catch.
    private var spacerStuckOffsetPt: Double?

    func setTargetNeverHides(_ value: Bool) {
        lock.withLock { targetNeverHides = value }
    }

    func setVanishOwnerAfterCaptures(_ n: Int) {
        lock.withLock { vanishOwnerAfterCaptures = n }
    }

    func setSpacerStuckOffsetPt(_ pt: Double) {
        lock.withLock { spacerStuckOffsetPt = pt }
    }

    private func ownerIsGone() -> Bool {
        guard let threshold = vanishOwnerAfterCaptures else { return false }
        return captureCount > threshold
    }

    private func spacerRenderX() -> Double {
        guard let offset = spacerStuckOffsetPt, spacerState == .rest else { return Self.spacerX }
        return Self.spacerX + offset
    }

    func setUp(_ role: String) {
        lock.withLock {
            switch role {
            case "protected": protectedUp = true
            case "spacer": spacerUp = true
            case "target": targetUp = true
            default: break
            }
        }
    }

    func setDown(_ role: String) {
        lock.withLock {
            log.append("\(role).quit")
            switch role {
            case "protected": protectedUp = false
            case "spacer": spacerUp = false
            case "target": targetUp = false
            default: break
            }
        }
    }

    /// A helper's own `send(_:)` -- only the spacer's `length <pt>`/`rest`
    /// commands change this world's state; every command is logged.
    func handleCommand(_ line: String, role: String) {
        lock.withLock {
            log.append("\(role).\(line)")
            guard role == "spacer" else { return }
            if line == "rest" {
                spacerState = .rest
            } else if line.hasPrefix("length "), let value = Double(line.dropFirst("length ".count)) {
                spacerState = .expanded(value)
            }
        }
    }

    private func targetX() -> Double {
        if targetNeverHides { return Self.targetRestX }
        switch spacerState {
        case .rest: return Self.targetRestX
        case .expanded: return Self.targetHiddenX
        }
    }

    // MARK: - Capture (pixels)

    func image() -> StripImage {
        var glyphs: [(shape: [String], atPt: Double)] = []
        let (targetUp, spacerUp, protectedUp, ownerGone) = lock.withLock {
            captureCount += 1
            return (self.targetUp, self.spacerUp, self.protectedUp, self.ownerIsGone())
        }
        if targetUp { glyphs.append((Self.shapeTarget, targetX())) }
        if spacerUp { glyphs.append((Self.shapeSpacer, spacerRenderX())) }
        if protectedUp { glyphs.append((Self.shapeProtected, Self.protectedX)) }
        if !ownerGone { glyphs.append((Self.shapeOwner, Self.ownerX)) }
        return Self.render(glyphs)
    }

    private static func render(_ glyphs: [(shape: [String], atPt: Double)]) -> StripImage {
        let widthPx = widthPt * scale
        let heightPx = heightPt * scale
        var bytes = [UInt8](repeating: 0, count: widthPx * heightPx * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = backdrop.r
            bytes[i + 1] = backdrop.g
            bytes[i + 2] = backdrop.b
            bytes[i + 3] = 255
        }
        for (shape, xPt) in glyphs {
            let x0 = Int((xPt * Double(scale)).rounded())
            let y0 = (heightPx - shape.count) / 2
            for (dy, row) in shape.enumerated() {
                for (dx, char) in row.enumerated() where char == "#" {
                    let x = x0 + dx
                    let y = y0 + dy
                    guard x >= 0, x < widthPx, y >= 0, y < heightPx else { continue }
                    let i = (y * widthPx + x) * 4
                    bytes[i] = ink.r
                    bytes[i + 1] = ink.g
                    bytes[i + 2] = ink.b
                    bytes[i + 3] = 255
                }
            }
        }
        return StripImage(width: widthPx, height: heightPx, scale: Double(scale), bytes: bytes)
    }

    /// The trimmed (detector-facing) AX frame a glyph at `atPt` reads at --
    /// one point narrower than its own ink on each side, the same
    /// convention `TestBar.frame` uses.
    private static func frame(atPt xPt: Double, width: Double = 7) -> BarRect {
        BarRect(minX: xPt - 1, minY: 0, width: width, height: Double(heightPt))
    }

    // MARK: - Accessibility (AX reads and discovery)

    /// `items` maps a caller-chosen id to the pid that owns it (`MenuBarAXReading`'s
    /// own contract) -- only a requested id whose live pid actually matches
    /// gets a frame back; everything else is simply absent from
    /// `itemFrames`, never a read failure.
    func axSnapshot(items: [String: pid_t]) -> MenuBarAXSnapshot {
        let live = Dictionary(uniqueKeysWithValues: liveEntries().map { ($0.id, $0.entry) })
        var itemFrames = [String: ItemFrame]()
        for (id, pid) in items {
            guard let entry = live[id], entry.pid == pid else { continue }
            itemFrames[id] = ItemFrame(id: id, minX: entry.frame.minX, minY: entry.frame.minY, width: entry.frame.width, height: entry.frame.height)
        }
        return MenuBarAXSnapshot(itemFrames: itemFrames, agentFrames: [AgentFrame(minX: Self.indicatorX, minY: 0, width: Self.indicatorWidth)])
    }

    func discoveryResult() -> DiscoveryResult {
        let entries = liveEntries()
        let items = entries.map { id, entry in
            DiscoveredItem(
                key: entry.key, basis: .declared,
                process: ProcessInfoRecord(pid: entry.pid, bundleID: entry.key.namespace, localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
                frame: entry.frame, position: .onBar,
                title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
            )
        }
        let set = DiscoveredItemSet(
            items: items, visibleControlItem: nil, hiddenDivider: nil, alwaysHiddenDivider: nil,
            ownRead: .ok, systemElements: [], dropped: [], staleProcesses: [:], completeness: .complete
        )
        return DiscoveryResult(
            set: set, duration: 0, origin: DiscoveryOrigin(x: 0, y: 0), bounds: Self.bounds,
            nextCursor: 0, quarantined: [], enumeratedPIDs: Set(entries.map { $0.entry.pid })
        )
    }

    /// Every item currently "up," keyed by its encoded `ItemKey` -- the
    /// single source both `axSnapshot(items:)` and `discoveryResult()`
    /// build from, so pixels, AX and discovery can never disagree about
    /// who exists right now.
    private func liveEntries() -> [(id: String, entry: (key: ItemKey, pid: pid_t, frame: BarRect))] {
        lock.withLock {
            var result = [(id: String, entry: (key: ItemKey, pid: pid_t, frame: BarRect))]()
            if targetUp {
                result.append((Self.targetKey.encoded, (Self.targetKey, Self.targetPID, Self.frame(atPt: targetX()))))
            }
            if spacerUp {
                result.append((Self.spacerKey.encoded, (Self.spacerKey, Self.spacerPID, Self.frame(atPt: spacerRenderX()))))
            }
            if protectedUp {
                result.append((Self.protectedKey.encoded, (Self.protectedKey, Self.protectedPID, Self.frame(atPt: Self.protectedX))))
            }
            if !ownerIsGone() {
                result.append((Self.ownerKey.encoded, (Self.ownerKey, Self.ownerPID, Self.frame(atPt: Self.ownerX))))
            }
            return result
        }
    }
}
