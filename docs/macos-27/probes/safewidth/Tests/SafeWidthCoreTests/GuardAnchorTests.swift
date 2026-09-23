// Anchor resolution: agreement/offset selection, reclassification
// within and across captures, dynamic itemLost, and anchor search
// skipping non-static neighbours.
import Testing
@testable import SafeWidthCore

// MARK: - Anchor agreement uses the RIGHT anchor's offset as the common offset

@Test func anchorAgreementUsesRightOffsetAsTheCommonOffset() {
    var g = SafetyGuard(
        baselines: [
            item("Y1", at: 0, width: 10, kind: .static),
            item("X", at: 10, width: 10, kind: .dynamic),
            item("Y2", at: 20, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    let cap = CaptureReading(
        time: 0,
        items: [
            // Y1's own offset (1.0) is exactly at anchorTolerance, so it is
            // not itself reported as shifted (see the boundary test above).
            reading("Y1", .found(offset: 1.0)),
            reading("X", .notFound(bestMismatch: 0.1)),
            reading("Y2", .found(offset: 1.8)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    var captured: Span?
    let decision = g.assess(cap, presence: { _, span in
        captured = span
        return true
    })
    // Anchors agree (|1.0 - 1.8| = 0.8 <= 1.0); the common offset used for X
    // must be the RIGHT anchor's (1.8), not the left's (1.0) and not their
    // average (1.4).
    #expect(decision == .clean(info: [.shifted(id: "Y2", offset: 1.8)]))
    #expect(captured == Span(lo: 11.8, hi: 21.8))
}

// MARK: - Reclassification within a capture must not change that capture's anchors

@Test func reclassificationDuringACaptureDoesNotAffectThatCapturesAnchors() {
    var g = SafetyGuard(
        baselines: [
            item("M", at: 0, width: 10, kind: .static),
            item("X", at: 10, width: 10, kind: .dynamic),
            item("Y", at: 20, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    // M: notFound, its anchors are virtual-P (offset 0) and Y (offset 0) -> agree,
    // presence true -> appearanceChanged(M), reclassified AFTER this capture.
    // X: dynamic, its left anchor is M. If M were already reclassified to
    // dynamic while X is processed in the same pass, X's left anchor search
    // would skip M and fall back to virtual P (offset 0), agreeing with Y's
    // offset (0) and hiding the bug. M's own reading is .notFound this
    // capture, so M (still correctly seen as .static) contributes no offset,
    // so X's anchors must DISAGREE (left nil, right 0) -> itemUnverifiable.
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("M", .notFound(bestMismatch: 0.1)),
            reading("X", .notFound(bestMismatch: 0.1)),
            reading("Y", .found(offset: 0)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    let decision = g.assess(cap, presence: alwaysTrue)
    #expect(decision == .suspect(reasons: [.itemUnverifiable(id: "X")]))
    #expect(g.baselines.first(where: { $0.id == "M" })?.kind == .dynamic)
    #expect(g.baselines.first(where: { $0.id == "X" })?.kind == .dynamic)
}

// Rule C's anchor search must use each baseline's CURRENT kind, i.e. as of
// the capture being assessed, not a snapshot taken when the guard was built.
// An item reclassified to .dynamic by one capture must stop serving as a
// static anchor on the very next capture.
@Test func reclassifiedItemStopsActingAsAStaticAnchorOnTheNextCapture() {
    var g = SafetyGuard(
        baselines: [
            item("M", at: 0, width: 10, kind: .static),
            item("X", at: 10, width: 10, kind: .dynamic),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    // Capture 1: M is notFound; its anchors (virtual P at offset 0, screen
    // edge at offset 0) agree, and presence is true, so M is reclassified to
    // .dynamic AFTER this capture. X has no reading this capture (irrelevant
    // to what is being pinned here) so it comes back itemUnverifiable.
    let cap1 = CaptureReading(
        time: 0,
        items: [reading("M", .notFound(bestMismatch: 0.1))],
        protected: protectedOkAtZero,
        pill: nil
    )
    let d1 = g.assess(cap1, presence: alwaysTrue)
    #expect(d1 == .suspect(reasons: [.itemUnverifiable(id: "X")]))
    #expect(g.baselines.first(where: { $0.id == "M" })?.kind == .dynamic)

    // Capture 2: protected absent, M reported .found(0). If M were still
    // (incorrectly) treated as a static anchor here, X's left anchor would
    // be M's offset (0), which would agree with the screen edge (0) and
    // silently verify X. Correctly, M is now .dynamic, so it cannot serve as
    // an anchor: X's left anchor falls back to the virtual P anchor, which
    // is unavailable (protected absent) -> itemUnverifiable. M itself is
    // also now assessed as dynamic, and its own anchors (virtual P, screen
    // edge) disagree the same way -> itemUnverifiable too. (The unknown
    // streak already stood at 1 from capture 1, so it now reaches the
    // persistence threshold of 2 -> .stop, not .suspect.)
    let cap2 = CaptureReading(
        time: 1,
        items: [reading("M", .found(offset: 0)), reading("X", .notFound(bestMismatch: 0.1))],
        protected: .absent,
        pill: nil
    )
    let d2 = g.assess(cap2, presence: alwaysTrue)
    #expect(d2 == .stop(reasons: [.protectedLost, .itemUnverifiable(id: "M"), .itemUnverifiable(id: "X")]))
}

// MARK: - Dynamic item, anchors agree, presence false -> itemLost

@Test func dynamicItemWithAgreeingAnchorsAndNoPresenceIsItemLost() {
    var g = SafetyGuard(
        baselines: [
            item("Y1", at: 0, width: 10, kind: .static),
            item("X", at: 10, width: 10, kind: .dynamic),
            item("Y2", at: 20, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("Y1", .found(offset: 0)),
            reading("X", .notFound(bestMismatch: 0.1)),
            reading("Y2", .found(offset: 0)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    let decision = g.assess(cap, presence: alwaysFalse)
    #expect(decision == .suspect(reasons: [.itemLost(id: "X")]))
}

// MARK: - Anchor search skips over non-static neighbours to reach a further static item

@Test func leftAnchorSearchSkipsOverAnInterveningDynamicNeighbor() {
    var g = SafetyGuard(
        baselines: [
            item("Y", at: 0, width: 10, kind: .static),
            item("D1", at: 10, width: 10, kind: .dynamic),
            item("D2", at: 20, width: 10, kind: .dynamic),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("Y", .found(offset: 0)),
            reading("D1", .notFound(bestMismatch: 0.1)),
            reading("D2", .notFound(bestMismatch: 0.1)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    // D2's nearest static neighbour to the left is Y, two positions away
    // (D1, being dynamic, must be skipped). Both D1 and D2 end up anchored
    // by Y on the left and the screen edge on the right, offset 0 on both
    // sides, so presence alone decides.
    let decision = g.assess(cap, presence: alwaysTrue)
    #expect(decision == .clean(info: []))
}
