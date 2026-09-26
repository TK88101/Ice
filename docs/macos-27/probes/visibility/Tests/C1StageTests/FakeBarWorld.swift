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
    /// F4 (Amendment v6, crosscheck #3; I7 scenario 1c): the spacer reads
    /// back at a small, transient offset from its own rest baseline for
    /// `transientWindowSeconds` of virtual time after the *first* `rest`
    /// command this world ever sees, then genuinely settles for every
    /// collapse after that -- "the spacer was still animating back when
    /// the first post-collapse sample was taken." Distinct from
    /// `.spacerStuckOffset` (which never settles): this one is a
    /// disagreement between paired samples the run must retry through,
    /// never a latch trip.
    case transientUnstableRestOnce
    /// G3 (Amendment v7): the templated owner item's own drawn content
    /// changes once a cycle is under way -- still listed, still drawn, at
    /// the same x, just a different glyph (`shapeOwnerAlt`) -- so a
    /// baseline that read it as *static* now disagrees with its own
    /// template. Distinct from `dynamicTemplatedOwnerAtBaseline` (below),
    /// which instead makes the item disagree with itself *during* the
    /// baseline window, before any `length` is ever sent.
    case ownerAppearanceChangesLater
    /// G4 (Amendment v7): a chevron-width agent frame plus real ink
    /// appears for exactly the 5th and 6th `image()` capture after a
    /// `rest` command -- timed to land inside `StageC1Cycle.runCycle`'s
    /// own post-rest `readFoldValue` read (one `observe()` bracket = 2
    /// captures), which runs right after `confirmRestSettled`'s own
    /// settled read (2 observes = 4 captures, assuming it settles on the
    /// first attempt, which it does with no other fault armed) has
    /// already finished, and long before the reset check's own fold read
    /// many (simulated) seconds later. This isolates the specific read
    /// Cycle.swift's own G4 fix feeds to the latch from every other
    /// post-rest fold read -- `.foldWithoutExpansion` above trips at
    /// `collapse.rest` instead, a path that was never broken.
    case foldOnlyAtPostRestRead
    /// G3 (Amendment v7, "a single weak/ambiguous match... does not trip
    /// by itself"): the templated owner item reads `shapeOwnerWeak`
    /// (mismatch 0.07, a weak but still `.unique` match) for exactly the
    /// 1st capture since arming, then reverts to the normal `shapeOwner`
    /// for every capture after -- a transient glitch a real static badge
    /// or icon redraw might cause, distinct from `.ownerAppearanceChangesLater`
    /// (which never recovers).
    case ownerWeakMatchOnce
    /// G6 (Amendment v7, "freshness enforced"): a one-time, large virtual
    /// clock jump on the very first capture since arming -- simulating a
    /// cycle that unexpectedly takes far longer internally (preflight
    /// retries, rest-confirm retries) than the proactive per-cycle
    /// prediction (`maybeRefreshVerificationBaseline`, already run and
    /// satisfied *before* this cycle's own captures start) ever accounted
    /// for. By the time this same cycle reaches its own verify call, the
    /// prepared baseline is stale despite the proactive check having found
    /// nothing to refresh -- only the newly enforced per-verify guard can
    /// still catch it.
    case hugeAgeJumpBeforeVerify(seconds: Double)
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
///
/// Rework #7a (G8): rework #6a charged `captureSeconds` from
/// `LiveStripCapturer`'s own *screen-capture* wall time alone (5-9 ms),
/// which is not what a "capture" costs a caller of `Sampler`/
/// `VisibilityObserver` on the owner's own 1728x32 pt strip -- that number
/// never included the pixel work (`Ink`/`TemplateMatcher`/`StripAssessor`)
/// every real sample also pays. Codex round 7's own duration lens
/// (crosscheck-rework6.json `notes.duration`) backs into that whole-sample
/// cost from measured wall stamps instead: removing the warm-up's 24 x
/// 0.25 s explicit sleep from a measured ~7.2 s `verify` leaves ~30 ms per
/// capture. That single number, fed through the *existing* real IceCore/
/// MenuBarCapture call counts and sleeps (nothing here adds a new sleep --
/// `VisibilityObserver.observe`'s 2 samples x (capture, AX, capture) +
/// `minSampleSpacing` already comes to ~0.43-0.44 s; `HidingVerification`'s
/// 24-capture warm-up (`warmUpSpacing` 0.25 s) + a 4-sample, `baselineMinSpan`
/// 3 s `baseline()` already comes to ~10.5 s), reproduces the brief's own
/// per-operation figures (observe ~0.43 s, verify ~7.2 s, prepare ~11.5 s)
/// without this world charging any of those totals a second time -- see
/// `Tests/C1StageTests/SEAM-AUDIT.md` for the full worked reconciliation.
enum SimulatedLatency {
    /// Rework #7a: ~30 ms, the residual per-capture cost the duration
    /// lens backs into after removing modelled sleeps from a measured
    /// `verify` (see the type's own doc comment) -- not
    /// `LiveStripCapturer`'s screen-capture-only 5-9 ms, which undercounts
    /// the pixel work every real sample also pays.
    static let captureSeconds = 0.03
    /// Not separately measured in the cited evidence -- a conservative
    /// estimate, the same order as a capture.
    static let axReadSeconds = 0.01
    /// `STATUS.md:20`'s measured median keyed-discovery pass, unrounded
    /// (rework #6a rounded it down to 0.03; G8 asks for the owner-bar
    /// figure itself, since C1 charges this once per latched capture --
    /// about 2,160 times in a full run -- so the rounding was not free).
    static let discoverySeconds = 0.0365
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
    /// G3 (Amendment v7): a second, still-asymmetric owner glyph -- `shapeOwner`
    /// read top-to-bottom in reverse -- for the two "owner content changes"
    /// knobs below. It shares `shapeOwner`'s width and ink coverage (so a
    /// mismatch reads as a *content* change, not a vacated slot), but
    /// disagrees with it row-for-row, which is what makes
    /// `StripAssessor.baseline` (IceCore, frozen) refuse to call the two
    /// samples the same static template.
    static let shapeOwnerAlt: [String] = [
        "##........", "##........", "##........", "##########", "##########",
        "##########", "##########", "........##", "........##", "........##",
    ]
    /// A solid block, wide enough to clear `foldClusterMinPx` (16 px) many
    /// times over -- the "fold without expansion" knob's own ink.
    static let shapeFoldGhost: [String] = Array(repeating: "##########", count: 10)
    /// G3 (Amendment v7): `shapeOwner` with 16 cells flipped (rows 3-4).
    /// The baseline template's own cared region is 14x14 = 196 cells (a
    /// 2 pt margin around this 10x10 glyph, consistently background in
    /// every baseline sample, cared like the ink itself) -- empirically
    /// confirmed by printing `ItemTemplate.caredCount` -- so 16/196 = 0.082
    /// mismatch, inside `(DetectorParameters.maxMismatch (0.05),
    /// weakThreshold (0.12)]`. `TemplateMatcher.match` returns `.unique`
    /// with a mismatch *above* `maxMismatch` (a weak match), never
    /// `.absent` or `.ambiguous` -- `.ownerWeakMatchOnce`'s own
    /// single-capture glitch.
    static let shapeOwnerWeak: [String] = [
        "........##", "........##", "........##", "..........", "......####",
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

    /// Whether the templated owner item (`ownerKey`, `ownerX`) exists in
    /// this world at all -- `false` models the owner's own bar having no
    /// item the pixel baseline can template (scenario 1b).
    private let templatedOwnerPresent: Bool
    /// How many untemplated (baseline-rejected) owner items this world
    /// also carries, left of `ownerX` (0...4).
    let untemplatedOwnerCount: Int
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
        dynamicTemplatedOwnerAtBaseline: Bool = false,
        injectPrepareRejection: Bool = false,
        hangDurationSeconds: Double = 3.5,
        discoverySecondsOverride: Double = SimulatedLatency.discoverySeconds
    ) {
        precondition(untemplatedOwnerCount >= 0 && untemplatedOwnerCount <= 4, "the cluster must stay clear of Protected and the templated owner")
        self.templatedOwnerPresent = templatedOwnerPresent
        self.untemplatedOwnerCount = untemplatedOwnerCount
        self.dynamicTemplatedOwnerAtBaseline = dynamicTemplatedOwnerAtBaseline
        self.injectPrepareRejection = injectPrepareRejection
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
        if spacerState == .rest, isArmedLocked(), case .transientUnstableRestOnce = knob, transientRestStillPending {
            if let firstRestSeenAt, clock.now() - firstRestSeenAt < Self.transientRestWindowSeconds {
                return Self.spacerX + 3.0
            }
            // The window has passed -- consumed for good, never offsets
            // again (a one-shot transient, not a lasting stuck offset).
            transientRestStillPending = false
        }
        guard spacerState == .rest, isArmedLocked(), case .spacerStuckOffset(let pt) = knob else { return Self.spacerX }
        return Self.spacerX + pt
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
            capturesSinceLastRest += 1
            if isArmedLocked() { capturesSinceArmed += 1 }
            if captureShouldFailLocked() { return ([], true) }
            var g: [(shape: [String], atPt: Double)] = []
            if targetUp { g.append((Self.shapeTarget, targetXLocked())) }
            if spacerUp { g.append((Self.shapeSpacer, spacerRenderXLocked())) }
            if protectedVisibleLocked() { g.append((Self.shapeProtected, Self.protectedX)) }
            if templatedOwnerVisibleLocked() { g.append((templatedOwnerShapeLocked(), Self.ownerX)) }
            for i in 0..<untemplatedOwnerCount where extraVisibleLocked(i) {
                g.append((Self.shapeOwner, extraXLocked(i)))
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
                frame: entry.frame, position: .onBar,
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
