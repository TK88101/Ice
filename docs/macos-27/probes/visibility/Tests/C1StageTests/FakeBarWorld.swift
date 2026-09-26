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
//
// Rework #8: split into `FakeBarWorldSupport.swift` (the spacer state,
// `FaultKnob`, the virtual clock/latency model) and
// `FakeBarWorldLayout.swift` (every fixed position, identity and glyph
// shape) to stay under the 800-line cap -- this file keeps the world's own
// state, command handling, and its capture/Accessibility/discovery reads.
import C1Core
import C1Stage
import Darwin
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDiscovery

/// One synthesized bar: Target, the spacer, Protected, one templated owner
/// item and, optionally, a small cluster of *untemplated* owner items --
/// each a fixed, asymmetric glyph shape so the ink/template rules can find
/// and tell them apart; the capture indicator lives only in the AX-only
/// extras scan, matching the real `detectIndicatorFrame()`'s own seam. All
/// state is behind one lock so the capturer/AX-reader/discoverer fakes,
/// called from different queues, always agree.
final class FakeBarWorld: @unchecked Sendable {
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

    /// Amendment v8a: this world's own model of the macOS preferences
    /// system -- bundle id -> key -> value -- written/read only through
    /// `defaultsWrite`/`defaultsForget`/`defaultsKeys` (`FakeHelperDefaults`'s
    /// own forwarding target), so pixels/AX/discovery and "what got
    /// written to defaults" can never disagree about what actually
    /// happened, the same single-lock guarantee `liveEntries()`'s own doc
    /// comment describes for everything else.
    private var defaultsDomains: [String: [String: Double]] = [:]
    /// Every `write`/`forget` call this world's own `FakeHelperDefaults`
    /// seam has recorded, in order -- "the fake defaults store records
    /// every write/forget" (Amendment v8's own placement-by-preferred-
    /// position bullet).
    private var defaultsCallLog: [String] = []
    var defaultsLog: [String] { lock.withLock { defaultsCallLog } }

    @discardableResult
    func defaultsForget(_ bundleID: String) -> Bool {
        lock.withLock {
            defaultsDomains[bundleID] = [:]
            defaultsCallLog.append("forget \(bundleID)")
        }
        return true
    }

    func defaultsKeys(_ bundleID: String) -> [String]? {
        lock.withLock { (defaultsDomains[bundleID] ?? [:]).keys.sorted() }
    }

    @discardableResult
    func defaultsWrite(_ bundleID: String, key: String, value: Double) -> Bool {
        lock.withLock {
            defaultsDomains[bundleID, default: [:]][key] = value
            defaultsCallLog.append("write \(bundleID) \(key) \(value)")
        }
        return true
    }

    /// Amendment v8a: the honoured-position read -- `nil` (use `fallback`)
    /// unless `honoursPreferredPosition` is `true` and this exact
    /// `bundleID`/`autosaveName` pair already has a written value, in
    /// which case the render X is the inverse of `PlacementPlan`'s own
    /// `barRightEdge - minX` conversion (the INFERRED right-edge-distance
    /// assumption, SEAM-AUDIT.md). Called only while holding `lock`.
    private func resolvedXLocked(bundleID: String, autosaveName: String, fallback: Double) -> Double {
        guard honoursPreferredPosition,
              let value = defaultsDomains[bundleID]?[PreferredPositionKey.stringKey(autosaveName: autosaveName)]
        else { return fallback }
        return Self.geometry.widthPt - value
    }

