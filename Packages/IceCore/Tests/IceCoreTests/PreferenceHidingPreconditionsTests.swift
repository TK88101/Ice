import Testing
@testable import IceCore

/// Plan 2026-10-07-icebar-preference-hiding, D-c and section 5 O1: the three
/// preconditions any hiding needs, verified or not, and "blocked, not
/// attempted" naming every one that fails.
@Suite("PreferenceHidingPreconditions")
struct PreferenceHidingPreconditionsTests {
    func rect(midX: Double) -> BarRect {
        BarRect(minX: midX - 10, minY: 4.5, width: 20, height: 24)
    }

    /// Ice's icon as a pass reads it on the bar with this frame.
    func iconItem(_ frame: BarRect?, position: ItemPosition = .onBar) -> DiscoveredItem {
        fixtureItem(identifier: "Ice.ControlItem.Visible", pid: 9, frame: frame, position: position, isSelf: true)
    }

    func divider(midX: Double, usable: Bool = true) -> DividerReading {
        DividerReading(frame: rect(midX: midX), isUsable: usable)
    }

    func blocker(_ identifier: String) -> PreferenceHidingBlocker {
        let key = ItemKey(namespace: "com.example.a", identifier: identifier, pid: 7, childIndex: 0)
        return PreferenceHidingBlocker(key: key, tag: key.tagKey(isSelf: false), name: nil)
    }

    func evaluate(
        icon: BarRect? = nil,
        hiddenDivider: DividerReading? = nil,
        completeness: Completeness = .complete,
        ownRead: OwnReadStatus = .ok,
        blockers: [PreferenceHidingBlocker] = []
    ) -> PreferenceHidingPreconditionResult {
        PreferenceHidingPreconditions.evaluate(
            iceIcon: iconItem(icon ?? rect(midX: 1500)),
            hiddenDivider: hiddenDivider ?? divider(midX: 1469),
            completeness: completeness,
            ownRead: ownRead,
            blockers: blockers
        )
    }

    @Test("D-c: icon right of the divider, a complete pass and no positional item is ok")
    func allHoldIsOk() {
        #expect(evaluate() == .ok)
        #expect(evaluate().isOk)
        #expect(evaluate().reasons.isEmpty)
    }

    // MARK: - (a) icon right of divider

    @Test("D-c (a), P2: an icon left of its divider blocks")
    func iconLeftOfDividerBlocks() {
        let result = evaluate(icon: rect(midX: 1297.5), hiddenDivider: divider(midX: 1469))
        #expect(result == .blocked([.iceIconNotRightOfDivider(.iconLeftOfDivider)]))
    }

    @Test("D-c (a): an icon whose mid-x is exactly the divider's minX is not right of it")
    func iconAtDividerBlocks() {
        // divider midX 1469, width 20 -> minX 1459
        let result = evaluate(icon: rect(midX: 1459), hiddenDivider: divider(midX: 1469))
        #expect(result == .blocked([.iceIconNotRightOfDivider(.iconLeftOfDivider)]))
    }

    @Test("D-c (a): the boundary is the divider's minX, so an icon between its minX and its mid-x is right of it")
    func iconBetweenDividerMinAndMidIsRight() {
        // divider minX 1459, midX 1469; the divider's width is not a bar position.
        #expect(evaluate(icon: rect(midX: 1465), hiddenDivider: divider(midX: 1469)) == .ok)
        #expect(evaluate(icon: rect(midX: 1459.5), hiddenDivider: divider(midX: 1469)) == .ok)
    }

    @Test("D-c (a): a missing icon reading is not right of the divider")
    func missingIconBlocks() {
        let result = PreferenceHidingPreconditions.evaluate(
            iceIcon: nil, hiddenDivider: divider(midX: 1469), completeness: .complete, ownRead: .ok, blockers: []
        )
        #expect(result == .blocked([.iceIconNotRightOfDivider(.iconUnreadable)]))
    }

    @Test("D-c (a): a missing divider reading blocks")
    func missingDividerBlocks() {
        let result = PreferenceHidingPreconditions.evaluate(
            iceIcon: iconItem(rect(midX: 1500)), hiddenDivider: nil, completeness: .complete, ownRead: .ok, blockers: []
        )
        #expect(result == .blocked([.iceIconNotRightOfDivider(.dividerUnusable)]))
    }

