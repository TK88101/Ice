import Testing
@testable import IceCore

/// Plan 2026-10-07-icebar-preference-hiding, D-a: who is a member of the
/// hidden set, who blocks hiding, and what a previously known member does when
/// the current read no longer supports it.
@Suite("PreferenceHidingMembership")
struct PreferenceHidingMembershipTests {
    func item(
        _ identifier: String,
        pid: Int32 = 1,
        basis: IdentityBasis = .declared,
        position: ItemPosition = .onBar,
        childIndex: Int? = nil
    ) -> DiscoveredItem {
        let frame: BarRect? = position == .noFrame ? nil : barFrame(minX: 100, width: 24)
        return fixtureItem(identifier: identifier, pid: pid, childIndex: childIndex, basis: basis, frame: frame, position: position)
    }

    func resolve(
        _ items: [DiscoveredItem],
        previous: [TagKey] = [],
        released: Set<TagKey> = [],
        identifiers: [Int32: [String?]]? = nil
    ) -> PreferenceHidingMembership {
        let derived = identifiers ?? Dictionary(grouping: items, by: { $0.key.pid }).mapValues { $0.map { $0.key.identifier } }
        return PreferenceHidingMembership.resolve(
            leftOfDivider: items, previousMembers: previous, releasedTags: released, childIdentifiersByPID: derived
        )
    }

    /// Whether the state rule would hold the state at "not verified" because of
    /// a stale or stacked member (D-a): the cap is asserted through `evaluate`.
    func caps(_ membership: PreferenceHidingMembership) -> Bool {
        let checks = Dictionary(
            membership.members.compactMap(\.key).map { ($0, SectionItemCheck.checked(.hidden(folded: false))) },
            uniquingKeysWith: { first, _ in first }
        )
        let state = PreferenceHidingStateRule.evaluate(
            preconditions: .ok, membership: membership, lengthApplied: true, checks: checks, pendingLayoutChange: nil
        )
        guard case .requestedNotVerified(let reasons) = state else { return false }
        return reasons.contains {
            switch $0 {
            case .staleMembers, .stackedMembers: return true
            default: return false
            }
        }
    }

    // MARK: - D-a: declared and unnamed items are members

    @Test("D-a: a declared item left of the divider is a ready, pressable member")
    func declaredIsReadyMember() throws {
        let a = item("a")
        let result = resolve([a])
        let member = try #require(result.members.first)
        #expect(result.members.count == 1)
        #expect(member.tag == a.tagKey)
        #expect(member.condition == .ready)
        #expect(member.isPressable)
        #expect(!caps(result))
        #expect(result.blockers.isEmpty)
    }

    @Test("D-a: an unnamed item left of the divider is a ready, pressable member")
    func unnamedIsReadyMember() throws {
        let u = item("", basis: .unnamed)
        let result = resolve([u])
        let member = try #require(result.members.first)
        #expect(member.key == u.key)
        #expect(member.condition == .ready)
        #expect(member.isPressable)
    }

    @Test("D-a: members keep the order of the read")
    func membersKeepReadOrder() {
        let result = resolve([item("b", pid: 2), item("a", pid: 1)])
        #expect(result.members.map(\.key?.identifier) == ["b", "a"])
    }

    // MARK: - D-a: positional blocks

    @Test("D-a: a positional item is a blocker, named, and is not a member")
    func positionalIsBlockerNotMember() throws {
        let p = item("clock", basis: .positional, childIndex: 2)
        let result = resolve([p, item("a", pid: 2)], identifiers: [1: ["clock", "x", "clock"], 2: ["a"]])
        let blocker = try #require(result.blockers.first)
        #expect(result.blockers.count == 1)
        #expect(blocker.key == p.key)
        #expect(blocker.tag == p.tagKey)
        #expect(result.members.map(\.tag) == [item("a", pid: 2).tagKey])
    }