    /// Whether the templated owner item (`ownerKey`, `ownerX`) exists in
    /// this world at all -- `false` models the owner's own bar having no
    /// item the pixel baseline can template (scenario 1b).
    private let templatedOwnerPresent: Bool
    /// How many untemplated (baseline-rejected) owner items this world
    /// also carries, left of `ownerX` (0...4).
    let untemplatedOwnerCount: Int
    /// Amendment v8 (Placement gate): how many owner items this world
    /// draws *left* of every helper (0...3) -- the recorded live placement
    /// (section 2's "each new item lands at the left end" is false on the
    /// owner's bar; crosscheck-rework7.json finding #1). Always visible,
    /// never gated by a fault knob -- this is the bar's own resting
    /// layout, not a fault. The plain default (`0`) keeps every existing
    /// scenario's own "helpers land leftmost" layout, which Amendment v8's
    /// own work item keeps as the *post-placement* case (scenario 1 etc.).
    let ownerItemsLeftOfHelpersCount: Int
    /// Amendment v8a: whether this world's own defaults-domain model
    /// (`defaultsWrite`/`defaultsForget`/`defaultsKeys`) is honoured when
    /// rendering the helpers' own rest position -- modelling "macOS 27
    /// honours the stored `NSStatusItem Preferred Position`" (`true`) vs.
    /// "macOS 27 ignores it" (`false`, the default -- every existing
    /// scenario's own fixed positions, unaffected by whatever `StageC1`
    /// now writes). Unproven either way on the real bar (SEAM-AUDIT.md);
    /// this fake models both outcomes so the wiring is exercised
    /// regardless of which turns out true.
    let honoursPreferredPosition: Bool
    /// Amendment v8a: when set, one additional on-bar owner item (always
    /// visible, ungated) appears at this minX, close enough to the bar's
    /// own left edge that no helper width/margin combination could ever
    /// leave room for the three helpers left of it -- the "no room, refuse
    /// before any launch" scenario.
    let noRoomOwnerMinX: Double?
    /// G3 (Amendment v7): the templated owner item alternates between
    /// `shapeOwner` and `shapeOwnerAlt` on every capture from the very
    /// first one -- including every capture inside `step3Baseline`'s own
    /// `ownerObserver.baseline()` call, which happens before any `length`
    /// is ever sent and so cannot be gated on `FaultKnob`'s own
    /// after-the-Nth-length phase gate. Models "the owner baseline itself
    /// disagrees across samples," which `StripAssessor.baseline` accepts
    /// and marks `template.markedDynamic()` rather than rejecting.
    private let dynamicTemplatedOwnerAtBaseline: Bool
    /// G2 (Amendment v7): makes `HidingVerification.prepare()`'s own
    /// internal (`C1Discoverer`-wrapped) discovery pass -- and only that
    /// pass, never `step3Baseline`'s own raw roster pass that seeds
    /// `ownerItemIDs`/`untemplatedOwnerBaseline` -- reject its composition
    /// once, before any `length` command is ever sent. Models a benign,
    /// one-off "prepare comes back not ready" defect that has nothing to
    /// do with G1 (this world's `discoveryResult()` already reads
    /// `ownRead: .notRead` honestly, like the live seam): a discovery-only
    /// phantom item, further left than Target, that never appears for
    /// pixels or AX, so it can never pollute the owner baseline built from
    /// the earlier, unaffected roster pass.
    private let injectPrepareRejection: Bool
    private var discoveryCallCount = 0
    private var hasFiredPrepareRejectionOnce = false
    static let phantomKey = key("phantom", pid: 599, identifier: "phantom.prepare-reject")

    /// Amendment v8 (Teardown fold rule): once `injectPrepareRejection`'s
    /// own one-shot phantom has fired -- which only happens after the rest
    /// baseline's own capture loop has already finished clean
    /// (`hasFiredPrepareRejectionOnce`'s own doc comment above) -- a fold
    /// ghost also starts appearing, from the very next real capture on.
    /// That next capture is the staged teardown's own Protected-only fold
    /// read (`step3Baseline` aborts at `prepare()`, before any `length` is
    /// ever sent, and nothing else in between takes a pixel capture): "a
    /// fold appears while at rest," discovered only at teardown, on a
    /// layout where no `length` was ever sent. Meaningless without
    /// `injectPrepareRejection: true`.
    private let unreadableFoldAfterAbort: Bool

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
    /// F4 / scenario 1c: virtual-clock time of the *first* `rest` command
    /// this world has ever seen -- `nil` before that.
    private var firstRestSeenAt: Double?
    /// F4 / scenario 1c: `true` until `.transientUnstableRestOnce`'s own
    /// window has been read past once, after which it never offsets the
    /// spacer again (a one-shot fault, not a lasting one).
    private var transientRestStillPending = true
    static let transientRestWindowSeconds = 1.3
    /// G4: captures since the most recently seen `rest` command (reset to
    /// 0 on every one, unlike `capturesSinceArmed`, which never resets) --
    /// `.foldOnlyAtPostRestRead`'s own precise capture-index gate.
    private var capturesSinceLastRest = 0

