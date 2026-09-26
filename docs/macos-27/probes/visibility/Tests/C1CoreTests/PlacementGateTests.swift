import Testing
@testable import C1Core

/// Amendment v8, "Placement gate" (first bullet's own companion piece):
/// section 2's premise -- "each new item lands at the left end" -- is false
/// on the owner's bar (a fourth cross-check found 1-3 owner items drawn left
/// of the helpers in every recorded run). Right after the launches, before
/// any baseline and before any `length`, discovery must show Target, the
/// spacer and Protected each left of every on-bar owner item; otherwise the
/// run ends INCONCLUSIVE with the count of owner items still found left of
/// them, never a safety stop. This is the pure decision -- `helperMinXs`/
/// `onBarOwnerMinXs` are already-filtered (`.onBar` only, per the parked-item
/// fix) minX readings; the stage (`StageC1`) supplies them from one
/// discovery pass and reaps/records/aborts around this answer.
@Suite("PlacementGate")
struct PlacementGateTests {
    @Test("no on-bar owner items at all -> passes (nil)")
    func noOwnerItems() {
        #expect(PlacementGate.check(helperMinXs: [150, 190, 230], onBarOwnerMinXs: []) == nil)
    }

    @Test("every on-bar owner item right of every helper -> passes (nil)")
    func ownersAllRight() {
        #expect(PlacementGate.check(helperMinXs: [150, 190, 230], onBarOwnerMinXs: [250, 270]) == nil)
    }

    @Test("one owner item left of the rightmost helper -> fails with count 1")
    func oneOwnerLeft() {
        #expect(PlacementGate.check(helperMinXs: [150, 190, 230], onBarOwnerMinXs: [100, 250]) == 1)
    }

    @Test("three owner items left of the rightmost helper -> fails with count 3 (the recorded live case)")
    func threeOwnersLeft() {
        #expect(PlacementGate.check(helperMinXs: [1220.5, 1200.0, 1247.0], onBarOwnerMinXs: [1050.5, 1084.0, 1114.5]) == 3)
    }

    @Test("an owner item exactly at the rightmost helper's minX (a tie) does not count as left of it")
    func tieDoesNotCount() {
        #expect(PlacementGate.check(helperMinXs: [150, 190, 230], onBarOwnerMinXs: [230, 250]) == nil)
    }

    @Test("only owner items left of the rightmost helper are counted -- one left, one right")
    func mixedLeftAndRight() {
        #expect(PlacementGate.check(helperMinXs: [150, 190, 230], onBarOwnerMinXs: [100, 250]) == 1)
    }

    @Test("no helpers at all (none launched or none with a frame) -- every on-bar owner item counts as left, fail closed")
    func noHelpers() {
        #expect(PlacementGate.check(helperMinXs: [], onBarOwnerMinXs: [100, 250]) == 2)
        #expect(PlacementGate.check(helperMinXs: [], onBarOwnerMinXs: []) == nil)
    }
}
