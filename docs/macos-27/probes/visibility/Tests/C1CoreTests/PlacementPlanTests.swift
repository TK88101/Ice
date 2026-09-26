import Testing
@testable import C1Core

/// Amendment v9, "Sort-key values" / "Real pitch": the pure geometry and
/// value-choice behind Amendment v8's write. Geometry (`targetMinX` etc.)
/// still anchors `marginPt` left of the nearest on-bar owner item, now using
/// each helper's own real *occupied* pitch (crosscheck-rework8.json #1) --
/// but the written "NSStatusItem Preferred Position" values are no longer
/// `barRightEdge - minX` (crosscheck-rework8.json #0/#4: the recorded
/// stored values on the owner's bar contradict that reading and fit a
/// sort-key one instead). They are now `floor + step` for each helper, where
/// `floor` is the largest of the historical maximum and every on-bar
/// owner's own scanned stored value -- read-only, before any launch -- and
/// an uncertain scan refuses the whole plan rather than guess.
@Suite("PlacementPlan")
struct PlacementPlanTests {
    let targetOccupied = 28.0
    let spacerOccupied = 32.0
    let protectedOccupied = 28.0

    private func owner(_ minX: Double, value: Double? = nil) -> PlacementValueScan.Classified {
        guard let value else {
            return .init(minX: minX, issue: nil, numericValues: [])
        }
        return .init(minX: minX, issue: nil, numericValues: [value])
    }

    // MARK: - Geometry (occupied pitch)

    @Test("plenty of room, one owner item -- lands left to right at the real occupied pitch, margin left of the owner item")
    func plentyOfRoomOneOwner() throws {
        let outcome = PlacementPlan.plan(
            owners: [owner(270.0)],
            barRightEdge: 320.0,
            notchRightEdge: 0.0,
            targetOccupiedPt: targetOccupied,
            spacerOccupiedPt: spacerOccupied,
            protectedOccupiedPt: protectedOccupied
        )
        guard case .planned(let plan) = outcome else { throw TestFailure.unexpectedRefusal(outcome) }
        #expect(plan.spacerMinX == plan.targetMinX + targetOccupied)
        #expect(plan.protectedMinX == plan.spacerMinX + spacerOccupied)
        #expect(plan.protectedMinX + protectedOccupied == 270.0 - PlacementPlan.marginPt)
        #expect(plan.protectedMinX + protectedOccupied <= 270.0)
    }

