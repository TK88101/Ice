// I7: a synthesized fake bar for the orchestration test
// (`I7OrchestrationTests.swift`, `I7FaultTriggerTests.swift`). Shaped after,
// but not copied verbatim from, `Packages/MenuBarDiscovery/Tests/MenuBarDetectorFeedTests/TestBar.swift`
// and `Scenario.swift` (frozen test targets this one cannot import) --
// enough real drawing to give IceCore's own ink/template rules an actual
// glyph to accept and match, real Accessibility-shaped frames, and a real
// `DiscoveredItemSet`/`DiscoveryResult`, all driven from one small, lockable
// world model so the fake capturer, the fake AX readers and the fake
// discoverer always agree with each other.
//
// Rework #6a: the world now also carries a realistic owner population (one
// templated owner item plus, optionally, several the pixel baseline rejects
// -- overlapping AX frames, the same reason the owner's own bar rejects 2-6
// items every recorded preflight) and one *phase-armed* fault knob
// (`FaultKnob`, below) -- never a raw capture count (crosscheck #13-#16):
// every knob engages only once the spacer has received its Nth `length`
// command, which cannot happen before `step3Baseline` has already run.
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

/// One synthesized bar's single active fault, armed only once the phase
/// gate opens (`FakeBarWorld.arm(_:afterNthLength:)`) -- never by raw
/// capture count (Amendment v6 / crosscheck #13-#16). A test configures at
/// most one of these before `run()`.
enum FaultKnob {
    /// The templated owner item disappears (pixels, AX and discovery
    /// together). `returnsAfterCaptures`: `nil` models "stays gone through
    /// teardown" (scenario 4's escalation); a small number models "comes
    /// back before teardown" (scenario 3a's control case, proving the
    /// escalation itself -- not a first-time mismatch -- produced scenario
    /// 4's verdict).
    case vanishTemplatedOwner(returnsAfterCaptures: Int?)
    case vanishProtected
    /// `index` into the untemplated cluster (0..<untemplatedOwnerCount).
    case vanishExtra(index: Int)
    case shiftExtra(index: Int, byPt: Double)
    /// A chevron-width agent frame plus real ink appears once the spacer
    /// is back at rest -- "a fold appears while at rest," never during an
    /// expansion (gated on `spacerState == .rest`, so it cannot confuse
    /// the mid-expansion verifier read, which is expected to see no fold
    /// either way).
    case foldWithoutExpansion
    case captureFailure
    /// The discoverer blocks past `C1DiscoveryExecutor`'s own (real,
    /// 3.0 s) bound -- this world cannot inject a shorter one without a
    /// source seam outside the tests-only brief, so the test pays the real
    /// 3 s instead.
    case discoveryHang
    /// Also scenario 3i's own knob (a small, sub-`referenceTolerancePt`
    /// offset): see its own doc comment on why the *magnitude*, not a
    /// separate case, is what tells the two scenarios apart.
    case spacerStuckOffset(pt: Double)
}

/// A run's elapsed time, advanced only by what the real stage actually asks
/// for: an explicit `sleep`/`run`, or one of this world's own per-operation
/// latencies (`SimulatedLatency`) -- never by a bare `now()` read. Shared
/// between `FakePump` (which callers see as the clock) and this world
/// (which callers cannot see advancing it), so a scenario's own `clock.now()`
/// before and after `stage.run()` is the simulated wall time that run took.
final class VirtualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: Double = 1_000

    func advance(_ seconds: Double) {
        guard seconds > 0 else { return }
        lock.withLock { t += seconds }
    }

    func now() -> Double { lock.withLock { t } }
}

/// Per-operation latencies the world charges the virtual clock with, so a
/// run's simulated duration reflects the real number of captures/discovery
/// passes/AX reads the stage actually makes, not a guess. Sources named
/// where a number comes from measurement; the rest are conservative
/// estimates (flagged in the worker report, never presented as measured).
enum SimulatedLatency {
    /// `LiveStripCapturer.swift:14-16`'s own measurement (5-9 ms); the
    /// lower end, since this world's strip is far smaller than a real bar.
    static let captureSeconds = 0.006
    /// Not separately measured in the cited evidence -- a conservative
    /// estimate, the same order as a capture.
    static let axReadSeconds = 0.01
    /// `STATUS.md:20`'s measured median keyed-discovery pass (36.5 ms),
    /// rounded down slightly for a clean bar with few items to enumerate.
    static let discoverySeconds = 0.03
}

