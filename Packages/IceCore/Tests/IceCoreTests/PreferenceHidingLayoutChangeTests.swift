import Testing
@testable import IceCore

/// Plan 2026-10-07-icebar-preference-hiding, D-e, through its one implementation:
/// the caller keeps the requested member set and calls
/// `PreferenceHidingStateRule.evaluate` again with `pendingLayoutChange:`. A layout
/// change drops verified to not verified pending re-check, and never asks for the
/// section to be shown.
@Suite("PreferenceHidingLayoutChange")
struct PreferenceHidingLayoutChangeTests {
    static let events: [PreferenceHidingLayoutChange] = [.displayChanged, .itemsChanged, .frontmostAppChanged, .menuWidthChanged, .spaceChanged]
    let hiddenClean = SectionItemCheck.checked(.hidden(folded: false))

    func item(_ identifier: String, pid: Int32, position: ItemPosition = .onBar) -> DiscoveredItem {
        fixtureItem(identifier: identifier, pid: pid, frame: barFrame(minX: Double(pid) * 40, width: 24), position: position)
    }

    func membership(_ items: [DiscoveredItem], previous: [TagKey] = []) -> PreferenceHidingMembership {
        let identifiers = Dictionary(uniqueKeysWithValues: items.map { ($0.key.pid, [$0.key.identifier]) })
        return PreferenceHidingMembership.resolve(
            leftOfDivider: items, previousMembers: previous, releasedTags: [], childIdentifiersByPID: identifiers
        )
    }

    func evaluate(
        _ members: PreferenceHidingMembership,
        preconditions: PreferenceHidingPreconditionResult = .ok,
        checks: [ItemKey: SectionItemCheck] = [:],
        pending: PreferenceHidingLayoutChange? = nil
    ) -> PreferenceHidingState {
        PreferenceHidingStateRule.evaluate(
            preconditions: preconditions, membership: members, lengthApplied: true,
            checks: checks, pendingLayoutChange: pending
        )
    }

    @Test("D-e: verified hidden drops to not verified pending re-check, for each event", arguments: events)
    func verifiedDropsToNotVerified(event: PreferenceHidingLayoutChange) {
        let a = item("a", pid: 1)
        let members = membership([a])
        let checks = [a.key: hiddenClean]
        #expect(evaluate(members, checks: checks) == .verifiedHidden)
        let next = evaluate(members, checks: checks, pending: event)
        #expect(next == .requestedNotVerified(reasons: [.layoutChangePending(event)]))
        #expect(next.isIceBarOffered)
        #expect(!next.countsAsLabSuccess)
    }

    @Test("D-e: re-evaluating without the pending change (the re-check) verifies again")
    func recheckClearsPending() {
        let a = item("a", pid: 1)
        let members = membership([a])
        let checks = [a.key: hiddenClean]
        #expect(evaluate(members, checks: checks, pending: .itemsChanged) != .verifiedHidden)
        #expect(evaluate(members, checks: checks, pending: nil) == .verifiedHidden)
    }

    @Test("D-e: blocked stays blocked, with its reasons, for each event", arguments: events)
    func blockedStays(event: PreferenceHidingLayoutChange) {
        let reasons: [PreferenceHidingBlockReason] = [.discoveryIncomplete(.permissionDenied)]
        let a = item("a", pid: 1)
        let blocked = evaluate(membership([a]), preconditions: .blocked(reasons), checks: [a.key: hiddenClean], pending: event)
        #expect(blocked == .blocked(reasons: reasons))
        #expect(!blocked.isIceBarOffered)
    }

    @Test("D-e: visible / failed stays visible / failed for each event", arguments: events)
    func failedStays(event: PreferenceHidingLayoutChange) {
        let a = item("a", pid: 1)
        let failed = evaluate(membership([a]), checks: [a.key: .checked(.stillDrawn)], pending: event)
        #expect(failed == .visibleFailed(drawn: [a.tagKey]))
    }

    @Test("D-e: a not-verified state keeps its other reasons and gains the pending one", arguments: events)
    func notVerifiedKeepsReasonsAndGainsPending(event: PreferenceHidingLayoutChange) {
        let a = item("a", pid: 1)
        let without = evaluate(membership([a]), checks: [a.key: .skipped(.noReference)])
        #expect(without == .requestedNotVerified(reasons: [.noReference, .membersUnchecked([a.tagKey])]))
        let with = evaluate(membership([a]), checks: [a.key: .skipped(.noReference)], pending: event)
        #expect(with == .requestedNotVerified(reasons: [.noReference, .membersUnchecked([a.tagKey]), .layoutChangePending(event)]))
    }