    @Test("D-a: a declared member that became positional is a blocker and stays listed as stale under its previous tag")
    func positionalFormerMemberStaysListedStale() throws {
        let declared = item("clock")
        let p = item("clock", basis: .positional, childIndex: 0)
        let result = resolve([p], previous: [declared.tagKey], identifiers: [1: ["clock", "clock"]])
        #expect(result.blockers.map(\.key) == [p.key])
        #expect(result.blockers.map(\.tag) == [p.tagKey])
        let member = try #require(result.members.first)
        #expect(result.members.count == 1, "no second missingFromRead entry for the previous tag")
        #expect(member.tag == declared.tagKey)
        #expect(member.key == p.key)
        #expect(member.condition == .stale(.ambiguousOrUnreadable))
        #expect(!member.isPressable)
        #expect(declared.tagKey != p.tagKey)
    }

    @Test("D-a: two positional siblings of one former member are two blockers and one stale member")
    func positionalSiblingsAreOneStaleMember() {
        let declared = item("clock")
        let first = item("clock", basis: .positional, childIndex: 0)
        let second = item("clock", basis: .positional, childIndex: 1)
        let result = resolve([first, second], previous: [declared.tagKey], identifiers: [1: ["clock", "clock"]])
        #expect(result.blockers.map(\.key) == [first.key, second.key])
        #expect(result.members.map(\.tag) == [declared.tagKey])
        #expect(result.members.first?.key == first.key)
    }

    @Test("D-a: a unnamed member that became positional is matched by its base tag too")
    func unnamedFormerMemberBecamePositional() {
        let unnamed = item("", basis: .unnamed)
        let p = item("", basis: .positional, childIndex: 2)
        let result = resolve([p], previous: [unnamed.tagKey], identifiers: [1: ["", ""]])
        #expect(result.members.map(\.tag) == [unnamed.tagKey])
        #expect(result.members.first?.condition == .stale(.ambiguousOrUnreadable))
    }

    // MARK: - D-a: stale, stacked, addressability

    @Test("D-a: a stacked member stays listed and pressable and caps at not verified")
    func stackedMemberIsPressableAndCaps() throws {
        let result = resolve([item("a", position: .stacked)])
        let member = try #require(result.members.first)
        #expect(member.condition == .stacked)
        #expect(member.isPressable)
        #expect(caps(result))
    }

    @Test("D-a: a member that is ambiguous in the current read is listed, stale, disabled and caps")
    func ambiguousMemberIsStale() throws {
        let result = resolve([item("a")], identifiers: [1: ["a", "a"]])
        let member = try #require(result.members.first)
        #expect(member.condition == .stale(.ambiguousOrUnreadable))
        #expect(!member.isPressable)
        #expect(caps(result))
        #expect(result.staleMembers.count == 1)
    }

    @Test("D-a: a member whose process has no readable children is stale")
    func unreadableMemberIsStale() throws {
        let result = resolve([item("a")], identifiers: [:])
        #expect(result.members.first?.condition == .stale(.ambiguousOrUnreadable))
    }

    @Test("D-a: addressability is derived from PressTargetRule, so a non-item sibling does not make it ambiguous")
    func nonItemSiblingDoesNotMakeAmbiguity() {
        let result = resolve([item("a")], identifiers: [1: [nil, "a", "b"]])
        #expect(result.members.first?.condition == .ready)
    }

    @Test("D-a: an unnamed member sharing the empty identifier with another child is stale")
    func unnamedAmbiguousIsStale() {
        let result = resolve([item("", basis: .unnamed)], identifiers: [1: ["", ""]])
        #expect(result.members.first?.condition == .stale(.ambiguousOrUnreadable))
    }

    @Test("D-a: a new item that is not uniquely addressable is listed stale, not silently ignored")
    func newUnaddressableIsStaleMember() {
        let result = resolve([item("a")], previous: [], identifiers: [1: []])
        #expect(result.members.first?.condition == .stale(.ambiguousOrUnreadable))
    }

    // MARK: - D-a: parked, frameless, never newly selected

    @Test("D-a: a parked item that was not a member is not selected, and nothing is reported for it")
    func parkedNewItemIsNotSelected() {
        let result = resolve([item("a", position: .parked)])
        #expect(result.members.isEmpty)
        #expect(result.blockers.isEmpty)
        #expect(!caps(result))
    }