/// One synthesized bar: Target, the spacer, Protected, one templated owner
/// item and, optionally, a small cluster of *untemplated* owner items --
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
    /// The one owner item the pixel baseline accepts as a template.
    static let ownerX = 270.0
    /// Left of `ownerX` (Amendment v6: "at least one untemplated item LEFT
    /// of the leftmost templated one"), each 3 pt apart so every pair's AX
    /// frame (7 pt wide) overlaps its neighbour -- the same
    /// `overlapsAnotherItem` rejection the owner's own bar hits
    /// (`StripAssessor.baseline`, line ~136), never a shape the ink/template
    /// rules would simply fail to cut.
    static let extraBaseX = 250.0
    static let extraSpacingPt = 3.0
    /// Clear of everything else on the strip (Target's rest position is
    /// 150), for the "fold without expansion" knob's own chevron-width
    /// agent frame and ink.
    static let foldGhostX = 50.0
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

    /// Never a real third-party app name (the hard rule): neutral,
    /// numbered ids, like `ownerIdentifier` above.
    static func extraPID(_ i: Int) -> pid_t { pid_t(502 + i) }
    static func extraKey(_ i: Int) -> ItemKey { key("owner", pid: extraPID(i), identifier: "owner.b\(i)") }
    static func extraX(_ i: Int) -> Double { extraBaseX + Double(i) * extraSpacingPt }

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
    /// Reused for the untemplated cluster too: their shape is irrelevant
    /// (the baseline rejects them for overlapping, before any per-id ink
    /// cut is even attempted), only their AX frame and position matter.
    static let shapeOwner: [String] = [
        "........##", "........##", "........##", "##########", "##########",
        "##########", "##########", "##........", "##........", "##........",
    ]
    /// A solid block, wide enough to clear `foldClusterMinPx` (16 px) many
    /// times over -- the "fold without expansion" knob's own ink.
    static let shapeFoldGhost: [String] = Array(repeating: "##########", count: 10)

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

    /// Whether the templated owner item (`ownerKey`, `ownerX`) exists in
    /// this world at all -- `false` models the owner's own bar having no
    /// item the pixel baseline can template (scenario 1b).
    private let templatedOwnerPresent: Bool
    /// How many untemplated (baseline-rejected) owner items this world
    /// also carries, left of `ownerX` (0...4).
    let untemplatedOwnerCount: Int

    /// A run's virtual clock -- shared with the `FakePump` this world's
    /// environment is built with (`FakeC1EnvironmentFactory.make`), so
    /// `sleep`/`run` and this world's own per-operation latencies
    /// (`SimulatedLatency`) advance the same timeline.
    let clock = VirtualClock()

    /// Section 4's own trigger, engaged only by phase (never a raw capture
    /// count) -- see the fault-knob effect methods below.
    private var knob: FaultKnob?
    private var armAfterNthLength = 1
    private var lengthCommandsSeen = 0
    /// Captures since the phase gate opened -- only meaningful for a knob
    /// that "returns after N captures" (scenario 3a's control case).
    private var capturesSinceArmed = 0

    private var captureCount = 0

    init(templatedOwnerPresent: Bool = true, untemplatedOwnerCount: Int = 0) {
        precondition(untemplatedOwnerCount >= 0 && untemplatedOwnerCount <= 4, "the cluster must stay clear of Protected and the templated owner")
        self.templatedOwnerPresent = templatedOwnerPresent
        self.untemplatedOwnerCount = untemplatedOwnerCount
    }

    func setTargetNeverHides(_ value: Bool) {
        lock.withLock { targetNeverHides = value }
    }

    /// Arms `knob`, engaged once the spacer has received its `afterNthLength`-th
    /// `length` command -- e.g. `1` for "as soon as the first cycle
    /// expands" (most triggers), `2` for "only from the second cycle on"
    /// (the reset-check drift case, which needs the first cycle's own
    /// reset check to pass clean).
    func arm(_ knob: FaultKnob, afterNthLength: Int = 1) {
        lock.withLock {
            self.knob = knob
            self.armAfterNthLength = afterNthLength
        }
    }

    // MARK: - Phase gate (called only while holding `lock`)

    private func isArmedLocked() -> Bool {
        knob != nil && lengthCommandsSeen >= armAfterNthLength
    }

    // MARK: - Fault-knob effects (called only while holding `lock`)

    private func captureShouldFailLocked() -> Bool {
        guard isArmedLocked(), case .captureFailure = knob else { return false }
        return true
    }

    private func protectedVisibleLocked() -> Bool {
        guard protectedUp else { return false }
        guard isArmedLocked(), case .vanishProtected = knob else { return true }
        return false
    }

    private func templatedOwnerVisibleLocked() -> Bool {
        guard templatedOwnerPresent else { return false }
        guard isArmedLocked() else { return true }
        if case .vanishTemplatedOwner(let returns) = knob {
            if let returns { return capturesSinceArmed > returns }
            return false
        }
        return true
    }

    private func extraVisibleLocked(_ i: Int) -> Bool {
        guard isArmedLocked(), case .vanishExtra(let index) = knob, index == i else { return true }
        return false
    }

    private func extraXLocked(_ i: Int) -> Double {
        let base = Self.extraX(i)
        guard isArmedLocked(), case .shiftExtra(let index, let byPt) = knob, index == i else { return base }
        return base + byPt
    }

    /// The spacer's own rendered position: unaffected by expansion (I7
    /// never needs the exact real-world magnitude -- see `FakeSpacerState`),
    /// but offset while at rest once `.spacerStuckOffset` is armed --
    /// "the collapse was sent, but the spacer did not actually come back."
    /// Armed only after the first `length` command (Amendment v6 /
    /// crosscheck #15): the baseline, taken before any `length` is ever
    /// sent, records the *true* rest position, so only a rest *after* an
    /// expansion is offset -- never the rest baseline itself.
    ///
    /// The magnitude is what tells 3h and 3i apart, not a separate knob:
    /// `confirmRestSettled`'s own position check tolerates
    /// `referenceTolerancePt` (1 pt), but `performResetCheck`'s helper
    /// condition demands *exact* equality (section 5: "no stated tolerance
    /// for them"). A large offset (30 pt) fails the first check ->
    /// `restNotConfirmed` (3h). A small, sub-1-pt offset (0.5 pt) passes
    /// it -- rest is confirmed -- but is still nonzero, so the reset
    /// check's own exact-match condition fails it next ->
    /// `resetCheckFailed` (3i). A drift big enough to fail the reset
    /// check's *owner*-item 2 pt tolerance is necessarily also big enough
    /// to fail `assessLatch`'s own 1-pt-tolerance per-capture check first
    /// (it runs on every capture, including the reset check's own), so an
    /// *owner*-item drift cannot isolate `resetCheckFailed` from a latch
    /// trip -- only the helpers' own zero-tolerance condition can.
    private func spacerRenderXLocked() -> Double {
        guard spacerState == .rest, isArmedLocked(), case .spacerStuckOffset(let pt) = knob else { return Self.spacerX }
        return Self.spacerX + pt
    }

    /// Gated on `spacerState == .rest`, not merely "armed": the ghost
    /// exists only while at rest, matching the trigger's own name and
    /// keeping it from ever appearing during the mid-expansion verifier
    /// read (which tolerates no fold either way, so this would only ever
    /// have added noise there, never a meaningful assertion).
    private func foldGhostPresentLocked() -> Bool {
        guard spacerState == .rest, isArmedLocked(), case .foldWithoutExpansion = knob else { return false }
        return true
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
    /// commands change this world's state; every command is logged. Every
    /// `length` the spacer receives also advances the phase gate
    /// (`lengthCommandsSeen`) -- the one thing every fault knob arms on.
    func handleCommand(_ line: String, role: String) {
        lock.withLock {
            log.append("\(role).\(line)")
            guard role == "spacer" else { return }
            if line == "rest" {
                spacerState = .rest
            } else if line.hasPrefix("length "), let value = Double(line.dropFirst("length ".count)) {
                spacerState = .expanded(value)
                lengthCommandsSeen += 1
            }
        }
    }

    private func targetXLocked() -> Double {
        if targetNeverHides { return Self.targetRestX }
        switch spacerState {
        case .rest: return Self.targetRestX
        case .expanded: return Self.targetHiddenX
        }
    }

    // MARK: - Capture (pixels)

    /// `nil` models a failed capture (the "capture returns nil" knob) --
    /// itself an immediate abort in the real stage (`LatchingCapturer.
    /// capture()`), never merely "nothing drawn."
    func image() -> StripImage? {
        let (glyphs, shouldFail): ([(shape: [String], atPt: Double)], Bool) = lock.withLock {
            captureCount += 1
            if isArmedLocked() { capturesSinceArmed += 1 }
            if captureShouldFailLocked() { return ([], true) }
            var g: [(shape: [String], atPt: Double)] = []
            if targetUp { g.append((Self.shapeTarget, targetXLocked())) }
            if spacerUp { g.append((Self.shapeSpacer, spacerRenderXLocked())) }
            if protectedVisibleLocked() { g.append((Self.shapeProtected, Self.protectedX)) }
            if templatedOwnerVisibleLocked() { g.append((Self.shapeOwner, Self.ownerX)) }
            for i in 0..<untemplatedOwnerCount where extraVisibleLocked(i) {
                g.append((Self.shapeOwner, extraXLocked(i)))
            }
            if foldGhostPresentLocked() {
                g.append((Self.shapeFoldGhost, Self.foldGhostX))
            }
            return (g, false)
        }
        guard !shouldFail else { return nil }
        clock.advance(SimulatedLatency.captureSeconds)
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
        var agentFrames = [AgentFrame(minX: Self.indicatorX, minY: 0, width: Self.indicatorWidth)]
        if lock.withLock({ foldGhostPresentLocked() }) {
            agentFrames.append(AgentFrame(minX: Self.foldGhostX, minY: 0, width: 17.5))
        }
        clock.advance(SimulatedLatency.axReadSeconds)
        return MenuBarAXSnapshot(itemFrames: itemFrames, agentFrames: agentFrames)
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
        clock.advance(SimulatedLatency.discoverySeconds)
        return DiscoveryResult(
            set: set, duration: 0, origin: DiscoveryOrigin(x: 0, y: 0), bounds: Self.bounds,
            nextCursor: 0, quarantined: [], enumeratedPIDs: Set(entries.map { $0.entry.pid })
        )
    }

    /// Whether the discoverer should block past `C1DiscoveryExecutor`'s own
    /// (real, wall-clock) bound -- the "discovery timeout" knob, which no
    /// per-operation clock advance can model (the executor's own deadline
    /// is real time, not this world's virtual one).
    func shouldHangDiscovery() -> Bool {
        lock.withLock {
            guard isArmedLocked(), case .discoveryHang = knob else { return false }
            return true
        }
    }

    /// Every item currently "up," keyed by its encoded `ItemKey` -- the
    /// single source both `axSnapshot(items:)` and `discoveryResult()`
    /// build from, so pixels, AX and discovery can never disagree about
    /// who exists right now.
    private func liveEntries() -> [(id: String, entry: (key: ItemKey, pid: pid_t, frame: BarRect))] {
        lock.withLock {
            var result = [(id: String, entry: (key: ItemKey, pid: pid_t, frame: BarRect))]()
            if targetUp {
                result.append((Self.targetKey.encoded, (Self.targetKey, Self.targetPID, Self.frame(atPt: targetXLocked()))))
            }
            if spacerUp {
                result.append((Self.spacerKey.encoded, (Self.spacerKey, Self.spacerPID, Self.frame(atPt: spacerRenderXLocked()))))
            }
            if protectedVisibleLocked() {
                result.append((Self.protectedKey.encoded, (Self.protectedKey, Self.protectedPID, Self.frame(atPt: Self.protectedX))))
            }
            if templatedOwnerVisibleLocked() {
                result.append((Self.ownerKey.encoded, (Self.ownerKey, Self.ownerPID, Self.frame(atPt: Self.ownerX))))
            }
            for i in 0..<untemplatedOwnerCount where extraVisibleLocked(i) {
                let key = Self.extraKey(i)
                result.append((key.encoded, (key, Self.extraPID(i), Self.frame(atPt: extraXLocked(i)))))
            }
            return result
        }
    }
}