    @Test("D-e: the members passed are untouched, so the requested set is kept across the change")
    func requestedSetIsKept() {
        let a = item("a", pid: 1)
        let gone = TagKey(namespace: "com.example.gone", title: "g/p9")
        let members = membership([a], previous: [gone])
        let before = members.members
        _ = evaluate(members, checks: [a.key: hiddenClean], pending: .menuWidthChanged)
        #expect(members.members == before)
        #expect(members.members.map(\.tag) == [a.tagKey, gone])
    }

    @Test("D-e: a long menu is not a reason to show the section; no event yields a blocked state by itself")
    func longMenuNeverShows() {
        let a = item("a", pid: 1)
        let members = membership([a])
        let scenarios: [[ItemKey: SectionItemCheck]] = [[a.key: hiddenClean], [:], [a.key: .checked(.stillDrawn)]]
        for checks in scenarios {
            let next = evaluate(members, checks: checks, pending: .menuWidthChanged)
            #expect(next.isIceBarOffered)
            if case .blocked = next { Issue.record("a layout change must not block") }
        }
    }

    // MARK: - Derived from two signatures, not classified by hand (T3b)

    func signature(
        visible: [String] = ["v1"],
        hidden: [String] = ["h1"],
        alwaysHidden: [String] = [],
        frontmostPID: Int32? = 10,
        menuMaxX: Double? = 400,
        displayID: UInt32? = 1,
        spaceID: UInt64? = 7
    ) -> LayoutSignature {
        LayoutSignature(
            visible: visible, hidden: hidden, alwaysHidden: alwaysHidden, frontmostPID: frontmostPID,
            menuMaxX: menuMaxX, displayID: displayID, spaceID: spaceID
        )
    }

    @Test("equal signatures are no change")
    func noChange() {
        #expect(PreferenceHidingLayoutChange.between(signature(), signature()) == nil)
    }

    @Test("each field's difference is its own change")
    func eachField() {
        let old = signature()
        #expect(PreferenceHidingLayoutChange.between(old, signature(displayID: 2)) == .displayChanged)
        #expect(PreferenceHidingLayoutChange.between(old, signature(visible: ["v1", "v2"])) == .itemsChanged)
        #expect(PreferenceHidingLayoutChange.between(old, signature(hidden: [])) == .itemsChanged)
        #expect(PreferenceHidingLayoutChange.between(old, signature(alwaysHidden: ["a1"])) == .itemsChanged)
        #expect(PreferenceHidingLayoutChange.between(old, signature(frontmostPID: 11)) == .frontmostAppChanged)
        #expect(PreferenceHidingLayoutChange.between(old, signature(menuMaxX: 900)) == .menuWidthChanged)
        #expect(PreferenceHidingLayoutChange.between(old, signature(menuMaxX: nil)) == .menuWidthChanged)
        #expect(PreferenceHidingLayoutChange.between(old, signature(spaceID: 8)) == .spaceChanged)
    }

    @Test("several differences at once: the structural one is named, display before items")
    func structuralWins() {
        let old = signature()
        #expect(PreferenceHidingLayoutChange.between(old, signature(hidden: [], frontmostPID: 11, spaceID: 8)) == .itemsChanged)
        #expect(PreferenceHidingLayoutChange.between(old, signature(hidden: [], displayID: 2)) == .displayChanged)
        #expect(PreferenceHidingLayoutChange.between(old, signature(frontmostPID: 11, menuMaxX: 900, spaceID: 8)) == .frontmostAppChanged)
    }

    @Test("the roster may be wrong only after a display or item change; a Space id alone says nothing of it")
    func whichAreStructural() {
        #expect(PreferenceHidingLayoutChange.displayChanged.isStructural)
        #expect(PreferenceHidingLayoutChange.itemsChanged.isStructural)
        #expect(!PreferenceHidingLayoutChange.frontmostAppChanged.isStructural)
        #expect(!PreferenceHidingLayoutChange.menuWidthChanged.isStructural)
        #expect(!PreferenceHidingLayoutChange.spaceChanged.isStructural)
    }
}
