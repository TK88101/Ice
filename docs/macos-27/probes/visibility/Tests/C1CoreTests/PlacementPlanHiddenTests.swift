// C2 T3 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 1): the placement plan
// for k hidden items -- C1's k = 1 plan is unchanged.
import Testing
@testable import C1Core

@Suite("PlacementPlanHidden")
struct PlacementPlanHiddenTests {
    let pitch = 28.0
    let spacerPitch = 32.0

    private func plan(extra: Int, barRightEdge: Double = 1728, notch: Double = 956.5) -> PlacementPlan.Outcome {
        PlacementPlan.plan(owners: [], barRightEdge: barRightEdge, notchRightEdge: notch, targetOccupiedPt: pitch, spacerOccupiedPt: spacerPitch, protectedOccupiedPt: pitch, extraHiddenCount: extra)
    }

    @Test("k = 3: Target, two extra hidden items, the spacer and Protected, left to right at the real pitch")
    func threeHiddenLayout() throws {
        guard case .planned(let result) = plan(extra: 2) else { throw PlanFailure.refused }
        #expect(result.extraHiddenMinXs == [result.targetMinX + pitch, result.targetMinX + 2 * pitch])
        #expect(result.spacerMinX == result.targetMinX + 3 * pitch)
        #expect(result.protectedMinX == result.spacerMinX + spacerPitch)
        #expect(result.protectedMinX + pitch == 1728 - PlacementPlan.marginPt)
    }

    @Test("k = 3: sort keys descend left to right, Protected lowest at floor + step")
    func threeHiddenSortKeys() throws {
        guard case .planned(let result) = plan(extra: 2) else { throw PlanFailure.refused }
        let step = PlacementPlan.sortKeyStepPt
        let floor = result.floorValue
        #expect(result.protectedPreferredPosition == floor + step)
        #expect(result.spacerPreferredPosition == floor + 2 * step)
        #expect(result.extraHiddenPreferredPositions == [floor + 4 * step, floor + 3 * step])
        #expect(result.targetPreferredPosition == floor + 5 * step)
    }

    @Test("k = 1 through the new parameter equals C1's own plan")
    func kOneUnchanged() {
        let c1 = PlacementPlan.plan(owners: [], barRightEdge: 1728, notchRightEdge: 956.5, targetOccupiedPt: pitch, spacerOccupiedPt: spacerPitch, protectedOccupiedPt: pitch)
        #expect(plan(extra: 0) == c1)
        guard case .planned(let result) = c1 else { return }
        #expect(result.extraHiddenMinXs.isEmpty)
        #expect(result.extraHiddenPreferredPositions.isEmpty)
    }

    @Test("the extra items count toward the room: a bar with room for k = 1 but not k = 4 refuses k = 4")
    func extraItemsNeedRoom() {
        let barRightEdge = 956.5 + 3 * pitch + spacerPitch + PlacementPlan.marginPt
        guard case .planned = plan(extra: 0, barRightEdge: barRightEdge) else {
            Issue.record("k = 1 should fit")
            return
        }
        #expect(plan(extra: 3, barRightEdge: barRightEdge) == .refused(.noRoom(onBarOwnerCount: 0)))
    }

    @Test("a negative extra count is refused as no room")
    func negativeExtraRefused() {
        #expect(plan(extra: -1) == .refused(.noRoom(onBarOwnerCount: 0)))
    }
}

enum PlanFailure: Error {
    case refused
}
