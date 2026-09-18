// Reading matching (missing/duplicate/out-of-order readings by id) and
// the harm/unknown persistence-streak behaviour.
import Testing
@testable import SafeWidthCore

// MARK: - Missing reading -> unverifiable, regardless of kind

@Test func missingReadingForStaticItemIsUnverifiable() {
    var g = singleItemGuard(kind: .static)
    let cap = CaptureReading(time: 0, items: [], protected: protectedOkAtZero, pill: nil)
    #expect(g.assess(cap, presence: alwaysTrue) == .suspect(reasons: [.itemUnverifiable(id: "A")]))
}

@Test func missingReadingForDynamicItemIsUnverifiable() {
    var g = singleItemGuard(kind: .dynamic)
    let cap = CaptureReading(time: 0, items: [], protected: protectedOkAtZero, pill: nil)
    #expect(g.assess(cap, presence: alwaysTrue) == .suspect(reasons: [.itemUnverifiable(id: "A")]))
}

// Readings are matched to baselines by id (rule B), not by their position in
// the `items` array.

@Test func missingReadingForAMiddleBaselineIsMatchedByIdNotPosition() {
    var g = SafetyGuard(
        baselines: [
            item("A", at: 0, width: 10, kind: .static),
            item("B", at: 10, width: 10, kind: .static),
            item("C", at: 20, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    // B has no reading at all; if readings were matched by position, C's
    // reading would land on B's slot and mask the gap.
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .found(offset: 0)), reading("C", .found(offset: 0))],
        protected: protectedOkAtZero,
        pill: nil
    )
    #expect(g.assess(cap, presence: alwaysTrue) == .suspect(reasons: [.itemUnverifiable(id: "B")]))
}

