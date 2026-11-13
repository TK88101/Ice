import Testing
@testable import IceCore

/// The roster IceBar keeps across passes (plan 2026-10-07-icebar-preference-
/// hiding, D-a, D-c and the T3b design): each completed pass advances it; a pass
/// without permission freezes it and blocks.
@Suite("PreferenceHidingRoster")
struct PreferenceHidingRosterTests {
    static let divider = DividerReading(frame: BarRect(minX: 900, minY: 4.5, width: 18, height: 24), isUsable: true)
    static let standard = DividerState(isEnabled: true, isCollapsed: true, collapsedFor: 5, changedDuringPass: false)
    static let hiding = DividerState(isEnabled: true, isCollapsed: false, collapsedFor: 0, changedDuringPass: false)
    static let display = BarDisplay(bounds: BarBounds(minX: 0, maxX: 1512, minY: 0, barHeight: 33), originX: 0, originY: 0)
    /// The hidden divider's right edge at standard length (`divider`).
    static let boundary = 918.0

    func placed(_ identifier: String, pid: Int32, minX: Double, position: ItemPosition = .onBar) -> DiscoveredItem {
        fixtureItem(identifier: identifier, pid: pid, frame: barFrame(minX: minX, width: 24), position: position)
    }

    func children(_ items: [DiscoveredItem]) -> [Int32: [String?]] {
        Dictionary(grouping: items, by: \.key.pid).mapValues { $0.map { $0.key.identifier } }
    }

    func advance(
        _ roster: PreferenceHidingRoster,
        _ items: [DiscoveredItem],
        state: DividerState = standard,
        completeness: Completeness = .complete,
        placement: PreferenceHidingIconPlacement? = nil,
        exited: Set<Int32> = [],
        display: BarDisplay = display
    ) -> PreferenceHidingRoster {
        roster.advanced(
            set: fixtureSet(items: items, hiddenDivider: Self.divider, completeness: completeness),
            hiddenDividerState: state,
            childIdentifiersByPID: children(items),
            iconPlacement: placement,
            hasExited: { exited.contains($0) },
            display: display
        )
    }

