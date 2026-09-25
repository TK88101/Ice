import Testing
@testable import C1Core

/// Round 4 item 2: "the latching capturer's assess path also runs the
/// keyed untemplated check on every capture ... a missing/moved/
/// unenumerated item trips the latch like a templated miss." This is the
/// pure merge: folding `UntemplatedOwnerWatch.check`'s result into
/// whatever the templated (pixel) assessment already found, before either
/// reaches `Latch.observe`.
@Suite("LatchObservationMerge")
struct LatchObservationMergeTests {
    @Test("no untemplated failures -> the templated observation passes through unchanged")
    func noFailuresPassesThrough() {
        let templated = Latch.Observation(missingOwnerItems: ["owner-1"], protectedMissing: true)
        let merged = LatchObservationMerge.merge(templated: templated, untemplated: [])
        #expect(merged == templated)
    }

    @Test("an untemplated item missing is added to missingOwnerItems, exactly like a templated miss")
    func untemplatedMissingIsAdded() {
        let templated = Latch.Observation()
        let merged = LatchObservationMerge.merge(templated: templated, untemplated: [.missing("owner-untemplated-1")])
        #expect(merged.missingOwnerItems == ["owner-untemplated-1"])
    }

    @Test("an untemplated item that moved is added to missingOwnerItems too")
    func untemplatedMovedIsAdded() {
        let templated = Latch.Observation()
        let merged = LatchObservationMerge.merge(templated: templated, untemplated: [.moved("owner-untemplated-2")])
        #expect(merged.missingOwnerItems == ["owner-untemplated-2"])
    }

    @Test("templated and untemplated misses are unioned, sorted, without duplicates")
    func templatedAndUntemplatedUnioned() {
        let templated = Latch.Observation(missingOwnerItems: ["owner-a", "owner-b"])
        let merged = LatchObservationMerge.merge(templated: templated, untemplated: [.missing("owner-c"), .moved("owner-a")])
        #expect(merged.missingOwnerItems == ["owner-a", "owner-b", "owner-c"])
    }

    @Test("every other templated field (protectedMissing, residualInkChanged, foldAppearedWithoutExpansion, captureFailed) is preserved untouched")
    func otherFieldsPreserved() {
        let templated = Latch.Observation(protectedMissing: true, residualInkChanged: true, foldAppearedWithoutExpansion: true, captureFailed: true)
        let merged = LatchObservationMerge.merge(templated: templated, untemplated: [])
        #expect(merged.protectedMissing)
        #expect(merged.residualInkChanged)
        #expect(merged.foldAppearedWithoutExpansion)
        #expect(merged.captureFailed)
    }

    @Test("untemplated == nil (the keyed read itself failed or came back late) sets captureFailed, an immediate abort like a failed pixel capture")
    func nilUntemplatedSetsCaptureFailed() {
        let templated = Latch.Observation(missingOwnerItems: ["owner-1"])
        let merged = LatchObservationMerge.merge(templated: templated, untemplated: nil)
        #expect(merged.captureFailed)
        // Whatever the templated pass already found is still carried.
        #expect(merged.missingOwnerItems == ["owner-1"])
    }

    @Test("captureFailed from a nil keyed read still trips the latch when fed through observe(_:)")
    func nilUntemplatedActuallyTripsTheLatch() {
        let merged = LatchObservationMerge.merge(templated: .init(), untemplated: nil)
        var latch = Latch()
        #expect(latch.observe(merged) == .captureFailed)
    }

    @Test("a missing untemplated item actually trips the latch when fed through observe(_:)")
    func missingUntemplatedActuallyTripsTheLatch() {
        let merged = LatchObservationMerge.merge(templated: .init(), untemplated: [.missing("owner-untemplated-1")])
        var latch = Latch()
        #expect(latch.observe(merged) == .ownerItemMissing("owner-untemplated-1"))
    }
}