    @Test("no on-bar owner items at all -- anchored marginPt left of the bar's own right edge")
    func noOwnerItemsAnchorsAtRightEdge() throws {
        let outcome = PlacementPlan.plan(owners: [], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        guard case .planned(let plan) = outcome else { throw TestFailure.unexpectedRefusal(outcome) }
        #expect(plan.protectedMinX + protectedOccupied == 320.0 - PlacementPlan.marginPt)
    }

    @Test("only the leftmost owner item constrains the geometry -- others further right are irrelevant")
    func onlyLeftmostOwnerConstrains() {
        let withOne = PlacementPlan.plan(owners: [owner(120.0)], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        let withSeveral = PlacementPlan.plan(owners: [owner(120.0), owner(200.0), owner(270.0)], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        #expect(withOne == withSeveral)
    }

    @Test("exactly enough room (the group's left edge lands exactly on the notch's right edge) -- passes, not refused")
    func exactlyEnoughRoomPasses() throws {
        let totalOccupied = targetOccupied + spacerOccupied + protectedOccupied
        let ownerMinX = PlacementPlan.marginPt + totalOccupied
        let outcome = PlacementPlan.plan(owners: [owner(ownerMinX)], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        guard case .planned(let plan) = outcome else { throw TestFailure.unexpectedRefusal(outcome) }
        #expect(plan.targetMinX == 0.0)
    }

    @Test("one point short of room -- refused (.noRoom)")
    func onePointShortOfRoomRefuses() {
        let totalOccupied = targetOccupied + spacerOccupied + protectedOccupied
        let ownerMinX = PlacementPlan.marginPt + totalOccupied - 1.0
        let outcome = PlacementPlan.plan(owners: [owner(ownerMinX)], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        #expect(outcome == .refused(.noRoom(onBarOwnerCount: 1)))
    }

    @Test("a notch that already consumes the whole bar -- refused (.noRoom)")
    func notchConsumingWholeBarRefuses() {
        let outcome = PlacementPlan.plan(owners: [], barRightEdge: 320.0, notchRightEdge: 320.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        #expect(outcome == .refused(.noRoom(onBarOwnerCount: 0)))
    }

    @Test("a non-positive occupied width is refused -- defensive, never a real geometry")
    func nonPositiveWidthRefuses() {
        #expect(PlacementPlan.plan(owners: [], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: 0, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied) == .refused(.noRoom(onBarOwnerCount: 0)))
        #expect(PlacementPlan.plan(owners: [], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: -1, protectedOccupiedPt: protectedOccupied) == .refused(.noRoom(onBarOwnerCount: 0)))
    }

    // MARK: - Sort-key values (Amendment v9)

    @Test("no owner has a stored value -- the floor is the historical maximum, and the three values are well-spaced above it")
    func floorFallsBackToHistoricalMaximum() throws {
        let outcome = PlacementPlan.plan(owners: [owner(270.0)], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        guard case .planned(let plan) = outcome else { throw TestFailure.unexpectedRefusal(outcome) }
        #expect(plan.floorValue == PlacementPlan.historicalMaximumStoredValue)
        #expect(plan.targetPreferredPosition == plan.floorValue + 3 * PlacementPlan.sortKeyStepPt)
        #expect(plan.spacerPreferredPosition == plan.floorValue + 2 * PlacementPlan.sortKeyStepPt)
        #expect(plan.protectedPreferredPosition == plan.floorValue + 1 * PlacementPlan.sortKeyStepPt)
        #expect(plan.targetPreferredPosition > plan.spacerPreferredPosition)
        #expect(plan.spacerPreferredPosition > plan.protectedPreferredPosition)
        #expect(plan.protectedPreferredPosition > plan.floorValue)
    }

    @Test("a stale on-bar owner value below the historical maximum (5703) does not raise the floor")
    func staleValueBelowHistoricalMaximumIsIgnored() throws {
        let outcome = PlacementPlan.plan(owners: [owner(270.0, value: 5703)], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        guard case .planned(let plan) = outcome else { throw TestFailure.unexpectedRefusal(outcome) }
        #expect(plan.floorValue == PlacementPlan.historicalMaximumStoredValue)
        #expect(plan.protectedPreferredPosition > 5703)
    }

    @Test("an on-bar owner value above the historical maximum raises the floor, and the plan still lands the helpers left of it")
    func ownerValueAboveHistoricalMaximumRaisesFloor() throws {
        let outcome = PlacementPlan.plan(owners: [owner(270.0, value: 6000)], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        guard case .planned(let plan) = outcome else { throw TestFailure.unexpectedRefusal(outcome) }
        #expect(plan.floorValue == 6000)
        #expect(plan.protectedPreferredPosition > 6000)
    }

    @Test("the floor is the maximum scanned value across every on-bar owner, not just the leftmost")
    func floorIsMaxAcrossEveryOwner() throws {
        let outcome = PlacementPlan.plan(owners: [owner(120.0, value: 400), owner(200.0, value: 6500), owner(270.0, value: 900)], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        guard case .planned(let plan) = outcome else { throw TestFailure.unexpectedRefusal(outcome) }
        #expect(plan.floorValue == 6500)
    }

    // MARK: - Uncertain-scan refusal (Amendment v9)

    @Test("an owner scan issue refuses the whole plan before any geometry work, with that owner's own minX and issue")
    func scanIssueRefuses() {
        let issueOwner = PlacementValueScan.Classified(minX: 270.0, issue: .nonNumeric, numericValues: [])
        let outcome = PlacementPlan.plan(owners: [issueOwner], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        #expect(outcome == .refused(.ownerScanUncertain(minX: 270.0, issue: .nonNumeric)))
    }

    @Test("with several owners, the leftmost one's own scan issue is reported, deterministically")
    func leftmostOwnersIssueWinsDeterministically() {
        let owners = [
            PlacementValueScan.Classified(minX: 270.0, issue: .missing, numericValues: []),
            PlacementValueScan.Classified(minX: 120.0, issue: .unreadable, numericValues: []),
            PlacementValueScan.Classified(minX: 200.0, issue: .attributionUnclear, numericValues: []),
        ]
        let outcome = PlacementPlan.plan(owners: owners, barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        #expect(outcome == .refused(.ownerScanUncertain(minX: 120.0, issue: .unreadable)))
    }

    @Test("a scan issue refuses even when there would otherwise be no room -- the scan is checked first")
    func scanIssueRefusesBeforeRoomCheck() {
        let issueOwner = PlacementValueScan.Classified(minX: 10.0, issue: .missing, numericValues: [])
        let outcome = PlacementPlan.plan(owners: [issueOwner], barRightEdge: 320.0, notchRightEdge: 0.0, targetOccupiedPt: targetOccupied, spacerOccupiedPt: spacerOccupied, protectedOccupiedPt: protectedOccupied)
        #expect(outcome == .refused(.ownerScanUncertain(minX: 10.0, issue: .missing)))
    }
}

enum TestFailure: Error {
    case unexpectedRefusal(PlacementPlan.Outcome)
}