    private var captureCount = 0

    /// G7 (Amendment v7): `.discoveryHang`'s own real wall-clock sleep --
    /// configurable so a test can pair a short injected
    /// `C1DiscoveryExecutor` bound with a correspondingly short hang,
    /// instead of every discovery-timeout scenario paying the live
    /// default's real 3.0 s+ (`FakeDiscoverer.discover`, `FakeC1Environment.swift`).
    let hangDurationSeconds: Double
    /// G8 (Amendment v7, "time budget"): the virtual-clock cost every
    /// discovery pass charges (`SimulatedLatency.discoverySeconds`, 36.5 ms,
    /// by default) -- overridable per world so a test can simulate a
    /// slower bar (FINDINGS.md's own "~290 ms with a stuck accessory
    /// process") without changing the shared constant every other scenario
    /// also calibrates against.
    let discoverySecondsOverride: Double

    init(
        templatedOwnerPresent: Bool = true,
        untemplatedOwnerCount: Int = 0,
        ownerItemsLeftOfHelpersCount: Int = 0,
        honoursPreferredPosition: Bool = false,
        noRoomOwnerMinX: Double? = nil,
        dynamicTemplatedOwnerAtBaseline: Bool = false,
        injectPrepareRejection: Bool = false,
        unreadableFoldAfterAbort: Bool = false,
        hangDurationSeconds: Double = 3.5,
        discoverySecondsOverride: Double = SimulatedLatency.discoverySeconds
    ) {
        precondition(untemplatedOwnerCount >= 0 && untemplatedOwnerCount <= 4, "the cluster must stay clear of Protected and the templated owner")
        precondition(ownerItemsLeftOfHelpersCount >= 0 && ownerItemsLeftOfHelpersCount <= 3, "the recorded live bar never showed more than 3")
        self.templatedOwnerPresent = templatedOwnerPresent
        self.untemplatedOwnerCount = untemplatedOwnerCount
        self.ownerItemsLeftOfHelpersCount = ownerItemsLeftOfHelpersCount
        self.honoursPreferredPosition = honoursPreferredPosition
        self.noRoomOwnerMinX = noRoomOwnerMinX
        self.dynamicTemplatedOwnerAtBaseline = dynamicTemplatedOwnerAtBaseline
        self.injectPrepareRejection = injectPrepareRejection
        self.unreadableFoldAfterAbort = unreadableFoldAfterAbort
        self.hangDurationSeconds = hangDurationSeconds
        self.discoverySecondsOverride = discoverySecondsOverride
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

    /// G3: which glyph the templated owner item draws this capture --
    /// `shapeOwner` unless one of the two "content changes" knobs says
    /// otherwise. `captureCount` (already incremented by the caller before
    /// this runs, `image()` below) alternates the baseline-time knob every
    /// other capture, so consecutive baseline samples disagree with each
    /// other rather than every sample being simply a different, but still
    /// internally self-consistent, glyph.
    private func templatedOwnerShapeLocked() -> [String] {
        if dynamicTemplatedOwnerAtBaseline {
            return captureCount % 2 == 0 ? Self.shapeOwner : Self.shapeOwnerAlt
        }
        if isArmedLocked(), case .ownerAppearanceChangesLater = knob { return Self.shapeOwnerAlt }
        if isArmedLocked(), case .ownerWeakMatchOnce = knob, capturesSinceArmed == 1 { return Self.shapeOwnerWeak }
        return Self.shapeOwner
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
        let restX = resolvedXLocked(bundleID: C1HelperRole.protected, autosaveName: C1AutosaveName.spacer, fallback: Self.spacerX)
        if spacerState == .rest, isArmedLocked(), case .transientUnstableRestOnce = knob, transientRestStillPending {
            if let firstRestSeenAt, clock.now() - firstRestSeenAt < Self.transientRestWindowSeconds {
                return restX + 3.0
            }
            // The window has passed -- consumed for good, never offsets
            // again (a one-shot transient, not a lasting stuck offset).
            transientRestStillPending = false
        }
        guard spacerState == .rest, isArmedLocked(), case .spacerStuckOffset(let pt) = knob else { return restX }
        return restX + pt
    }

    /// Gated on `spacerState == .rest`, not merely "armed": the ghost
    /// exists only while at rest, matching the trigger's own name and
    /// keeping it from ever appearing during the mid-expansion verifier
    /// read (which tolerates no fold either way, so this would only ever
    /// have added noise there, never a meaningful assertion).
    ///
    /// G4: `.foldOnlyAtPostRestRead` is a second, independent gate -- a
    /// precise capture-index window after the most recent `rest`, not
    /// "for as long as resting" -- see its own doc comment.
    private func foldGhostPresentLocked() -> Bool {
        // Amendment v8 (Teardown fold rule): from the first real capture
        // after `injectPrepareRejection`'s own phantom has fired, on --
        // see `unreadableFoldAfterAbort`'s own doc comment.
        if unreadableFoldAfterAbort, hasFiredPrepareRejectionOnce { return true }
        if spacerState == .rest, isArmedLocked(), case .foldWithoutExpansion = knob { return true }
        if isArmedLocked(), case .foldOnlyAtPostRestRead = knob, (9...12).contains(capturesSinceLastRest) { return true }
        return false
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
            markDownLocked(role)
        }
    }

