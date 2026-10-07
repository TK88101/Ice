import Testing
@testable import IceCore

/// Plan 2026-10-07-icebar-preference-hiding, S2 design T2a: what one
/// discovery pass says about where Ice's items and the other items sit, as
/// numbers only, so the trace's oracle is judged on one snapshot.
@Suite("LabTracePlacement")
struct LabTracePlacementTests {
    /// Divider minX 500 (width 18), icon mid-x 1017.5 (minX 1000, width 35).
    let divider = DividerReading(frame: barFrame(minX: 500, width: 18), isUsable: true)
    let icon = fixtureItem(identifier: "Ice.ControlItem.Visible", pid: 9, frame: barFrame(minX: 1000, width: 35), isSelf: true)

    func other(_ identifier: String, minX: Double?, position: ItemPosition = .onBar) -> DiscoveredItem {
        fixtureItem(identifier: identifier, pid: 1, frame: minX.map { barFrame(minX: $0, width: 24) }, position: position)
    }

    func placement(
        _ items: [DiscoveredItem],
        icon: DiscoveredItem?? = .none,
        hiddenDivider: DividerReading?? = .none,
        alwaysHiddenDivider: DividerReading? = nil,
        ownRead: OwnReadStatus = .ok,
        completeness: Completeness = .complete
    ) -> LabTracePlacement {
        LabTracePlacement(set: fixtureSet(
            items: items,
            visibleControlItem: icon ?? self.icon,
            hiddenDivider: hiddenDivider ?? divider,
            alwaysHiddenDivider: alwaysHiddenDivider,
            ownRead: ownRead,
            completeness: completeness
        ))
    }

    @Test("others are counted by region: left of the divider's minX, between, right of the icon's mid-x")
    func regions() {
        let result = placement([
            other("left", minX: 100),
            other("between1", minX: 600),
            other("between2", minX: 900),
            other("right", minX: 1100),
        ])
        #expect(result.othersLeftOfHiddenDivider == 1)
        #expect(result.othersBetween == 2)
        #expect(result.othersRightOfIcon == 1)
        #expect(result.othersUnplaced == 0)
    }

    @Test("the boundaries are IceCore's: a mid-x exactly on the divider's minX is not left of it; one on the icon's mid-x is right of it")
    func boundaries() {
        // frame 488..512 -> mid-x 500 == divider minX; frame 1005.5..1029.5 -> mid-x 1017.5 == icon mid-x
        let result = placement([other("onDivider", minX: 488), other("justLeft", minX: 487), other("onIcon", minX: 1005.5)])
        #expect(result.othersLeftOfHiddenDivider == 1)
        #expect(result.othersBetween == 1)
        #expect(result.othersRightOfIcon == 1)
    }

    @Test("an item not on the bar, frameless or parked on either side, is unplaced and never left of the divider; a stacked one is on the bar")
    func unplaced() {
        // MEASURED 26A434, run 20261008-001005-7X98U1-trace: three parked items
        // with frames at x -1 to 7, y 1104 (the screen's bottom left).
        let result = placement([
            other("noFrame", minX: nil, position: .noFrame),
            other("parkedRight", minX: 5000, position: .parked),
            other("parkedLeft", minX: 7, position: .parked),
            other("stackedBetween", minX: 700, position: .stacked),
            other("stackedLeft", minX: 100, position: .stacked),
        ])
        #expect(result.othersUnplaced == 3)
        #expect(result.othersLeftOfHiddenDivider == 1)
        #expect(result.othersBetween == 1)
        #expect(result.othersOnBar == 2)
    }

    @Test("the on-bar count needs no boundary: a baseline pass before Ice's items exist still has it")
    func onBarWithoutBoundaries() {
        let result = placement(
            [other("a", minX: 100), other("b", minX: 700, position: .stacked), other("parked", minX: 7, position: .parked), other("none", minX: nil, position: .noFrame)],
            icon: .some(nil),
            hiddenDivider: .some(nil),
            ownRead: .identifiersMissing
        )
        #expect(result.othersOnBar == 2)
        #expect(result.othersUnplaced == 4)
    }

