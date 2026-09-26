import Testing
@testable import C1Core

/// Amendment v9, "Gate": the pure decision behind the post-launch placement
/// gate. `check` now requires the internal order Target < spacer <
/// Protected as well as every on-bar owner item right of Protected
/// (crosscheck-rework8.json #1: the old gate only ever compared the
/// rightmost helper, so a misordered layout -- Target packed between the
/// spacer and Protected -- could pass the gate and fail later with a
/// generic, unexplained reason); a helper missing a frame (off the bar, or
/// folded) is its own distinct reason too, never lumped into "owner items
/// left." `materiallyAgree` is the two-consecutive-reads check Amendment v9
/// also requires before the gate decides at all.
@Suite("PlacementGate")
struct PlacementGateTests {
    private func reading(target: Double?, spacer: Double?, protected: Double?, owners: [Double]) -> PlacementGate.Reading {
        .init(targetMinX: target, spacerMinX: spacer, protectedMinX: protected, onBarOwnerMinXs: owners)
    }

    // MARK: - check

    @Test("no on-bar owner items at all -> passes (nil)")
    func noOwnerItems() {
        #expect(PlacementGate.check(reading(target: 150, spacer: 190, protected: 230, owners: [])) == nil)
    }

    @Test("every on-bar owner item right of Protected -> passes (nil)")
    func ownersAllRight() {
        #expect(PlacementGate.check(reading(target: 150, spacer: 190, protected: 230, owners: [250, 270])) == nil)
    }

    @Test("one owner item left of Protected -> fails with ownerItemsLeft(count: 1)")
    func oneOwnerLeft() {
        #expect(PlacementGate.check(reading(target: 150, spacer: 190, protected: 230, owners: [100, 250])) == .ownerItemsLeft(count: 1))
    }

    @Test("three owner items left of Protected -> fails with ownerItemsLeft(count: 3) (the recorded live case)")
    func threeOwnersLeft() {
        #expect(PlacementGate.check(reading(target: 1200.0, spacer: 1220.5, protected: 1247.0, owners: [1050.5, 1084.0, 1114.5])) == .ownerItemsLeft(count: 3))
    }

    @Test("an owner item exactly at Protected's own minX (a tie) does not count as left of it")
    func tieDoesNotCount() {
        #expect(PlacementGate.check(reading(target: 150, spacer: 190, protected: 230, owners: [230, 250])) == nil)
    }

    @Test("only owner items left of Protected are counted -- one left, one right")
    func mixedLeftAndRight() {
        #expect(PlacementGate.check(reading(target: 150, spacer: 190, protected: 230, owners: [100, 250])) == .ownerItemsLeft(count: 1))
    }

    @Test("any helper missing a frame (off the bar or folded) fails closed with helperOffBarOrFolded, distinct from owner order")
    func missingHelperFrame() {
        #expect(PlacementGate.check(reading(target: nil, spacer: 190, protected: 230, owners: [])) == .helperOffBarOrFolded)
        #expect(PlacementGate.check(reading(target: 150, spacer: nil, protected: 230, owners: [])) == .helperOffBarOrFolded)
        #expect(PlacementGate.check(reading(target: 150, spacer: 190, protected: nil, owners: [100])) == .helperOffBarOrFolded)
        #expect(PlacementGate.check(reading(target: nil, spacer: nil, protected: nil, owners: [])) == .helperOffBarOrFolded)
    }

    @Test("Target packed between the spacer and Protected is a misorder, distinct from owner order (crosscheck-rework8.json #1)")
    func targetBetweenSpacerAndProtectedIsMisorder() {
        #expect(PlacementGate.check(reading(target: 200, spacer: 190, protected: 230, owners: [])) == .misorder(targetMinX: 200, spacerMinX: 190, protectedMinX: 230))
    }

    @Test("spacer at or right of Protected is a misorder")
    func spacerNotLeftOfProtectedIsMisorder() {
        #expect(PlacementGate.check(reading(target: 150, spacer: 230, protected: 230, owners: [])) == .misorder(targetMinX: 150, spacerMinX: 230, protectedMinX: 230))
    }

    // MARK: - materiallyAgree

    @Test("two identical readings agree")
    func identicalReadingsAgree() {
        let a = reading(target: 150, spacer: 190, protected: 230, owners: [270, 300])
        #expect(PlacementGate.materiallyAgree(a, a))
    }

    @Test("readings within tolerance agree, regardless of the owner minXs' own order")
    func withinToleranceAgreesRegardlessOfOwnerOrder() {
        let a = reading(target: 150.0, spacer: 190.2, protected: 230.0, owners: [300.0, 270.4])
        let b = reading(target: 150.4, spacer: 190.0, protected: 229.6, owners: [270.0, 300.3])
        #expect(PlacementGate.materiallyAgree(a, b, tolerancePt: 1.0))
    }

    @Test("a helper minX difference past tolerance disagrees")
    func helperPastToleranceDisagrees() {
        let a = reading(target: 150, spacer: 190, protected: 230, owners: [])
        let b = reading(target: 155, spacer: 190, protected: 230, owners: [])
        #expect(!PlacementGate.materiallyAgree(a, b, tolerancePt: 1.0))
    }

    @Test("a differing owner-item count disagrees")
    func differingOwnerCountDisagrees() {
        let a = reading(target: 150, spacer: 190, protected: 230, owners: [270])
        let b = reading(target: 150, spacer: 190, protected: 230, owners: [270, 300])
        #expect(!PlacementGate.materiallyAgree(a, b))
    }

    @Test("one reading missing a helper frame while the other has it disagrees")
    func oneMissingHelperDisagrees() {
        let a = reading(target: nil, spacer: 190, protected: 230, owners: [])
        let b = reading(target: 150, spacer: 190, protected: 230, owners: [])
        #expect(!PlacementGate.materiallyAgree(a, b))
    }

    @Test("both readings missing the same helper frame agrees")
    func bothMissingSameHelperAgrees() {
        let a = reading(target: nil, spacer: 190, protected: 230, owners: [])
        let b = reading(target: nil, spacer: 190, protected: 230, owners: [])
        #expect(PlacementGate.materiallyAgree(a, b))
    }
}
