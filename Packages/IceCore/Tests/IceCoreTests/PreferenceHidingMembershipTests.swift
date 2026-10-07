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
        #expect(!result.capsAtNotVerified)
        #expect(result.blockers.isEmpty)
    }

    @Test("D-a: an unnamed item left of the divider is a ready, pressable member")
    func unnamedIsReadyMember() throws {
        let u = item("", basis: .unnamed)
        let result = resolve([u])
        let member = try #require(result.members.first)
        #expect(member.basis == .unnamed)
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

    @Test("D-a: a positional item that was a member is a blocker and stays listed as stale")
    func positionalFormerMemberStaysListedStale() throws {
        let declared = item("clock")
        let p = item("clock", basis: .positional, childIndex: 0)
        let result = resolve([p], previous: [p.tagKey], identifiers: [1: ["clock", "clock"]])
        #expect(result.blockers.map(\.key) == [p.key])
        let member = try #require(result.members.first)
        #expect(member.condition == .stale(.ambiguousOrUnreadable))
        #expect(!member.isPressable)
        #expect(declared.tagKey != p.tagKey)
    }

    // MARK: - D-a: stale, stacked, addressability

    @Test("D-a: a stacked member stays listed and pressable and caps at not verified")
    func stackedMemberIsPressableAndCaps() throws {
        let result = resolve([item("a", position: .stacked)])
        let member = try #require(result.members.first)
        #expect(member.condition == .stacked)
        #expect(member.isPressable)
        #expect(member.capsAtNotVerified)
        #expect(result.capsAtNotVerified)
    }

    @Test("D-a: a member that is ambiguous in the current read is listed, stale, disabled and caps")
    func ambiguousMemberIsStale() throws {
        let result = resolve([item("a")], identifiers: [1: ["a", "a"]])
        let member = try #require(result.members.first)
        #expect(member.condition == .stale(.ambiguousOrUnreadable))
        #expect(!member.isPressable)
        #expect(result.capsAtNotVerified)
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
        #expect(result.unselected.isEmpty)
    }

    // MARK: - D-a: parked, frameless, never newly selected

    @Test("D-a: a parked item is never newly selected, and is named as unselected")
    func parkedNewItemIsUnselected() {
        let parked = item("a", position: .parked)
        let result = resolve([parked])
        #expect(result.members.isEmpty)
        #expect(result.unselected == [PreferenceHidingUnselected(tag: parked.tagKey, reason: .parked)])
        #expect(!result.capsAtNotVerified)
    }

    @Test("D-a: a frameless item is never newly selected, and is named as unselected")
    func framelessNewItemIsUnselected() {
        let frameless = item("a", position: .noFrame)
        let result = resolve([frameless])
        #expect(result.members.isEmpty)
        #expect(result.unselected == [PreferenceHidingUnselected(tag: frameless.tagKey, reason: .noFrame)])
    }

    @Test("D-a stale rule: a previously known member that is now parked stays listed, stale, disabled, caps")
    func formerMemberNowParkedIsStale() throws {
        let parked = item("a", position: .parked)
        let result = resolve([parked], previous: [parked.tagKey])
        let member = try #require(result.members.first)
        #expect(member.condition == .stale(.parked))
        #expect(!member.isPressable)
        #expect(result.capsAtNotVerified)
        #expect(result.unselected.isEmpty)
    }

    @Test("D-a stale rule: a previously known member that is now frameless stays listed, stale, disabled, caps")
    func formerMemberNowFramelessIsStale() {
        let frameless = item("a", position: .noFrame)
        let result = resolve([frameless], previous: [frameless.tagKey])
        #expect(result.members.first?.condition == .stale(.noFrame))
        #expect(result.capsAtNotVerified)
    }

    @Test("D-a stale rule: a previously known member missing from the read stays listed, stale, disabled, caps")
    func formerMemberMissingIsStale() throws {
        let gone = TagKey(namespace: "com.example.gone", title: "x/p9")
        let result = resolve([item("a")], previous: [gone])
        #expect(result.members.count == 2)
        let missing = try #require(result.members.last)
        #expect(missing.tag == gone)
        #expect(missing.key == nil)
        #expect(missing.basis == nil)
        #expect(missing.condition == .stale(.missingFromRead))
        #expect(!missing.isPressable)
        #expect(result.capsAtNotVerified)
    }

    @Test("D-a stale rule: a previously known member that is ambiguous now stays listed, stale, disabled, caps")
    func formerMemberNowAmbiguousIsStale() {
        let a = item("a")
        let result = resolve([a], previous: [a.tagKey], identifiers: [1: ["a", "a"]])
        #expect(result.members.first?.condition == .stale(.ambiguousOrUnreadable))
        #expect(result.capsAtNotVerified)
    }

    @Test("D-a stale rule: a previous member the read shows released (moved right of the divider) is dropped, not stale")
    func releasedFormerMemberIsDropped() {
        let moved = TagKey(namespace: "com.example.moved", title: "m/p3")
        let result = resolve([item("a")], previous: [moved], released: [moved])
        #expect(result.members.map(\.tag) == [item("a").tagKey])
        #expect(!result.capsAtNotVerified)
    }

    // MARK: - boundaries

    @Test("boundary: an empty read with no previous members has no members, blockers or cap")
    func emptyRead() {
        let result = resolve([])
        #expect(result.members.isEmpty)
        #expect(result.blockers.isEmpty)
        #expect(result.unselected.isEmpty)
        #expect(!result.capsAtNotVerified)
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
                    #expect(result.unselected.count == 1)
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
}