@Test func readingsSuppliedOutOfBaselineOrderAreStillMatchedByTheirOwnId() {
    var g = SafetyGuard(
        baselines: [
            item("A", at: 0, width: 10, kind: .static),
            item("B", at: 10, width: 10, kind: .static),
            item("C", at: 20, width: 10, kind: .static),
        ],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    // Readings arrive shuffled, and only C's is shifted. If they were matched
    // by array position rather than id, the shift would land on A instead.
    let cap = CaptureReading(
        time: 0,
        items: [
            reading("C", .found(offset: 5)),
            reading("A", .found(offset: 0)),
            reading("B", .found(offset: 0)),
        ],
        protected: protectedOkAtZero,
        pill: nil
    )
    #expect(g.assess(cap, presence: alwaysTrue) == .clean(info: [.shifted(id: "C", offset: 5)]))
}

// Rule B assumes exactly one reading per baseline id. More than one reading
// for the same id is ambiguous input; the guard must not silently pick one
// (here, the notFound one lost to a later found(0) by "last one wins" and
// the capture came back clean) and instead treats it as unverifiable, same
// as no reading at all.
@Test func duplicateReadingsForTheSameIdAreItemUnverifiableNotSilentlyResolved() {
    var g = singleItemGuard()
    let cap = CaptureReading(
        time: 0,
        items: [reading("A", .notFound(bestMismatch: 0.9)), reading("A", .found(offset: 0))],
        protected: protectedOkAtZero,
        pill: nil
    )
    #expect(g.assess(cap, presence: alwaysFalse) == .suspect(reasons: [.itemUnverifiable(id: "A")]))
}

// MARK: - Persistence

@Test func harmAndUnknownInTheSameCaptureBothCountTowardBothStreaksUntilUnknownStops() {
    var g = singleItemGuard()
    let mixedCapture = { (time: Double) in
        CaptureReading(time: time, items: [], protected: .absent, pill: nil)
    }
    let d1 = g.assess(mixedCapture(0), presence: alwaysTrue)
    #expect(d1 == .suspect(reasons: [.protectedLost, .itemUnverifiable(id: "A")]))

    // A second consecutive mixed capture pushes both counters to the
    // persistence threshold (2). Unknown must win over harm: .stop, not
    // .restore.
    let d2 = g.assess(mixedCapture(1), presence: alwaysTrue)
    #expect(d2 == .stop(reasons: [.protectedLost, .itemUnverifiable(id: "A")]))
}

@Test func mixedCaptureFollowedByAHarmOnlyCaptureRestoresBecauseTheHarmCounterCountedTheMixedCapture() {
    var g = singleItemGuard()
    let d1 = g.assess(CaptureReading(time: 0, items: [], protected: .absent, pill: nil), presence: alwaysTrue)
    #expect(d1 == .suspect(reasons: [.protectedLost, .itemUnverifiable(id: "A")]))

    // Harm-only capture: unknownStreak resets to 0, but harmStreak must have
    // counted the previous mixed capture too, reaching 2 -> restore.
    let d2 = g.assess(harmOnlyReading(time: 1), presence: alwaysTrue)
    #expect(d2 == .restore(reasons: [.protectedLost]))
}

@Test func persistenceSuspectThenRestore() {
    var g = singleItemGuard()
    let d1 = g.assess(harmOnlyReading(time: 0), presence: alwaysTrue)
    #expect(d1 == .suspect(reasons: [.protectedLost]))
    let d2 = g.assess(harmOnlyReading(time: 1), presence: alwaysTrue)
    #expect(d2 == .restore(reasons: [.protectedLost]))
}

@Test func cleanCaptureInBetweenResetsTheHarmStreak() {
    var g = singleItemGuard()
    _ = g.assess(harmOnlyReading(time: 0), presence: alwaysTrue)
    let dClean = g.assess(cleanReading(time: 1), presence: alwaysTrue)
    #expect(dClean == .clean(info: []))
    let d3 = g.assess(harmOnlyReading(time: 2), presence: alwaysTrue)
    #expect(d3 == .suspect(reasons: [.protectedLost]))
}

@Test func persistenceOneTriggersImmediateRestoreOnHarm() {
    var g = singleItemGuard(persistence: 1)
    let d = g.assess(harmOnlyReading(time: 0), presence: alwaysTrue)
    #expect(d == .restore(reasons: [.protectedLost]))
}

@Test func persistenceOneTriggersImmediateStopOnUnknown() {
    var g = singleItemGuard(persistence: 1)
    let d = g.assess(unknownOnlyReading(time: 0), presence: alwaysTrue)
    #expect(d == .stop(reasons: [.itemUnverifiable(id: "A")]))
}

@Test func unknownStreakIsResetByAHarmOnlyCaptureInBetween() {
    var g = singleItemGuard()
    let d1 = g.assess(unknownOnlyReading(time: 0), presence: alwaysTrue)
    #expect(d1 == .suspect(reasons: [.itemUnverifiable(id: "A")]))
    let d2 = g.assess(harmOnlyReading(time: 1), presence: alwaysTrue)
    #expect(d2 == .suspect(reasons: [.protectedLost]))
    // Unknown streak was reset to 0 by the harm-only capture, so this is 1
    // again, not 2 -> suspect, not stop.
    let d3 = g.assess(unknownOnlyReading(time: 2), presence: alwaysTrue)
    #expect(d3 == .suspect(reasons: [.itemUnverifiable(id: "A")]))
}

@Test func unknownStreakIsResetByACleanCaptureInBetween() {
    var g = singleItemGuard()
    let d1 = g.assess(unknownOnlyReading(time: 0), presence: alwaysTrue)
    #expect(d1 == .suspect(reasons: [.itemUnverifiable(id: "A")]))
    let dClean = g.assess(cleanReading(time: 1), presence: alwaysTrue)
    #expect(dClean == .clean(info: []))
    // Reset to 1 again, not 2 -> suspect, not stop.
    let d3 = g.assess(unknownOnlyReading(time: 2), presence: alwaysTrue)
    #expect(d3 == .suspect(reasons: [.itemUnverifiable(id: "A")]))
}

@Test func harmStreakIsResetByAnUnknownOnlyCaptureInBetween() {
    var g = singleItemGuard()
    let d1 = g.assess(harmOnlyReading(time: 0), presence: alwaysTrue)
    #expect(d1 == .suspect(reasons: [.protectedLost]))
    let d2 = g.assess(unknownOnlyReading(time: 1), presence: alwaysTrue)
    #expect(d2 == .suspect(reasons: [.itemUnverifiable(id: "A")]))
    // Harm streak was reset to 0 by the unknown-only capture, so this is 1
    // again, not 2 -> suspect, not restore.
    let d3 = g.assess(harmOnlyReading(time: 2), presence: alwaysTrue)
    #expect(d3 == .suspect(reasons: [.protectedLost]))
}