    @Test("D-c (a): a divider with no frame, or marked unusable, blocks")
    func unusableDividerBlocks() {
        let noFrame = DividerReading(frame: nil, isUsable: false)
        #expect(evaluate(hiddenDivider: noFrame) == .blocked([.iceIconNotRightOfDivider(.dividerUnusable)]))
        #expect(evaluate(hiddenDivider: divider(midX: 1469, usable: false)) == .blocked([.iceIconNotRightOfDivider(.dividerUnusable)]))
    }

    @Test("D-c (a): a non-finite frame is an unusable reading, not a position")
    func nonFiniteBlocks() {
        let nan = BarRect(minX: .nan, minY: 4.5, width: 20, height: 24)
        let infinite = BarRect(minX: .infinity, minY: 4.5, width: 20, height: 24)
        #expect(evaluate(icon: nan) == .blocked([.iceIconNotRightOfDivider(.iconUnreadable)]))
        #expect(evaluate(icon: infinite) == .blocked([.iceIconNotRightOfDivider(.iconUnreadable)]))
        let nanDivider = DividerReading(frame: nan, isUsable: true)
        #expect(evaluate(hiddenDivider: nanDivider) == .blocked([.iceIconNotRightOfDivider(.dividerUnusable)]))
    }

    @Test("D-c (a): every component of a frame must be finite, not only its mid-x")
    func everyComponentMustBeFinite() {
        let bad: [BarRect] = [
            BarRect(minX: 1490, minY: .nan, width: 20, height: 24),
            BarRect(minX: 1490, minY: 4.5, width: 20, height: .infinity),
            BarRect(minX: 1490, minY: -.infinity, width: 20, height: 24),
            BarRect(minX: 1490, minY: 4.5, width: .nan, height: 24),
        ]
        for frame in bad {
            #expect(evaluate(icon: frame) == .blocked([.iceIconNotRightOfDivider(.iconUnreadable)]), "icon \(frame)")
            let reading = DividerReading(frame: frame, isUsable: true)
            #expect(evaluate(hiddenDivider: reading) == .blocked([.iceIconNotRightOfDivider(.dividerUnusable)]), "divider \(frame)")
        }
    }

