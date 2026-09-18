// Static found shift boundaries, SafetyGuard init (baseline exposure
// and precondition traps), and the RoomCheck/Deadman watchdogs.
import Testing
@testable import SafeWidthCore

// MARK: - Static found: shifted boundary, and never harm regardless of magnitude

@Test func staticFoundExactlyAtAnchorToleranceBoundaryIsNotShifted() {
    var g = singleItemGuard()
    let cap = CaptureReading(time: 0, items: [reading("A", .found(offset: 1))], protected: protectedOkAtZero, pill: nil)
    #expect(g.assess(cap, presence: alwaysTrue) == .clean(info: []))
}

@Test func staticFoundBeyondToleranceIsShiftedButNeverHarm() {
    var g = singleItemGuard()
    let cap = CaptureReading(time: 0, items: [reading("A", .found(offset: 50))], protected: protectedOkAtZero, pill: nil)
    #expect(g.assess(cap, presence: alwaysTrue) == .clean(info: [.shifted(id: "A", offset: 50)]))
}

// Rule D's tolerance check uses abs(), so a shift to the left must be
// reported too, not just to the right (every other test here shifts right).
@Test func staticFoundNegativeOffsetBeyondToleranceIsShiftedButNeverHarm() {
    var g = singleItemGuard()
    let cap = CaptureReading(time: 0, items: [reading("A", .found(offset: -5))], protected: protectedOkAtZero, pill: nil)
    #expect(g.assess(cap, presence: alwaysTrue) == .clean(info: [.shifted(id: "A", offset: -5)]))
}

// MARK: - init exposes baselines

@Test func initExposesTheInitialBaselines() {
    let baselines = [item("A", at: 0, width: 10, kind: .static)]
    let g = SafetyGuard(
        baselines: baselines,
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1
    )
    #expect(g.baselines == baselines)
}

// MARK: - init validates its inputs, so bad state crashes at setup instead
// of mid-experiment inside assess.

@Test func initRejectsPersistenceBelowOne() async {
    await #expect(processExitsWith: .failure) {
        _ = SafetyGuard(
            baselines: [item("A", at: 0, width: 10, kind: .static)],
            protectedExpected: protectedExpected,
            protectedTolerance: 2,
            anchorTolerance: 1,
            persistence: 0
        )
    }
}

@Test func initRejectsDuplicateBaselineIds() async {
    await #expect(processExitsWith: .failure) {
        _ = SafetyGuard(
            baselines: [
                item("A", at: 0, width: 10, kind: .static),
                item("A", at: 10, width: 10, kind: .static),
            ],
            protectedExpected: protectedExpected,
            protectedTolerance: 2,
            anchorTolerance: 1
        )
    }
}

@Test func initRejectsANegativeWidthBaselineInsteadOfCrashingLaterInAssess() async {
    await #expect(processExitsWith: .failure) {
        _ = SafetyGuard(
            baselines: [item("A", at: 0, width: -5, kind: .static)],
            protectedExpected: protectedExpected,
            protectedTolerance: 2,
            anchorTolerance: 1
        )
    }
}

@Test func initRejectsANonFiniteAnchorTolerance() async {
    await #expect(processExitsWith: .failure) {
        _ = SafetyGuard(
            baselines: [item("A", at: 0, width: 10, kind: .static)],
            protectedExpected: protectedExpected,
            protectedTolerance: 2,
            anchorTolerance: .nan
        )
    }
}

@Test func initRejectsANegativeProtectedTolerance() async {
    await #expect(processExitsWith: .failure) {
        _ = SafetyGuard(
            baselines: [item("A", at: 0, width: 10, kind: .static)],
            protectedExpected: protectedExpected,
            protectedTolerance: -1,
            anchorTolerance: 1
        )
    }
}

// MARK: - RoomCheck

@Test func roomCheckAtExactToleranceBoundaryIsNotDrifted() {
    #expect(RoomCheck.drifted(before: 10, after: 12, tolerance: 2) == false)
}

@Test func roomCheckJustBeyondToleranceIsDrifted() {
    #expect(RoomCheck.drifted(before: 10, after: 12.01, tolerance: 2) == true)
}

@Test func roomCheckDetectsDriftInTheNegativeDirectionToo() {
    #expect(RoomCheck.drifted(before: 10, after: 7.4, tolerance: 2) == true)
}

// MARK: - Deadman

@Test func deadmanAtRestNeverExpiresNoMatterHowMuchTimePassed() {
    let d = Deadman(limit: 5, start: 0)
    #expect(d.expired(at: 10_000, spacerAtRest: true) == false)
}

@Test func deadmanExpiresStrictlyAfterTheLimitNotAtIt() {
    let d = Deadman(limit: 5, start: 0)
    #expect(d.expired(at: 5, spacerAtRest: false) == false)
    #expect(d.expired(at: 5.0001, spacerAtRest: false) == true)
}

@Test func deadmanNoteCleanAdvancesLastClean() {
    var d = Deadman(limit: 5, start: 0)
    d.noteClean(at: 10)
    #expect(d.expired(at: 14.9, spacerAtRest: false) == false)
    #expect(d.expired(at: 15.1, spacerAtRest: false) == true)
}

@Test func deadmanNoteCleanWithAnOlderTimeDoesNotMoveLastCleanBack() {
    var d = Deadman(limit: 5, start: 10)
    d.noteClean(at: 3)
    // If lastClean had moved back to 3, this would already be expired (14-3=11>5).
    #expect(d.expired(at: 14, spacerAtRest: false) == false)
    #expect(d.expired(at: 16, spacerAtRest: false) == true)
}

// A non-finite input must crash loudly rather than silently disarm the
// watchdog: Double.max(.nan, x) is .nan, so a NaN limit or lastClean would
// otherwise make `expired` return false forever.

@Test func deadmanInitRejectsANonFiniteLimit() async {
    await #expect(processExitsWith: .failure) {
        _ = Deadman(limit: .nan, start: 0)
    }
}

@Test func deadmanInitRejectsANegativeLimit() async {
    await #expect(processExitsWith: .failure) {
        _ = Deadman(limit: -1, start: 0)
    }
}

@Test func deadmanInitRejectsANonFiniteStart() async {
    await #expect(processExitsWith: .failure) {
        _ = Deadman(limit: 5, start: .infinity)
    }
}

@Test func deadmanNoteCleanRejectsANonFiniteTime() async {
    await #expect(processExitsWith: .failure) {
        var d = Deadman(limit: 5, start: 0)
        d.noteClean(at: .nan)
    }
}

@Test func deadmanExpiredRejectsANonFiniteNowWhenNotAtRest() async {
    await #expect(processExitsWith: .failure) {
        let d = Deadman(limit: 5, start: 0)
        _ = d.expired(at: .nan, spacerAtRest: false)
    }
}

@Test func deadmanExpiredIgnoresANonFiniteNowWhenSpacerIsAtRest() {
    // spacerAtRest short-circuits before `now` is ever used, so a bad `now`
    // must not crash a caller who is only polling while at rest.
    let d = Deadman(limit: 5, start: 0)
    #expect(d.expired(at: .nan, spacerAtRest: true) == false)
}