    @Test("D-a: a frameless item that was not a member is not selected, and nothing is reported for it")
    func framelessNewItemIsNotSelected() {
        let result = resolve([item("a", position: .noFrame)])
        #expect(result.members.isEmpty)
        #expect(result.blockers.isEmpty)
    }

    @Test("D-a stale rule: a previously known member that is now parked stays listed, stale, disabled, caps")
    func formerMemberNowParkedIsStale() throws {
        let parked = item("a", position: .parked)
        let result = resolve([parked], previous: [parked.tagKey])
        let member = try #require(result.members.first)
        #expect(member.condition == .stale(.parked))
        #expect(!member.isPressable)
        #expect(caps(result))
    }

    @Test("D-a stale rule: a previously known member that is now frameless stays listed, stale, disabled, caps")
    func formerMemberNowFramelessIsStale() {
        let frameless = item("a", position: .noFrame)
        let result = resolve([frameless], previous: [frameless.tagKey])
        #expect(result.members.first?.condition == .stale(.noFrame))
        #expect(caps(result))
    }

    @Test("D-a stale rule: a previously known member missing from the read stays listed, stale, disabled, caps")
    func formerMemberMissingIsStale() throws {
        let gone = TagKey(namespace: "com.example.gone", title: "x/p9")
        let result = resolve([item("a")], previous: [gone])
        #expect(result.members.count == 2)
        let missing = try #require(result.members.last)
        #expect(missing.tag == gone)
        #expect(missing.key == nil)
        #expect(missing.condition == .stale(.missingFromRead))
        #expect(!missing.isPressable)
        #expect(caps(result))
    }

    @Test("D-a stale rule: a previously known member that is ambiguous now stays listed, stale, disabled, caps")
    func formerMemberNowAmbiguousIsStale() {
        let a = item("a")
        let result = resolve([a], previous: [a.tagKey], identifiers: [1: ["a", "a"]])
        #expect(result.members.first?.condition == .stale(.ambiguousOrUnreadable))
        #expect(caps(result))
    }

    @Test("D-a stale rule: a previous member the read shows released (moved right of the divider) is dropped, not stale")
    func releasedFormerMemberIsDropped() {
        let moved = TagKey(namespace: "com.example.moved", title: "m/p3")
        let result = resolve([item("a")], previous: [moved], released: [moved])
        #expect(result.members.map(\.tag) == [item("a").tagKey])
        #expect(!caps(result))
    }

    // MARK: - boundaries

    @Test("boundary: an empty read with no previous members has no members, blockers or cap")
    func emptyRead() {
        let result = resolve([])
        #expect(result.members.isEmpty)
        #expect(result.blockers.isEmpty)
        #expect(!caps(result))
    }

    @Test("boundary: an empty read with previous members lists them all as missing")
    func emptyReadWithPrevious() {
        let tags = [TagKey(namespace: "n", title: "a/p1"), TagKey(namespace: "n", title: "b/p2")]
        let result = resolve([], previous: tags)
        #expect(result.members.map(\.tag) == tags)
        #expect(result.members.allSatisfy { $0.condition == .stale(.missingFromRead) })
    }

    @Test("boundary: a repeated previous member is listed once")
    func repeatedPreviousListedOnce() {
        let tag = TagKey(namespace: "n", title: "a/p1")
        let result = resolve([], previous: [tag, tag])
        #expect(result.members.count == 1)
    }

    @Test("boundary: two items with the same tag are one stale member, never two pressable cells")
    func duplicateTagIsOneStaleMember() {
        let a = item("a")
        let result = resolve([a, a])
        #expect(result.members.count == 1)
        #expect(result.members.first?.condition == .stale(.ambiguousOrUnreadable))
    }