    /// G5: the non-blocking `requestQuit()`'s own effect -- logged as
    /// `"\(role).quitRequested"`, distinct from the blocking path's
    /// `"\(role).quit"`, so a test can tell which one the stage actually
    /// took; otherwise identical (this fake models no real async delay
    /// between a closed stdin and the helper actually exiting).
    func setDownNonBlocking(_ role: String) {
        lock.withLock {
            log.append("\(role).quitRequested")
            markDownLocked(role)
        }
    }

    private func markDownLocked(_ role: String) {
        switch role {
        case "protected": protectedUp = false
        case "spacer": spacerUp = false
        case "target": targetUp = false
        default: break
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
                if firstRestSeenAt == nil { firstRestSeenAt = clock.now() }
                capturesSinceLastRest = 0
            } else if line.hasPrefix("length "), let value = Double(line.dropFirst("length ".count)) {
                spacerState = .expanded(value)
                lengthCommandsSeen += 1
            }
        }
    }

    private func targetXLocked() -> Double {
        let restX = resolvedXLocked(bundleID: C1HelperRole.target, autosaveName: C1AutosaveName.target, fallback: Self.targetRestX)
        if targetNeverHides { return restX }
        switch spacerState {
        case .rest: return restX
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
            capturesSinceLastRest += 1
            if isArmedLocked() { capturesSinceArmed += 1 }
            if captureShouldFailLocked() { return ([], true) }
            var g: [(shape: [String], atPt: Double)] = []
            if targetUp { g.append((Self.shapeTarget, targetXLocked())) }
            if spacerUp { g.append((Self.shapeSpacer, spacerRenderXLocked())) }
            if protectedVisibleLocked() { g.append((Self.shapeProtected, resolvedXLocked(bundleID: C1HelperRole.protected, autosaveName: C1AutosaveName.protected, fallback: Self.protectedX))) }
            if templatedOwnerVisibleLocked() { g.append((templatedOwnerShapeLocked(), Self.ownerX)) }
            for i in 0..<untemplatedOwnerCount where extraVisibleLocked(i) {
                g.append((Self.shapeOwner, extraXLocked(i)))
            }
            for i in 0..<ownerItemsLeftOfHelpersCount {
                g.append((Self.shapeOwner, Self.ownerLeftX(i)))
            }
            if let noRoomOwnerMinX {
                g.append((Self.shapeOwner, noRoomOwnerMinX + 1))
            }
            if foldGhostPresentLocked() {
                g.append((Self.shapeFoldGhost, Self.foldGhostX))
            }
            // G6: the one-time jump, on this same first post-arm capture,
            // before any pixel work below (order does not matter to the
            // clock, only that it happens exactly once).
            if isArmedLocked(), case .hugeAgeJumpBeforeVerify(let seconds) = knob, capturesSinceArmed == 1 {
                clock.advance(seconds)
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
        // G2: reject exactly `verification.prepare()`'s own single internal
        // discovery call (through `C1Discoverer`), never `step3Baseline`'s
        // own raw roster pass (whose `ids`/`untemplatedOwnerBaseline`
        // seeding must stay clean) nor any of step2Launch's three
        // per-helper discovery calls, nor a later teardown discovery
        // (`confirmReap`/`waitForTeardownBaselineEquivalence`) after this
        // aborts. All of those, like `prepare()`'s own call, run with
        // `lengthCommandsSeen == 0` (no `length` command is ever sent once
        // step 3 aborts), so that alone cannot tell them apart -- but only
        // `prepare()`'s call happens after the owner rest baseline's own
        // capture loop (`step3Baseline`'s `ownerObserver.baseline(...)`,
        // itself after the 24-capture warm-up), so `captureCount > 24` is
        // true only there. `hasFiredPrepareRejectionOnce` then keeps this
        // one-shot: prepare() is called exactly once by `step3Baseline`, so
        // failing anything after this first hit would wrongly poison the
        // later teardown's own discovery calls too.
        let shouldBreakComposition: Bool = lock.withLock {
            discoveryCallCount += 1
            guard injectPrepareRejection, !hasFiredPrepareRejectionOnce, lengthCommandsSeen == 0, captureCount > 24 else { return false }
            hasFiredPrepareRejectionOnce = true
            return true
        }
        let entries = liveEntries()
        var items = entries.map { id, entry in
            DiscoveredItem(
                key: entry.key, basis: .declared,
                process: ProcessInfoRecord(pid: entry.pid, bundleID: entry.key.namespace, localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
                frame: entry.frame, position: entry.position,
                title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
            )
        }
        if shouldBreakComposition {
            items.append(DiscoveredItem(
                key: Self.phantomKey, basis: .declared,
                process: ProcessInfoRecord(pid: 599, bundleID: Self.phantomKey.namespace, localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
                frame: Self.frame(atPt: Self.targetRestX - 50), position: .onBar,
                title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
            ))
        }
        let set = DiscoveredItemSet(
            items: items, visibleControlItem: nil, hiddenDivider: nil, alwaysHiddenDivider: nil,
            // Rework #7a (G1, G7 audit): the *raw* live discoverer
            // (`MenuBarDiscoverer` over `HarnessProcesses`, `StageC1Live.swift`)
            // never reads `.ok` here -- `HarnessProcesses` drops this
            // process's own `isSelf` read before `ItemCatalog.build` ever
            // sees it (`vizprobe/StageRun.swift:32`), so `ownRead` stays at
            // its initial `.notRead` (`ItemCatalog.swift:86`; neither the
            // `.failed` branch at :99 nor the `.ok`/`.identifiersMissing`
            // branch at :119 can ever run for a pid that was filtered out
            // before the loop). This world used to hard-code `.ok`, which
            // hid exactly the live defect G1 describes: `C1Discoverer`
            // forwards `set.ownRead` unchanged
            // (`Sources/C1Live/C1Discoverer.swift:57`), so a live run's own
            // composed set also carries `.notRead`, and `CheckPlan.make`
            // (`Packages/IceCore/Sources/IceCore/CheckPlan.swift:25`) then
            // always returns `.skip(.dividerUnavailable)` -- step 3 can
            // never reach `.ready`. See `SEAM-AUDIT.md` and the new
            // `C1LiveTests.C1DiscovererTests` case this fix is paired with.
            ownRead: .notRead, systemElements: [], dropped: [], staleProcesses: [:], completeness: .complete
        )
        clock.advance(discoverySecondsOverride)
        var enumeratedPIDs = Set(entries.map { $0.entry.pid })
        if shouldBreakComposition { enumeratedPIDs.insert(599) }
        return DiscoveryResult(
            set: set, duration: 0, origin: DiscoveryOrigin(x: 0, y: 0), bounds: Self.bounds,
            nextCursor: 0, quarantined: [], enumeratedPIDs: enumeratedPIDs
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
    /// who exists right now. `position` is `.onBar` for everything drawn
    /// on the strip; the fixed parked items (Amendment v8) are the one
    /// exception -- always present, never drawn (a parked item's frame
    /// sits below the bar on the real one, so it never contributes ink).
    private func liveEntries() -> [(id: String, entry: (key: ItemKey, pid: pid_t, frame: BarRect, position: ItemPosition))] {
        lock.withLock {
            var result = [(id: String, entry: (key: ItemKey, pid: pid_t, frame: BarRect, position: ItemPosition))]()
            if targetUp {
                result.append((Self.targetKey.encoded, (Self.targetKey, Self.targetPID, Self.frame(atPt: targetXLocked()), .onBar)))
            }
            if spacerUp {
                result.append((Self.spacerKey.encoded, (Self.spacerKey, Self.spacerPID, Self.frame(atPt: spacerRenderXLocked()), .onBar)))
            }
            if protectedVisibleLocked() {
                let x = resolvedXLocked(bundleID: C1HelperRole.protected, autosaveName: C1AutosaveName.protected, fallback: Self.protectedX)
                result.append((Self.protectedKey.encoded, (Self.protectedKey, Self.protectedPID, Self.frame(atPt: x), .onBar)))
            }
            if templatedOwnerVisibleLocked() {
                result.append((Self.ownerKey.encoded, (Self.ownerKey, Self.ownerPID, Self.frame(atPt: Self.ownerX), .onBar)))
            }
            for i in 0..<untemplatedOwnerCount where extraVisibleLocked(i) {
                let key = Self.extraKey(i)
                result.append((key.encoded, (key, Self.extraPID(i), Self.frame(atPt: extraXLocked(i)), .onBar)))
            }
            // Amendment v8 (Placement gate): the recorded live placement --
            // owner items drawn left of every helper. Always present (not
            // gated by any fault knob or phase); genuinely on-bar.
            for i in 0..<ownerItemsLeftOfHelpersCount {
                let key = Self.ownerLeftKey(i)
                result.append((key.encoded, (key, Self.ownerLeftPID(i), Self.frame(atPt: Self.ownerLeftX(i)), .onBar)))
            }
            // Amendment v8a: the dedicated "no room for the helpers"
            // fixture -- one owner item close enough to the bar's own
            // left edge that `PlacementPlan.plan` must refuse, before any
            // helper ever launches.
            if let noRoomOwnerMinX {
                let key = Self.noRoomOwnerKey
                result.append((key.encoded, (key, Self.noRoomOwnerPID, Self.frame(atPt: noRoomOwnerMinX + 1), .onBar)))
            }
            // Amendment v8 (parked items): the owner's own bar always
            // lists 2-3 of them (frames below the bar) -- fixed, always
            // present, never drawn.
            for i in 0..<Self.parkedMinXs.count {
                let key = Self.parkedKey(i)
                let frame = BarRect(minX: Self.parkedMinXs[i], minY: Self.parkedMinYs[i], width: 9, height: Double(Self.heightPt))
                result.append((key.encoded, (key, Self.parkedPID(i), frame, .parked)))
            }
            return result
        }
    }
}
