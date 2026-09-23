// Clean/shifted-baseline assessment: clean, uniform shift, non-uniform
// shift, static notFound, appearanceChanged, and dynamic items anchored
// by the protected marker or the screen edge.
import Testing
@testable import SafeWidthCore

// MARK: - 1. Clean baseline

@Test func cleanCaptureWithAllStaticItemsAtBaselineOffsetIsClean() {
    var g = SafetyGuard(
        baselines: [
            item("A", at: 0, width: 10, kind: .static),
            item("B", at: 10, width: 10, kind: .dynamic),
            item("C", at: 20, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("A", .found(offset: 0)),
            reading("B", .notFound(bestMismatch: 0.9)),
            reading("C", .found(offset: 0)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    let decision = g.assess(cap, presence: alwaysTrue)
    #expect(decision == .clean(info: []))
}

// MARK: - 2. Uniform shift

@Test func uniformShiftOfStaticsReportsShiftedButVerifiesDynamicAsNoHarm() {
    var g = SafetyGuard(
        baselines: [
            item("A", at: 0, width: 10, kind: .static),
            item("B", at: 10, width: 10, kind: .dynamic),
            item("C", at: 20, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("A", .found(offset: 3)),
            reading("B", .notFound(bestMismatch: 0.9)),
            reading("C", .found(offset: 3)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    let decision = g.assess(cap, presence: alwaysTrue)
    #expect(decision == .clean(info: [.shifted(id: "A", offset: 3), .shifted(id: "C", offset: 3)]))
}

// MARK: - 3. Non-uniform shift: dynamic unverifiable, suspect then stop

@Test func nonUniformShiftMakesDynamicUnverifiableThenStopsOnSecondCapture() {
    var g = SafetyGuard(
        baselines: [
            item("A", at: 0, width: 10, kind: .static),
            item("B", at: 10, width: 10, kind: .dynamic),
            item("C", at: 20, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("A", .found(offset: 0)),
            reading("B", .notFound(bestMismatch: 0.9)),
            reading("C", .found(offset: 5)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    let d1 = g.assess(cap, presence: alwaysTrue)
    #expect(d1 == .suspect(reasons: [.itemUnverifiable(id: "B")]))

    let cap2 = CaptureReading(time: 1, items: cap.items, protected: protectedOkAtZero, pill: nil)
    let d2 = g.assess(cap2, presence: alwaysTrue)
    #expect(d2 == .stop(reasons: [.itemUnverifiable(id: "B")]))
}

// MARK: - 4. Static notFound, anchors agree, presence false -> itemLost

@Test func staticNotFoundWithAgreeingAnchorsAndNoPresenceIsItemLost() {
    var g = singleItemGuard()
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .notFound(bestMismatch: 0.5))],
        protected: protectedOkAtZero,
        pill: nil
    )
    let decision = g.assess(cap, presence: alwaysFalse)
    #expect(decision == .suspect(reasons: [.itemLost(id: "A")]))
}

// Rule E's "otherwise -> itemLost" branch must also fire when the item's
// anchors DISAGREE (not just when they agree and presence is false), and
// presence must not even be consulted in that case.

@Test func staticNotFoundWithDisagreeingAnchorsIsItemLostWithoutConsultingPresence() {
    var g = SafetyGuard(
        baselines: [
            item("Y", at: 0, width: 10, kind: .static),
            item("A", at: 10, width: 10, kind: .static),
            item("Z", at: 20, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("Y", .found(offset: 0)),
            reading("A", .notFound(bestMismatch: 0.5)),
            // Z's offset (5) disagrees with Y's (0): |0 - 5| = 5 > anchorTolerance (1).
            reading("Z", .found(offset: 5)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    var presenceCallCount = 0
    let decision = g.assess(cap, presence: { _, _ in
        presenceCallCount += 1
        return true
    })
    #expect(decision == .suspect(reasons: [.itemLost(id: "A")]))
    #expect(presenceCallCount == 0)
}

// MARK: - 5. Static notFound + presence + agreeing anchors -> appearanceChanged,
// reclassified to dynamic on the NEXT capture only.

@Test func staticNotFoundWithPresenceAndAgreeingAnchorsAppearsChangedAndReclassifiesNextCaptureOnly() {
    var g = singleItemGuard()

    let cap1 = CaptureReading(
        time: 0,
        items: [reading("A", .notFound(bestMismatch: 0.1))],
        protected: protectedOkAtZero,
        pill: nil
    )
    let d1 = g.assess(cap1, presence: alwaysTrue)
    #expect(d1 == .clean(info: [.appearanceChanged(id: "A")]))
    #expect(g.baselines.first(where: { $0.id == "A" })?.kind == .dynamic)

    // Second capture: anchors now DISAGREE. If A were still (incorrectly)
    // treated as static this capture (bug: rule E), it would be checked by
    // its own .found(999) reading and give .clean(info: [.shifted(A, 999)]).
    // If correctly treated as dynamic (rule F), disagreement ->
    // itemUnverifiable (unknown), and the template result is ignored
    // entirely, which is why it is set to nonsense (999) on purpose.
    let displacedProtected = MarkerResult.unique(Span(lo: 11.5, hi: 21.5)) // mid 16.5, offset 1.5 (protectedTolerance 2 -> ok)
    let cap2 = CaptureReading(
        time: 1,
        items: [reading("A", .found(offset: 999))],
        protected: displacedProtected,
        pill: nil
    )
    let d2 = g.assess(cap2, presence: alwaysTrue)
    #expect(d2 == .suspect(reasons: [.itemUnverifiable(id: "A")]))
}

// Rule E's presence check must use the baseline span shifted by the anchors'
// COMMON offset, not the raw unshifted baseline span, when that offset is
// non-zero.

@Test func staticNotFoundPresenceIsCheckedAtTheSpanShiftedByTheCommonOffset() {
    var g = SafetyGuard(
        baselines: [
            item("Y1", at: 0, width: 10, kind: .static),
            item("M", at: 10, width: 10, kind: .static),
            item("Y2", at: 20, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("Y1", .found(offset: 1.0)),
            reading("M", .notFound(bestMismatch: 0.1)),
            // Anchors agree (|1.0 - 1.8| = 0.8 <= 1); common offset is the
            // right anchor's, 1.8.
            reading("Y2", .found(offset: 1.8)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    var captured: Span?
    let decision = g.assess(cap, presence: { id, span in
        if id == "M" { captured = span }
        return true
    })
    #expect(captured == Span(lo: 11.8, hi: 21.8))
    #expect(decision == .clean(info: [.appearanceChanged(id: "M"), .shifted(id: "Y2", offset: 1.8)]))
}

@Test func staticNotFoundIsItemLostWhenPresenceOnlyMatchesTheUnshiftedSpan() {
    var g = SafetyGuard(
        baselines: [
            item("Y1", at: 0, width: 10, kind: .static),
            item("M", at: 10, width: 10, kind: .static),
            item("Y2", at: 20, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("Y1", .found(offset: 1.0)),
            reading("M", .notFound(bestMismatch: 0.1)),
            reading("Y2", .found(offset: 1.8)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    // Presence is true only at M's OLD (unshifted) spot. If the guard wrongly
    // checked presence there instead of at the shifted span, this would be
    // read as the item's colour having reappeared in place.
    let decision = g.assess(cap, presence: { id, span in
        id == "M" && span == Span(lo: 10, hi: 20)
    })
    #expect(decision == .suspect(reasons: [.itemLost(id: "M")]))
}

// MARK: - 6. Dynamic leftmost anchored by P

@Test func dynamicLeftmostAnchoredByProtectedWhenProtectedOk() {
    var g = SafetyGuard(
        baselines: [
            item("X", at: 0, width: 10, kind: .dynamic),
            item("Y", at: 10, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("X", .notFound(bestMismatch: 0.1)),
            reading("Y", .found(offset: 0)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    var captured: (String, Span)?
    let decision = g.assess(cap, presence: { id, span in
        captured = (id, span)
        return true
    })
    #expect(decision == .clean(info: []))
    #expect(captured?.0 == "X")
    #expect(captured?.1 == Span(lo: 0, hi: 10))
}

@Test func dynamicLeftmostAnchoredByProtectedWhenProtectedLostProducesHarmAndUnknownTogether() {
    var g = SafetyGuard(
        baselines: [
            item("X", at: 0, width: 10, kind: .dynamic),
            item("Y", at: 10, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("X", .notFound(bestMismatch: 0.1)),
            reading("Y", .found(offset: 0)),
        ],
        protected: .absent,
        pill: nil
    )
    let decision = g.assess(cap, presence: alwaysTrue)
    #expect(decision == .suspect(reasons: [.protectedLost, .itemUnverifiable(id: "X")]))
}

// MARK: - 7. Dynamic rightmost anchored by the screen edge

@Test func dynamicRightmostAnchoredByScreenEdge() {
    var g = SafetyGuard(
        baselines: [
            item("Y", at: 0, width: 10, kind: .static),
            item("X", at: 10, width: 10, kind: .dynamic),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("Y", .found(offset: 0)),
            reading("X", .notFound(bestMismatch: 0.1)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    var captured: (String, Span)?
    let decision = g.assess(cap, presence: { id, span in
        captured = (id, span)
        return true
    })
    #expect(decision == .clean(info: []))
    #expect(captured?.0 == "X")
    #expect(captured?.1 == Span(lo: 10, hi: 20))
}