    @Test("boundary: every identity basis against every position")
    func basisByPositionMatrix() {
        let bases: [IdentityBasis] = [.declared, .unnamed, .positional]
        let positions: [ItemPosition] = [.onBar, .parked, .stacked, .noFrame]
        for basis in bases {
            for position in positions {
                let identifier = basis == .unnamed ? "" : "x"
                let i = item(identifier, basis: basis, position: position, childIndex: basis == .positional ? 0 : nil)
                let children = basis == .positional ? [identifier, identifier] : [identifier]
                let result = resolve([i], identifiers: [1: children])
                switch (basis, position) {
                case (.positional, _):
                    #expect(result.blockers.count == 1, "positional \(position) blocks")
                    #expect(result.members.isEmpty, "positional \(position) is no member")
                case (_, .parked), (_, .noFrame):
                    #expect(result.members.isEmpty, "\(basis) \(position) is never newly selected")
                case (_, .stacked):
                    #expect(result.members.first?.condition == .stacked)
                case (_, .onBar):
                    #expect(result.members.first?.condition == .ready)
                }
            }
        }
    }

    @Test("boundary: Ice's own icon, a non-AX record or a dropped record never reaches this rule (not handled here)")
    func ownAndNonAXRecordsAreTheCallersFilter() {
        // ItemCatalog drops non-AXMenuBarItem records before membership
        // (ItemCatalog.swift:123-131) and keeps Ice's own items out of
        // DiscoveredItemSet.items; this rule only sees what the caller hands in.
        let result = resolve([])
        #expect(result.members.isEmpty)
    }

    // MARK: - the one sanctioned geometry: resolve(set:)

    func placed(
        _ identifier: String,
        pid: Int32 = 1,
        minX: Double?,
        basis: IdentityBasis = .declared,
        position: ItemPosition = .onBar,
        childIndex: Int? = nil
    ) -> DiscoveredItem {
        let frame = minX.map { barFrame(minX: $0, width: 24) }
        return fixtureItem(identifier: identifier, pid: pid, childIndex: childIndex, basis: basis, frame: frame, position: position)
    }

    /// A usable divider with minX 500, width 20 (midX 510).
    let usableDivider = DividerReading(frame: barFrame(minX: 500, width: 20), isUsable: true)

    /// Collapsed for 5 s, unchanged during the pass: a boundary DiscoveredCachePlan trusts.
    static let settled = DividerState(isEnabled: true, isCollapsed: true, collapsedFor: 5, changedDuringPass: false)

    func resolve(
        set items: [DiscoveredItem],
        divider: DividerReading?,
        state: DividerState = settled,
        previous: [TagKey] = []
    ) -> PreferenceHidingMembership {
        let identifiers = Dictionary(grouping: items, by: { $0.key.pid }).mapValues { $0.map { $0.key.identifier } }
        return PreferenceHidingMembership.resolve(
            set: fixtureSet(items: items, hiddenDivider: divider), hiddenDividerState: state,
            previousMembers: previous, childIdentifiersByPID: identifiers
        )
    }

    @Test("D-a, set: on an untrusted boundary (expanded, settling, changed during the pass) the roster is frozen: nothing released, nothing added (Codex round 3)", arguments: [
        DividerState(isEnabled: true, isCollapsed: false, collapsedFor: 0, changedDuringPass: false),
        DividerState(isEnabled: true, isCollapsed: true, collapsedFor: 0.2, changedDuringPass: false),
        DividerState(isEnabled: true, isCollapsed: true, collapsedFor: 5, changedDuringPass: true),
    ])
    func setUntrustedBoundaryFreezesRoster(state: DividerState) {
        let movedRight = placed("moved", pid: 1, minX: 600)
        let newLeft = placed("new", pid: 2, minX: 100)
        let result = resolve(set: [movedRight, newLeft], divider: usableDivider, state: state, previous: [movedRight.tagKey])
        #expect(result.members.map(\.tag) == [movedRight.tagKey])
    }

    @Test("D-a, set: items left of the divider's minX are members and items right of it are not")
    func setSplitsAtDividerMinX() {
        let left = placed("left", pid: 1, minX: 100)
        let right = placed("right", pid: 2, minX: 600)
        let result = resolve(set: [left, right], divider: usableDivider)
        #expect(result.members.map(\.tag) == [left.tagKey])
        #expect(result.blockers.isEmpty)
    }

