// I7 support types split out of FakeBarWorld.swift (rework #8, to stay
// under the 800-line cap): the spacer's own rest/expanded state, the
// phase-armed fault knobs a scenario can arm on `FakeBarWorld`, and the
// virtual clock / per-operation latency model every knob and every
// scenario's own timing shares. See `FakeBarWorld.swift`'s own header for
// what the world as a whole models.
import Foundation


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