    @Test("a pass at standard length makes everything left of the divider a member, and remembers each member's key")
    func firstPass() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 2, minX: 1000)
        let roster = advance(PreferenceHidingRoster(), [a, right])
        #expect(roster.membership.members.map(\.tag) == [a.tagKey])
        #expect(roster.lastKeys == [a.tagKey: a.key])
        #expect(roster.preconditions == .ok)
    }

    @Test("every item the pass read is in the item tags, parked ones included, in a stable order")
    func itemTags() {
        let a = placed("a", pid: 1, minX: 100)
        let parked = placed("p", pid: 3, minX: -40, position: .parked)
        let right = placed("r", pid: 2, minX: 1000)
        let one = advance(PreferenceHidingRoster(), [a, parked, right])
        let other = advance(PreferenceHidingRoster(), [right, parked, a])
        #expect(Set(one.itemTags) == Set([a.tagKey, parked.tagKey, right.tagKey]))
        #expect(one.itemTags == other.itemTags)
    }

    @Test("a pass without permission keeps the roster and blocks")
    func permissionDeniedFreezes() {
        let a = placed("a", pid: 1, minX: 100)
        let roster = advance(PreferenceHidingRoster(), [a])
        let denied = advance(roster, [], completeness: .permissionDenied)
        #expect(denied.membership == roster.membership)
        #expect(denied.itemTags == roster.itemTags)
        #expect(denied.lastKeys == roster.lastKeys)
        #expect(denied.preconditions.reasons.contains(.discoveryIncomplete(.permissionDenied)))
    }

    @Test("G1: a member whose process has exited is dropped before the pass resolves; a live unread one stays, stale")
    func exitedMemberIsDropped() {
        let a = placed("a", pid: 1, minX: 100)
        let b = placed("b", pid: 2, minX: 130)
        let roster = advance(PreferenceHidingRoster(), [a, b])
        let next = advance(roster, [a], exited: [2])
        #expect(next.membership.members.map(\.tag) == [a.tagKey])
        #expect(next.lastKeys == [a.tagKey: a.key])
        let kept = advance(roster, [a])
        #expect(kept.membership.members.map(\.condition) == [.ready, .stale(.missingFromRead)])
        #expect(kept.lastKeys[b.tagKey] == b.key, "the last key read is kept while the member is")
    }

    @Test("a pass taken at a hiding length adds no member")
    func hidingLengthFreezes() {
        let a = placed("a", pid: 1, minX: 100)
        let roster = advance(PreferenceHidingRoster(), [a])
        let late = placed("n", pid: 5, minX: 60)
        let next = advance(roster, [late, a], state: Self.hiding)
        #expect(next.membership.members.map(\.tag) == [a.tagKey])
    }

    @Test("the preconditions come from the held placement and this pass's blockers")
    func preconditions() {
        let a = placed("a", pid: 1, minX: 100)
        let blocked = advance(PreferenceHidingRoster(), [a], placement: .iconLeftOfDivider)
        #expect(blocked.preconditions == .blocked([.iceIconNotRightOfDivider(.iconLeftOfDivider)]))
    }

    @Test("the signature carries the item tags, the roster's tags and the context")
    func signature() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 2, minX: 1000)
        let roster = advance(PreferenceHidingRoster(), [a, right])
        let signature = roster.signature(frontmostPID: 4, menuMaxX: 300, displayID: 1, spaceID: 2)
        #expect(signature.items == roster.itemTags)
        #expect(signature.members == [a.tagKey])
        #expect(signature.frontmostPID == 4)
    }

    // MARK: - The visible boundary (plan 2026-11-13-flash-on-item-change, D2, D2a, D3)

    @Test("a trusted pass sets the boundary to the divider's right edge and reads who is right of it")
    func trustedPassSetsBoundary() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 2, minX: 1000)
        let roster = advance(PreferenceHidingRoster(), [a, right])
        #expect(roster.visibleBoundary == Self.boundary)
        #expect(roster.visibleTags == [right.tagKey])
    }

    @Test("no boundary before a trusted pass: nothing is visible")
    func noBoundaryBeforeTrusted() {
        let right = placed("r", pid: 2, minX: 1000)
        let roster = advance(PreferenceHidingRoster(), [right], state: Self.hiding)
        #expect(roster.visibleBoundary == nil)
        #expect(roster.visibleTags.isEmpty)
    }

    @Test("an untrusted pass with no removal keeps the boundary and judges an added item by it")
    func untrustedKeepsBoundary() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 2, minX: 1000)
        let roster = advance(PreferenceHidingRoster(), [a, right])
        let added = placed("n", pid: 3, minX: 960)
        let next = advance(roster, [a, right, added], state: Self.hiding)
        #expect(next.visibleBoundary == Self.boundary)
        #expect(next.visibleTags == [right.tagKey, added.tagKey])
    }

    @Test("an item exactly at the boundary is visible, one point left of it is not")
    func boundaryEdge() {
        let roster = advance(PreferenceHidingRoster(), [placed("a", pid: 1, minX: 100)])
        let at = placed("e", pid: 3, minX: Self.boundary)
        let before = placed("f", pid: 4, minX: Self.boundary - 1)
        let next = advance(roster, [placed("a", pid: 1, minX: 100), at, before], state: Self.hiding)
        #expect(next.visibleTags == [at.tagKey])
    }

    @Test("a pass that reads an item gone clears the boundary: an addition in the same pass is not visible")
    func removalClearsBoundary() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 2, minX: 1000)
        let roster = advance(PreferenceHidingRoster(), [a, right])
        let added = placed("n", pid: 3, minX: 1000)
        let next = advance(roster, [a, added], state: Self.hiding)
        #expect(next.visibleBoundary == nil)
        #expect(next.visibleTags.isEmpty)
    }

    @Test("two removals, then an addition before a trusted pass: not visible")
    func removalsThenAddition() {
        let a = placed("a", pid: 1, minX: 100)
        let r1 = placed("r", pid: 2, minX: 1000)
        let r2 = placed("s", pid: 5, minX: 1040)
        let roster = advance(PreferenceHidingRoster(), [a, r1, r2])
        let once = advance(roster, [a, r2], state: Self.hiding)
        let twice = advance(once, [a], state: Self.hiding)
        let added = placed("n", pid: 3, minX: 1000)
        let next = advance(twice, [a, added], state: Self.hiding)
        #expect(next.visibleTags.isEmpty)
    }

    @Test("after a soft addition the kept boundary still judges the next one")
    func additionAfterAddition() {
        let a = placed("a", pid: 1, minX: 100)
        let roster = advance(PreferenceHidingRoster(), [a])
        let first = placed("n", pid: 3, minX: 1000)
        let once = advance(roster, [a, first], state: Self.hiding)
        let second = placed("o", pid: 4, minX: 930)
        let left = placed("l", pid: 6, minX: 905)
        let next = advance(once, [a, first, second, left], state: Self.hiding)
        #expect(next.visibleBoundary == Self.boundary)
        #expect(next.visibleTags == [first.tagKey, second.tagKey])
    }

    @Test("a pass on another display clears the boundary, by origin or by bounds")
    func otherDisplayClears() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 2, minX: 1000)
        let roster = advance(PreferenceHidingRoster(), [a, right])
        let moved = BarDisplay(bounds: Self.display.bounds, originX: 1512, originY: 0)
        let wider = BarDisplay(bounds: BarBounds(minX: 0, maxX: 2560, minY: 0, barHeight: 33), originX: 0, originY: 0)
        for other in [moved, wider] {
            let next = advance(roster, [a, right], state: Self.hiding, display: other)
            #expect(next.visibleBoundary == nil)
            #expect(next.visibleTags.isEmpty)
        }
    }

    @Test("an added parked, stacked or frameless item, or the placeholder frame, is not visible")
    func onlyOnBarItemsAreVisible() {
        let a = placed("a", pid: 1, minX: 100)
        let roster = advance(PreferenceHidingRoster(), [a])
        let parked = placed("p", pid: 3, minX: 1000, position: .parked)
        let stacked = placed("s", pid: 4, minX: 1000, position: .stacked)
        let frameless = fixtureItem(identifier: "f", pid: 5, frame: nil, position: .noFrame)
        let placeholder = fixtureItem(identifier: "x", pid: 6, frame: barFrame(minX: 7, width: 14), position: .onBar)
        let infinite = fixtureItem(identifier: "i", pid: 7, frame: barFrame(minX: .infinity, width: 14), position: .onBar)
        let next = advance(roster, [a, parked, stacked, frameless, placeholder, infinite], state: Self.hiding)
        #expect(next.visibleTags.isEmpty)
    }

    @Test("the signature carries the visible tags")
    func signatureCarriesVisible() {
        let right = placed("r", pid: 2, minX: 1000)
        let roster = advance(PreferenceHidingRoster(), [placed("a", pid: 1, minX: 100), right])
        let signature = roster.signature(frontmostPID: 4, menuMaxX: 300, displayID: 1, spaceID: 2)
        #expect(signature.visibleItems == [right.tagKey])
    }
}
