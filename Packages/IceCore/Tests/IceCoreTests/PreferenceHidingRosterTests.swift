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
        exited: Set<Int32> = []
    ) -> PreferenceHidingRoster {
        roster.advanced(
            set: fixtureSet(items: items, hiddenDivider: Self.divider, completeness: completeness),
            hiddenDividerState: state,
            childIdentifiersByPID: children(items),
            iconPlacement: placement,
            hasExited: { exited.contains($0) }
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
}
