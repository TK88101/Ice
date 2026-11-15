import Testing
@testable import IceCore

/// What a blind pass does to the roster (plan 2026-11-15-blind-at-length, D2):
/// on macOS 27.2 a pass at a hiding length reads nothing left of the divider,
/// so the members, their keys and their tags are carried, and only what was
/// seen right of the divider can be read gone.
@Suite("PreferenceHidingRoster, blind at length")
struct PreferenceHidingRosterBlindTests {
    static let divider = DividerReading(frame: BarRect(minX: 900, minY: 4.5, width: 18, height: 24), isUsable: true)
    static let standard = DividerState(isEnabled: true, isCollapsed: true, collapsedFor: 5, changedDuringPass: false)
    static let hiding = DividerState(isEnabled: true, isCollapsed: false, collapsedFor: 0, changedDuringPass: false)
    static let display = BarDisplay(bounds: BarBounds(minX: 0, maxX: 1512, minY: 0, barHeight: 33), originX: 0, originY: 0)
    /// The hidden divider's right edge at standard length (`divider`).
    static let boundary = 918.0
    static let icon = fixtureItem(
        namespace: "io.github.tk88101.Ice", identifier: "Ice.ControlItem.Visible", pid: 99,
        frame: barFrame(minX: 1344, width: 35), isSelf: true
    )

    func placed(_ identifier: String, pid: Int32, minX: Double, position: ItemPosition = .onBar) -> DiscoveredItem {
        fixtureItem(identifier: identifier, pid: pid, frame: barFrame(minX: minX, width: 24), position: position)
    }

    func children(_ items: [DiscoveredItem]) -> [Int32: [String?]] {
        Dictionary(grouping: items, by: \.key.pid).mapValues { $0.map { $0.key.identifier } }
    }

    /// A pass at standard length: everything is read, the divider too.
    func trusted(_ roster: PreferenceHidingRoster, _ items: [DiscoveredItem]) -> PreferenceHidingRoster {
        roster.advanced(
            set: fixtureSet(items: items, visibleControlItem: Self.icon, hiddenDivider: Self.divider),
            hiddenDividerState: Self.standard, childIdentifiersByPID: children(items), iconPlacement: nil,
            hasExited: { _ in false }, display: Self.display
        )
    }

    /// A pass at the hiding length on 27.2: only `read` is listed (what is
    /// right of the divider), Ice's icon, no divider.
    func atLength(
        _ roster: PreferenceHidingRoster,
        _ read: [DiscoveredItem],
        holdsWrittenLength: Bool = true,
        state: DividerState = hiding,
        exited: Set<Int32> = [],
        display: BarDisplay = display
    ) -> PreferenceHidingRoster {
        roster.advanced(
            set: fixtureSet(items: read, visibleControlItem: Self.icon, ownRead: .identifiersMissing),
            hiddenDividerState: state, childIdentifiersByPID: children(read), iconPlacement: nil,
            hasExited: { exited.contains($0) }, display: display, holdsWrittenLength: holdsWrittenLength
        )
    }

    func signature(_ roster: PreferenceHidingRoster) -> LayoutSignature {
        roster.signature(frontmostPID: 4, menuMaxX: 300, displayID: 1, spaceID: 2)
    }

    @Test("a blind pass carries the members, their conditions and keys, and blocks nothing")
    func carriesMembers() {
        let a = placed("a", pid: 1, minX: 100)
        let stacked = placed("s", pid: 2, minX: 140, position: .stacked)
        let right = placed("r", pid: 3, minX: 1000)
        let roster = trusted(PreferenceHidingRoster(), [a, stacked, right])
        let blind = atLength(roster, [right])
        #expect(blind.isBlindAtLength)
        #expect(blind.membership == roster.membership)
        #expect(blind.membership.members.map(\.condition) == [.ready, .stacked])
        #expect(blind.lastKeys == roster.lastKeys)
        #expect(blind.preconditions == .ok)
    }