    @Test("without a usable divider nothing is placed")
    func noDivider() {
        let unusable = DividerReading(frame: barFrame(minX: 500, width: 18), isUsable: false)
        let result = placement([other("a", minX: 100), other("b", minX: 700)], hiddenDivider: .some(unusable))
        #expect(result.othersUnplaced == 2)
        #expect(result.othersLeftOfHiddenDivider == 0)
        #expect(result.othersBetween == 0)
        #expect(result.othersRightOfIcon == 0)
    }

    @Test("left of the divider is the membership rule's and needs no icon; the rest cannot be placed without one")
    func noIcon() {
        let result = placement([other("a", minX: 100), other("b", minX: 700)], icon: .some(nil))
        #expect(result.othersLeftOfHiddenDivider == 1)
        #expect(result.othersUnplaced == 1)
        #expect(result.othersBetween == 0)
    }

    @Test("the frames and verdicts are the pass's own")
    func framesAndVerdicts() {
        let alwaysHidden = DividerReading(frame: barFrame(minX: 80, width: 18), isUsable: true)
        let result = placement([], alwaysHiddenDivider: alwaysHidden)
        #expect(result.icon == barFrame(minX: 1000, width: 35))
        #expect(result.iconOnBar)
        #expect(result.hiddenDivider == barFrame(minX: 500, width: 18))
        #expect(result.hiddenDividerUsable)
        #expect(result.alwaysHiddenDivider == barFrame(minX: 80, width: 18))
        #expect(result.alwaysHiddenDividerUsable)
        #expect(result.isComplete)
        #expect(result.ownReadOk)

        let poor = placement([], hiddenDivider: .some(nil), ownRead: .identifiersMissing, completeness: .incomplete(failedPIDs: [3]))
        #expect(poor.hiddenDivider == nil)
        #expect(!poor.hiddenDividerUsable)
        #expect(poor.alwaysHiddenDivider == nil)
        #expect(!poor.alwaysHiddenDividerUsable)
        #expect(!poor.isComplete)
        #expect(poor.failedReads == 1)
        #expect(result.failedReads == 0)
        #expect(placement([], completeness: .permissionDenied).failedReads == 0)
        #expect(!placement([], completeness: .permissionDenied).isComplete)
        #expect(!poor.ownReadOk)
    }

    @Test("an icon that is parked, frameless or missing is not on the bar and its placement unreadable, whatever its frame says (Codex review, T2a)")
    func iconOffBar() {
        func icon(_ position: ItemPosition) -> DiscoveredItem {
            let frame: BarRect? = position == .noFrame ? nil : barFrame(minX: 1000, width: 35)
            return fixtureItem(identifier: "Ice.ControlItem.Visible", pid: 9, frame: frame, position: position, isSelf: true)
        }
        #expect(!placement([], icon: .some(icon(.parked))).iconOnBar)
        #expect(placement([], icon: .some(icon(.parked))).iconPlacement == .iconUnreadable)
        #expect(placement([], icon: .some(icon(.noFrame))).iconPlacement == .iconUnreadable)
        #expect(placement([], icon: .some(icon(.stacked))).iconPlacement == nil)
        #expect(!placement([], icon: .some(icon(.noFrame))).iconOnBar)
        #expect(!placement([], icon: .some(nil)).iconOnBar)
        #expect(placement([], icon: .some(icon(.stacked))).iconOnBar)
    }

    @Test("the icon's placement is the precondition rule's, not a second definition")
    func iconPlacement() {
        #expect(placement([]).iconPlacement == nil)
        let inverted = placement([], icon: .some(fixtureItem(identifier: "Ice.ControlItem.Visible", pid: 9, frame: barFrame(minX: 100, width: 35), isSelf: true)))
        #expect(inverted.iconPlacement == .iconLeftOfDivider)
        #expect(placement([], icon: .some(nil)).iconPlacement == .iconUnreadable)
    }
}