    @Test("D-c (a): a finite mid-x with a non-finite minY (icon) or height (divider) is unreadable / unusable")
    func finiteMidXIsNotEnough() {
        let icon = BarRect(minX: 1490, minY: .nan, width: 20, height: 24)
        #expect(icon.midX.isFinite)
        #expect(evaluate(icon: icon) == .blocked([.iceIconNotRightOfDivider(.iconUnreadable)]))
        let tall = BarRect(minX: 1459, minY: 4.5, width: 20, height: .infinity)
        #expect(tall.midX.isFinite)
        #expect(evaluate(hiddenDivider: DividerReading(frame: tall, isUsable: true))
            == .blocked([.iceIconNotRightOfDivider(.dividerUnusable)]))
    }

    // MARK: - (b) complete pass

    @Test("D-c (b): an incomplete pass blocks, naming the failed pids")
    func incompleteBlocks() {
        let result = evaluate(completeness: .incomplete(failedPIDs: [3, 9]))
        #expect(result == .blocked([.discoveryIncomplete(.incomplete(failedPIDs: [3, 9]))]))
    }

    @Test("D-c (b): permission denied blocks")
    func permissionDeniedBlocks() {
        let result = evaluate(completeness: .permissionDenied)
        #expect(result == .blocked([.discoveryIncomplete(.permissionDenied)]))
    }

    @Test("D-c (b): a complete pass whose own read is not ok blocks, for each own-read status", arguments: [
        OwnReadStatus.failed, .identifiersMissing, .notRead,
    ])
    func ownReadNotOkBlocks(status: OwnReadStatus) {
        #expect(evaluate(ownRead: status) == .blocked([.ownReadNotOk(status)]))
    }

    // MARK: - (c) positional

    @Test("D-c (c): a positional item left of the divider blocks and carries its key")
    func positionalBlocks() {
        let p = blocker("clock")
        #expect(evaluate(blockers: [p]) == .blocked([.positionalItemsLeftOfDivider([p])]))
    }

    @Test("D-c (c): several positional items are one reason naming all of them, in order")
    func severalPositionalAreOneReason() {
        let list = [blocker("b"), blocker("a")]
        #expect(evaluate(blockers: list) == .blocked([.positionalItemsLeftOfDivider(list)]))
    }

    // MARK: - every failing reason

    @Test("D-c, O1: all preconditions failing at once name every reason, in a fixed order")
    func everyReasonIsReported() {
        let p = blocker("clock")
        let result = PreferenceHidingPreconditions.evaluate(
            iceIcon: iconItem(rect(midX: 100)),
            hiddenDivider: divider(midX: 1469),
            completeness: .incomplete(failedPIDs: [5]),
            ownRead: .failed,
            blockers: [p]
        )
        #expect(result == .blocked([
            .iceIconNotRightOfDivider(.iconLeftOfDivider),
            .discoveryIncomplete(.incomplete(failedPIDs: [5])),
            .ownReadNotOk(.failed),
            .positionalItemsLeftOfDivider([p]),
        ]))
        #expect(!result.isOk)
        #expect(result.reasons.count == 4)
    }

    @Test("D-c, O1: permission denied with an unread own process names both discovery reasons")
    func permissionDeniedNamesBothDiscoveryReasons() {
        let result = evaluate(completeness: .permissionDenied, ownRead: .notRead)
        #expect(result.reasons == [.discoveryIncomplete(.permissionDenied), .ownReadNotOk(.notRead)])
    }

    // MARK: - the discovered icon

    @Test("D-c (a): a discovered icon that is not on the bar is unreadable, wherever its frame points; on the bar the frame rule decides", arguments: [
        (ItemPosition.parked, 1500.0, PreferenceHidingIconPlacement?.some(.iconUnreadable)),
        (.parked, 7.0, .some(.iconUnreadable)),
        (.noFrame, 1500.0, .some(.iconUnreadable)),
        (.onBar, 1500.0, nil),
        (.stacked, 1500.0, nil),
        (.onBar, 1297.5, .some(.iconLeftOfDivider)),
    ])
    func discoveredIcon(position: ItemPosition, midX: Double, expected: PreferenceHidingIconPlacement?) {
        let frame: BarRect? = position == .noFrame ? nil : rect(midX: midX)
        let icon = iconItem(frame, position: position)
        #expect(PreferenceHidingPreconditions.iconPlacement(icon: icon, divider: divider(midX: 1469)) == expected)
        let result = PreferenceHidingPreconditions.evaluate(
            iceIcon: icon, hiddenDivider: divider(midX: 1469), completeness: .complete, ownRead: .ok, blockers: []
        )
        #expect(result == expected.map { .blocked([.iceIconNotRightOfDivider($0)]) } ?? .ok)
        #expect(PreferenceHidingPreconditions.iconPlacement(icon: DiscoveredItem?.none, divider: divider(midX: 1469)) == .iconUnreadable)
    }

    // MARK: - From a held placement (T3b, G3)

    @Test("T3b G3: the placement Ice holds decides (a): none held is ok, any held blocks with it", arguments: [
        PreferenceHidingIconPlacement.iconLeftOfDivider, .iconUnreadable, .dividerUnusable,
    ])
    func heldPlacementDecides(placement: PreferenceHidingIconPlacement) {
        #expect(PreferenceHidingPreconditions.evaluate(iconPlacement: nil, completeness: .complete, ownRead: .ok, blockers: []) == .ok)
        let result = PreferenceHidingPreconditions.evaluate(iconPlacement: placement, completeness: .complete, ownRead: .ok, blockers: [])
        #expect(result == .blocked([.iceIconNotRightOfDivider(placement)]))
    }

    @Test("T3b G3: with a held placement the other reasons keep their order a, b, c")
    func heldPlacementKeepsOrder() {
        let positional = blocker("shared")
        let result = PreferenceHidingPreconditions.evaluate(
            iconPlacement: .iconUnreadable, completeness: .permissionDenied, ownRead: .notRead, blockers: [positional]
        )
        #expect(result == .blocked([
            .iceIconNotRightOfDivider(.iconUnreadable),
            .discoveryIncomplete(.permissionDenied),
            .ownReadNotOk(.notRead),
            .positionalItemsLeftOfDivider([positional]),
        ]))
    }
}