    @Test("D-a, set: an item whose mid-x is exactly the divider's minX is right of it, not a member")
    func setBoundaryIsMinX() {
        // frame 488..512 -> midX 500 == divider minX
        let onTheLine = placed("line", pid: 1, minX: 488)
        let justLeft = placed("just", pid: 2, minX: 487)
        let result = resolve(set: [onTheLine, justLeft], divider: usableDivider)
        #expect(result.members.map(\.tag) == [justLeft.tagKey])
    }

    @Test("D-a, set: a previous member now right of the divider is released: dropped, not stale")
    func setReleasesMovedMember() {
        let moved = placed("moved", pid: 1, minX: 600)
        let stays = placed("stays", pid: 2, minX: 100)
        let result = resolve(set: [moved, stays], divider: usableDivider, previous: [moved.tagKey, stays.tagKey])
        #expect(result.members.map(\.tag) == [stays.tagKey])
    }

    @Test("D-a, set: a parked item left of the divider that was a member is stale(.parked)")
    func setParkedFormerMemberIsStale() {
        let parked = placed("p", pid: 1, minX: -4000, position: .parked)
        let result = resolve(set: [parked], divider: usableDivider, previous: [parked.tagKey])
        #expect(result.members.map(\.tag) == [parked.tagKey])
        #expect(result.members.first?.condition == .stale(.parked))
    }

    @Test("D-a, set: a member parked right of the divider or below the bar is stale(.parked), not released (Codex round 2)")
    func setParkedRightFormerMemberIsStaleNotReleased() {
        let parkedRight = placed("right", pid: 1, minX: 5000, position: .parked)
        let ready = placed("ready", pid: 2, minX: 100)
        let result = resolve(set: [parkedRight, ready], divider: usableDivider, previous: [parkedRight.tagKey, ready.tagKey])
        #expect(Set(result.members.map(\.tag)) == [ready.tagKey, parkedRight.tagKey])
        #expect(result.staleMembers.map(\.condition) == [.stale(.parked)])
    }

    @Test("D-a, set: a parked item that was not a member is not selected and not reported")
    func setParkedNewItemIsIgnored() {
        let parked = placed("p", pid: 1, minX: -4000, position: .parked)
        let result = resolve(set: [parked], divider: usableDivider)
        #expect(result.members.isEmpty)
        #expect(result.blockers.isEmpty)
    }

    @Test("D-a, set: a frameless previous member is stale(.noFrame); a frameless non-member is ignored")
    func setFramelessItems() {
        let known = placed("known", pid: 1, minX: nil, position: .noFrame)
        let stranger = placed("stranger", pid: 2, minX: nil, position: .noFrame)
        let result = resolve(set: [known, stranger], divider: usableDivider, previous: [known.tagKey])
        #expect(result.members.map(\.tag) == [known.tagKey])
        #expect(result.members.first?.condition == .stale(.noFrame))
    }

    @Test("D-a, set: an unusable divider gives no members from the read and keeps previous members stale missingFromRead")
    func setUnusableDividerKeepsPreviousAsMissing() {
        let known = placed("known", pid: 1, minX: 100)
        let stranger = placed("stranger", pid: 2, minX: 50)
        let dividers: [DividerReading?] = [
            nil,
            DividerReading(frame: barFrame(minX: 500, width: 20), isUsable: false),
            DividerReading(frame: nil, isUsable: false),
            DividerReading(frame: BarRect(minX: 500, minY: 4.5, width: 20, height: .nan), isUsable: true),
            DividerReading(frame: BarRect(minX: .nan, minY: 4.5, width: 20, height: 24), isUsable: true),
        ]
        for divider in dividers {
            let result = resolve(set: [known, stranger], divider: divider, previous: [known.tagKey])
            #expect(result.members.map(\.tag) == [known.tagKey], "\(String(describing: divider))")
            #expect(result.members.first?.key == nil)
            #expect(result.members.first?.condition == .stale(.missingFromRead))
            #expect(result.blockers.isEmpty)
        }
    }