    @Test("the signature of a blind pass equals the trusted pass's before it: no layout change")
    func signatureUnchanged() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 3, minX: 1000)
        let roster = trusted(PreferenceHidingRoster(), [a, right])
        let blind = atLength(roster, [right])
        #expect(blind.itemTags == roster.itemTags)
        #expect(PreferenceHidingLayoutChange.between(signature(roster), signature(blind)) == nil)
        let again = atLength(blind, [right])
        #expect(PreferenceHidingLayoutChange.between(signature(blind), signature(again)) == nil)
    }

    @Test("a non-member left of the divider (piled on it) stays in the item tags")
    func piledNonMemberStays() {
        let a = placed("a", pid: 1, minX: 100)
        // Stacked, mid-x left of the divider's minX (900), reaching onto it: no member.
        let piled = placed("p", pid: 5, minX: 885, position: .stacked)
        let right = placed("r", pid: 3, minX: 1000)
        let roster = trusted(PreferenceHidingRoster(), [a, piled, right])
        #expect(roster.membership.members.map(\.tag) == [a.tagKey])
        let blind = atLength(roster, [right])
        #expect(blind.itemTags.contains(piled.tagKey))
        #expect(PreferenceHidingLayoutChange.between(signature(roster), signature(blind)) == nil)
    }

    @Test("with nothing read gone the boundary and the visible tags are kept")
    func keepsBoundary() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 3, minX: 1000)
        let blind = atLength(trusted(PreferenceHidingRoster(), [a, right]), [right])
        #expect(blind.visibleBoundary == Self.boundary)
        #expect(blind.visibleTags == [right.tagKey])
    }

    @Test("an item seen right of the divider and not read now is gone: out of the tags, the boundary cleared, no structural change")
    func visibleItemGone() {
        let a = placed("a", pid: 1, minX: 100)
        let r1 = placed("r", pid: 3, minX: 1000)
        let r2 = placed("s", pid: 4, minX: 1040)
        let roster = trusted(PreferenceHidingRoster(), [a, r1, r2])
        let blind = atLength(roster, [r1])
        #expect(Set(blind.itemTags) == Set([a.tagKey, r1.tagKey]))
        #expect(blind.visibleBoundary == nil)
        #expect(blind.visibleTags.isEmpty)
        #expect(blind.membership == roster.membership)
        #expect(PreferenceHidingLayoutChange.between(signature(roster), signature(blind)) == .visibleItemsChanged)
    }

    @Test("without a boundary nothing can be read gone: a later removal stays in the tags")
    func withoutBoundaryNothingIsGone() {
        let a = placed("a", pid: 1, minX: 100)
        let r1 = placed("r", pid: 3, minX: 1000)
        let r2 = placed("s", pid: 4, minX: 1040)
        let once = atLength(trusted(PreferenceHidingRoster(), [a, r1, r2]), [r1])
        let twice = atLength(once, [])
        #expect(twice.itemTags == once.itemTags)
        #expect(twice.isBlindAtLength)
    }

    @Test("an item new right of the divider joins the tags and is visible: a soft change")
    func visibleItemNew() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 3, minX: 1000)
        let roster = trusted(PreferenceHidingRoster(), [a, right])
        let new = placed("n", pid: 6, minX: 960)
        let blind = atLength(roster, [right, new])
        #expect(Set(blind.itemTags) == Set([a.tagKey, right.tagKey, new.tagKey]))
        #expect(blind.visibleTags == [right.tagKey, new.tagKey])
        #expect(PreferenceHidingLayoutChange.between(signature(roster), signature(blind)) == .visibleItemsChanged)
    }

    @Test("a member whose process exited leaves the roster and the tags: a soft change, as on a bar that lists it gone")
    func exitedMemberLeaves() {
        let a = placed("a", pid: 1, minX: 100)
        let b = placed("b", pid: 2, minX: 140)
        let right = placed("r", pid: 3, minX: 1000)
        let roster = trusted(PreferenceHidingRoster(), [a, b, right])
        let blind = atLength(roster, [right], exited: [2])
        #expect(blind.membership.members.map(\.tag) == [a.tagKey])
        #expect(blind.lastKeys == [a.tagKey: a.key])
        #expect(Set(blind.itemTags) == Set([a.tagKey, right.tagKey]))
        #expect(PreferenceHidingLayoutChange.between(signature(roster), signature(blind)) == .visibleItemsChanged)
    }

    @Test("the last member exits: the roster is empty and the next pass is not blind")
    func lastMemberExits() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 3, minX: 1000)
        let blind = atLength(trusted(PreferenceHidingRoster(), [a, right]), [right], exited: [1])
        #expect(blind.membership.members.isEmpty)
        let next = atLength(blind, [right])
        #expect(!next.isBlindAtLength)
        #expect(next.preconditions == .blocked([.ownReadNotOk(.identifiersMissing)]))
    }

    @Test("the same reading while Ice does not hold the length is no blind pass: members stale, blocked, as before")
    func notHeldIsNotBlind() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 3, minX: 1000)
        let next = atLength(trusted(PreferenceHidingRoster(), [a, right]), [right], holdsWrittenLength: false)
        #expect(!next.isBlindAtLength)
        #expect(next.membership.members.map(\.condition) == [.stale(.missingFromRead)])
        #expect(next.preconditions == .blocked([.ownReadNotOk(.identifiersMissing)]))
    }

    @Test("a pass over which the divider's state changed (the IceBar opening, a length applied or retired) carries the roster and blocks nothing")
    func straddlingPassCarries() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 3, minX: 1000)
        let roster = trusted(PreferenceHidingRoster(), [a, right])
        for isCollapsed in [false, true] {
            let changed = DividerState(isEnabled: true, isCollapsed: isCollapsed, collapsedFor: isCollapsed ? 5 : 0, changedDuringPass: true)
            let next = atLength(roster, [right], holdsWrittenLength: !isCollapsed, state: changed)
            #expect(next.isBlindAtLength)
            #expect(next.membership == roster.membership)
            #expect(next.preconditions == .ok)
        }
    }

    @Test("a missing divider at standard length blocks as before")
    func standardLengthBlocks() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 3, minX: 1000)
        let next = atLength(trusted(PreferenceHidingRoster(), [a, right]), [right], state: Self.standard)
        #expect(!next.isBlindAtLength)
        #expect(next.preconditions == .blocked([.ownReadNotOk(.identifiersMissing)]))
    }

    @Test("a trusted pass after a blind one resolves the roster again and is not blind")
    func trustedAgain() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 3, minX: 1000)
        let blind = atLength(trusted(PreferenceHidingRoster(), [a, right]), [right])
        let arrived = placed("n", pid: 7, minX: 60)
        let next = trusted(blind, [arrived, a, right])
        #expect(!next.isBlindAtLength)
        #expect(next.membership.members.map(\.tag) == [arrived.tagKey, a.tagKey])
    }

    @Test("a blind pass on another display keeps the members and clears the boundary")
    func otherDisplay() {
        let a = placed("a", pid: 1, minX: 100)
        let right = placed("r", pid: 3, minX: 1000)
        let roster = trusted(PreferenceHidingRoster(), [a, right])
        let moved = BarDisplay(bounds: Self.display.bounds, originX: 1512, originY: 0)
        let blind = atLength(roster, [right], display: moved)
        #expect(blind.membership == roster.membership)
        #expect(blind.visibleBoundary == nil)
        #expect(blind.itemTags == roster.itemTags)
    }
}
