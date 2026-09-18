// Protected marker sub-cases (absent/ambiguous/displaced/tolerance
// boundaries), pill visibility cases, and finding ordering.
import Testing
@testable import SafeWidthCore

// MARK: - 8/9/10/11. Protected marker sub-cases

@Test func protectedAbsentIsHarm() {
    var g = singleItemGuard()
    let cap = CaptureReading(time: 0, items: [reading("A", .found(offset: 0))], protected: .absent, pill: nil)
    #expect(g.assess(cap, presence: alwaysTrue) == .suspect(reasons: [.protectedLost]))
}

@Test func protectedAmbiguousIsHarm() {
    var g = singleItemGuard()
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .found(offset: 0))],
        protected: .ambiguous([Span(lo: 9, hi: 11), Span(lo: 19, hi: 21)]),
        pill: nil
    )
    #expect(g.assess(cap, presence: alwaysTrue) == .suspect(reasons: [.protectedLost]))
}

@Test func protectedDisplacedBeyondToleranceIsHarm() {
    var g = singleItemGuard()
    // mid 25, expected mid 15, diff 10 > tolerance 2
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .found(offset: 0))],
        protected: .unique(Span(lo: 20, hi: 30)),
        pill: nil
    )
    #expect(g.assess(cap, presence: alwaysTrue) == .suspect(reasons: [.protectedLost]))
}

@Test func protectedDisplacedExactlyAtToleranceBoundaryIsOk() {
    var g = singleItemGuard()
    // mid 17, expected mid 15, diff 2 == tolerance 2 -> ok (<=)
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .found(offset: 0))],
        protected: .unique(Span(lo: 12, hi: 22)),
        pill: nil
    )
    #expect(g.assess(cap, presence: alwaysTrue) == .clean(info: []))
}

// Rule A's tolerance check uses abs(), so displacement to the LEFT of
// expected must be caught too, not just to the right (every other test here
// displaces P to the right).

@Test func protectedDisplacedLeftBeyondToleranceIsHarm() {
    var g = singleItemGuard()
    // mid 5, expected mid 15, diff -10, |−10| = 10 > tolerance 2.
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .found(offset: 0))],
        protected: .unique(Span(lo: 0, hi: 10)),
        pill: nil
    )
    #expect(g.assess(cap, presence: alwaysTrue) == .suspect(reasons: [.protectedLost]))
}

@Test func protectedDisplacedLeftExactlyAtToleranceBoundaryIsOk() {
    var g = singleItemGuard()
    // mid 13, expected mid 15, diff -2, |−2| = 2 == tolerance 2 -> ok (<=)
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .found(offset: 0))],
        protected: .unique(Span(lo: 8, hi: 18)),
        pill: nil
    )
    #expect(g.assess(cap, presence: alwaysTrue) == .clean(info: []))
}

// Rule C's offset is `s.mid - protectedExpected.mid` (not the other way
// round). Pin the sign using P as a leftmost dynamic item's anchor: a +1
// displacement must AGREE with a right anchor at +1, and a mirrored -1
// displacement must DISAGREE with that same +1 right anchor.

@Test func leftmostDynamicAgreesWithARightAnchorWhenProtectedIsDisplacedInTheSameDirection() {
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
            reading("Y", .found(offset: 1)),
        ],
        // mid 16, expected mid 15, offset = 16 - 15 = +1.
        protected: .unique(Span(lo: 11, hi: 21)),
        pill: nil
    )
    let decision = g.assess(cap, presence: alwaysTrue)
    #expect(decision == .clean(info: []))
}

@Test func leftmostDynamicDisagreesWithARightAnchorWhenProtectedIsDisplacedInTheOppositeDirection() {
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
            reading("Y", .found(offset: 1)),
        ],
        // mid 14, expected mid 15, offset = 14 - 15 = -1. If the subtraction
        // were flipped (expected.mid - s.mid), this would read as +1 and
        // wrongly agree with Y's +1.
        protected: .unique(Span(lo: 9, hi: 19)),
        pill: nil
    )
    let decision = g.assess(cap, presence: alwaysTrue)
    #expect(decision == .suspect(reasons: [.itemUnverifiable(id: "X")]))
}

// MARK: - Pill

@Test func pillHiddenIsHarm() {
    var g = singleItemGuard()
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .found(offset: 0))],
        protected: protectedOkAtZero,
        pill: PillReading(axPresent: true, pixelPresent: false)
    )
    #expect(g.assess(cap, presence: alwaysTrue) == .suspect(reasons: [.pillHidden]))
}

@Test func pillHarmlessWhenBothAbsent() {
    var g = singleItemGuard()
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .found(offset: 0))],
        protected: protectedOkAtZero,
        pill: PillReading(axPresent: false, pixelPresent: false)
    )
    #expect(g.assess(cap, presence: alwaysTrue) == .clean(info: []))
}

@Test func pillHarmlessWhenAxAbsentButPixelPresent() {
    var g = singleItemGuard()
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .found(offset: 0))],
        protected: protectedOkAtZero,
        pill: PillReading(axPresent: false, pixelPresent: true)
    )
    #expect(g.assess(cap, presence: alwaysTrue) == .clean(info: []))
}

@Test func pillHarmlessWhenBothPresent() {
    var g = singleItemGuard()
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .found(offset: 0))],
        protected: protectedOkAtZero,
        pill: PillReading(axPresent: true, pixelPresent: true)
    )
    #expect(g.assess(cap, presence: alwaysTrue) == .clean(info: []))
}

// Rule H: protected first, then items in baseline order, then the pill last.
@Test func findingsAreOrderedProtectedThenItemsThenPill() {
    var g = singleItemGuard()
    // A: notFound with P absent, so its anchors are (nil, screen edge 0) ->
    // disagree -> itemLost(A), regardless of presence.
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .notFound(bestMismatch: 0.5))],
        protected: .absent,
        pill: PillReading(axPresent: true, pixelPresent: false)
    )
    let decision = g.assess(cap, presence: alwaysTrue)
    #expect(decision == .suspect(reasons: [.protectedLost, .itemLost(id: "A"), .pillHidden]))
}