    @Test("D-a, set: a positional item left of the divider blocks, and one right of it does not")
    func setPositionalBlocksOnlyLeft() {
        let left = placed("clock", pid: 1, minX: 100, basis: .positional, childIndex: 0)
        let right = placed("clock", pid: 1, minX: 600, basis: .positional, childIndex: 1)
        let result = PreferenceHidingMembership.resolve(
            set: fixtureSet(items: [left, right], hiddenDivider: usableDivider), hiddenDividerState: Self.settled,
            previousMembers: [], childIdentifiersByPID: [1: ["clock", "clock"]]
        )
        #expect(result.blockers.map(\.key) == [left.key])
        #expect(result.members.isEmpty)
    }

    @Test("D-a, set: a previous member that became positional and moved right of the divider is released by its base tag")
    func setReleasesBasisChangedMember() {
        let before = placed("clock", pid: 1, minX: 100)
        let nowRight = placed("clock", pid: 1, minX: 600, basis: .positional, childIndex: 1)
        let other = placed("clock", pid: 1, minX: 700, basis: .positional, childIndex: 2)
        let result = resolve(set: [nowRight, other], divider: usableDivider, previous: [before.tagKey])
        #expect(result.members.isEmpty, "released, not stale missingFromRead")
        #expect(result.blockers.isEmpty)
    }

    @Test("D-a, set: a previous member that became positional and is still left of the divider is a blocker and one stale member")
    func setBasisChangedMemberStaysStale() {
        let before = placed("clock", pid: 1, minX: 100)
        let nowLeft = placed("clock", pid: 1, minX: 100, basis: .positional, childIndex: 0)
        let result = resolve(set: [nowLeft], divider: usableDivider, previous: [before.tagKey])
        #expect(result.blockers.map(\.key) == [nowLeft.key])
        #expect(result.members.map(\.tag) == [before.tagKey])
        #expect(result.members.first?.condition == .stale(.ambiguousOrUnreadable))
    }

    @Test("D-a, set: a frameless item that became positional is matched by its base tag")
    func setFramelessPositionalFormerMember() {
        let before = placed("clock", pid: 1, minX: 100)
        let frameless = placed("clock", pid: 1, minX: nil, basis: .positional, position: .noFrame, childIndex: 0)
        let result = resolve(set: [frameless], divider: usableDivider, previous: [before.tagKey])
        #expect(result.members.map(\.tag) == [before.tagKey])
        #expect(result.members.first?.condition == .stale(.ambiguousOrUnreadable))
    }

    // MARK: - A member whose process has exited (T3b, G1)

    @Test("T3b G1: a previous member is dropped only when the process of its last read key no longer exists")
    func exitedProcessIsDropped() {
        let a = item("a", pid: 1)
        let b = item("b", pid: 2)
        let carried = PreferenceHidingMembership.carried(
            previous: [a.tagKey, b.tagKey], lastKeys: [a.tagKey: a.key, b.tagKey: b.key], hasExited: { $0 == 2 }
        )
        #expect(carried == [a.tagKey])
    }

    @Test("T3b G1: a live process keeps its member, read or not, in the listed order")
    func liveProcessIsKept() {
        let a = item("a", pid: 1)
        let b = item("b", pid: 2)
        let tags = [b.tagKey, a.tagKey]
        let carried = PreferenceHidingMembership.carried(
            previous: tags, lastKeys: [a.tagKey: a.key, b.tagKey: b.key], hasExited: { _ in false }
        )
        #expect(carried == tags)
    }

    @Test("T3b G1: a member with no recorded key is kept: nothing says its process is gone")
    func unknownKeyIsKept() {
        let a = item("a", pid: 1)
        let carried = PreferenceHidingMembership.carried(previous: [a.tagKey], lastKeys: [:], hasExited: { _ in true })
        #expect(carried == [a.tagKey])
    }
}
