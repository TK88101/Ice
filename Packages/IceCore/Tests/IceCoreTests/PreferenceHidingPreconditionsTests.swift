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
            iceIcon: icon ?? rect(midX: 1500),
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

    @Test("D-c (a): an icon exactly at the divider's mid-x is not right of it")
    func iconAtDividerBlocks() {
        let result = evaluate(icon: rect(midX: 1469), hiddenDivider: divider(midX: 1469))
        #expect(result == .blocked([.iceIconNotRightOfDivider(.iconLeftOfDivider)]))
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
            iceIcon: rect(midX: 1500), hiddenDivider: nil, completeness: .complete, ownRead: .ok, blockers: []
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
            iceIcon: rect(midX: 100),
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
}
