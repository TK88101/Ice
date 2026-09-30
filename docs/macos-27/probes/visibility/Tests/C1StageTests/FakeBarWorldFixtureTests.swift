// Rework #7a: direct, StageC1-independent checks of the fixture mechanisms
// this rework added or changed -- `FakeBarWorld`'s own behaviour, never
// `StageC1`'s. These exist because G1 (Amendment v7) currently stops every
// `StageC1` orchestration run at step 3 before any of the new G3 knobs ever
// get a chance to matter (see `SEAM-AUDIT.md` and the worker report): without
// this file, a bug in the new knobs themselves would be invisible until
// rework #7b's source fix lands, and could then be mistaken for a leftover
// G3 defect instead of a fixture mistake made here.
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDiscovery
import Testing

@Suite("FakeBarWorld -- rework #7a fixture mechanisms, checked independently of StageC1")
struct FakeBarWorldFixtureTests {
    /// G1 audit: the raw discovery this world hands `C1Discoverer` must
    /// read `.notRead`, matching the live harness's own self-filtered read
    /// (`ItemCatalog.swift:86`, never reached by `.failed`/`.ok` for a pid
    /// `HarnessProcesses` already dropped) -- not the `.ok` rework #6a
    /// hard-coded, which hid G1 from every existing I7 scenario.
    @Test("the raw discoveryResult() reads ownRead .notRead, like the live harness")
    func rawDiscoveryReadsOwnReadNotRead() {
        let world = FakeBarWorld()
        world.setUp("protected")
        world.setUp("spacer")
        world.setUp("target")
        #expect(world.discoveryResult().set.ownRead == .notRead)
    }

    /// G8 audit: pin the calibrated constants themselves, so a later,
    /// unrelated edit cannot silently drift the run's simulated duration
    /// away from the brief's own per-operation figures without a test
    /// noticing.
    @Test("the calibrated per-operation latencies match the brief's own figures")
    func calibratedLatenciesMatchTheBrief() {
        #expect(SimulatedLatency.captureSeconds == 0.03)
        #expect(SimulatedLatency.discoverySeconds == 0.0365)
    }

    /// G3 (baseline half): with the knob on, two back-to-back captures at
    /// the templated owner's own position must disagree -- the mechanism
    /// `StripAssessor.baseline` needs to mark the template dynamic, rather
    /// than every sample coincidentally reading the same self-consistent
    /// glyph.
    @Test("dynamicTemplatedOwnerAtBaseline: consecutive captures disagree at the owner's own position")
    func dynamicOwnerAtBaselineAlternatesShape() {
        let world = FakeBarWorld(dynamicTemplatedOwnerAtBaseline: true)
        world.setUp("protected")
        world.setUp("spacer")
        world.setUp("target")
        guard let first = world.image(), let second = world.image() else {
            Issue.record("expected both captures to succeed")
            return
        }
        #expect(pixelsDiffer(first, second, atXPt: FakeBarWorld.ownerX))
    }

    /// G3 (dynamic half), negative control: with the knob off (the
    /// default), the templated owner item is the same glyph on every
    /// capture -- the mechanism above must not fire when nothing asked
    /// for it.
    @Test("without the knob, the templated owner item is the same glyph on every capture")
    func staticOwnerNeverAlternates() {
        let world = FakeBarWorld()
        world.setUp("protected")
        world.setUp("spacer")
        world.setUp("target")
        guard let first = world.image(), let second = world.image() else {
            Issue.record("expected both captures to succeed")
            return
        }
        #expect(!pixelsDiffer(first, second, atXPt: FakeBarWorld.ownerX))
    }

    /// G3 (post-baseline half): `.ownerAppearanceChangesLater` must leave
    /// the owner item's glyph untouched until the phase gate opens (a
    /// `length` command), then change it -- "a baseline-static item that
    /// later reads differently," never "different from the very first
    /// baseline sample" (that is the other knob, above).
    @Test("ownerAppearanceChangesLater: the glyph changes only once armed (after a length command)")
    func ownerAppearanceChangesOnlyOnceArmed() {
        let world = FakeBarWorld()
        world.setUp("protected")
        world.setUp("spacer")
        world.setUp("target")
        world.arm(.ownerAppearanceChangesLater)

        guard let beforeA = world.image(), let beforeB = world.image() else {
            Issue.record("expected both pre-arming captures to succeed")
            return
        }
        #expect(!pixelsDiffer(beforeA, beforeB, atXPt: FakeBarWorld.ownerX), "unarmed captures must still agree with each other")

        world.handleCommand("length 700", role: "spacer")
        guard let afterArmed = world.image() else {
            Issue.record("expected the post-arming capture to succeed")
            return
        }
        #expect(pixelsDiffer(beforeA, afterArmed, atXPt: FakeBarWorld.ownerX), "once armed, the glyph must differ from the pre-arming reading")
    }

    /// Reads back the ink bytes directly over the glyph's own column band
    /// (10 pt wide at `FakeBarWorld.scale`, the fixed glyph width every
    /// shape in that world uses) so this check needs no knowledge of
    /// `StripAssessor`/`TemplateMatcher` (frozen, IceCore) -- only that the
    /// two rendered bitmaps are not byte-identical there.
    private func pixelsDiffer(_ a: StripImage, _ b: StripImage, atXPt xPt: Double) -> Bool {
        guard a.width == b.width, a.height == b.height else { return true }
        let scale = FakeBarWorld.scale
        let x0 = Int((xPt * Double(scale)).rounded())
        let widthPx = 10 * scale
        for y in 0..<a.height {
            for x in x0..<min(x0 + widthPx, a.width) {
                let i = (y * a.width + x) * 4
                guard i + 2 < a.bytes.count, i + 2 < b.bytes.count else { continue }
                if a.bytes[i] != b.bytes[i] || a.bytes[i + 1] != b.bytes[i + 1] || a.bytes[i + 2] != b.bytes[i + 2] {
                    return true
                }
            }
        }
        return false
    }
}
