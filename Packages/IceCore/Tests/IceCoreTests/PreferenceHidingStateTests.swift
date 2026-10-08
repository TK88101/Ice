import Testing
@testable import IceCore

/// Plan 2026-10-07-icebar-preference-hiding, D-b, D-c, D-d: the four states
/// derived from the preconditions, the membership, whether a length was
/// applied and the per-member pixel checks.
@Suite("PreferenceHidingStateRule")
struct PreferenceHidingStateTests {
    let hiddenClean = SectionItemCheck.checked(.hidden(folded: false))

    func item(_ identifier: String, pid: Int32, position: ItemPosition = .onBar) -> DiscoveredItem {
        fixtureItem(identifier: identifier, pid: pid, frame: barFrame(minX: Double(pid) * 40, width: 24), position: position)
    }

    func membership(_ items: [DiscoveredItem], previous: [TagKey] = [], addressable: Bool = true) -> PreferenceHidingMembership {
        let identifiers: [Int32: [String?]] = addressable
            ? Dictionary(uniqueKeysWithValues: items.map { ($0.key.pid, [$0.key.identifier]) })
            : [:]
        return PreferenceHidingMembership.resolve(
            leftOfDivider: items, previousMembers: previous, releasedTags: [], childIdentifiersByPID: identifiers
        )
    }

    func evaluate(
        _ members: PreferenceHidingMembership,
        preconditions: PreferenceHidingPreconditionResult = .ok,
        lengthApplied: Bool = true,
        checks: [ItemKey: SectionItemCheck] = [:],
        pending: PreferenceHidingLayoutChange? = nil
    ) -> PreferenceHidingState {
        PreferenceHidingStateRule.evaluate(
            preconditions: preconditions, membership: members, lengthApplied: lengthApplied,
            checks: checks, pendingLayoutChange: pending
        )
    }

    // MARK: - blocked, not attempted

    @Test("D-c: a failed precondition is blocked, not attempted, carrying every reason, whatever else is true")
    func blockedCarriesReasons() {
        let a = item("a", pid: 1)
        let reasons: [PreferenceHidingBlockReason] = [.iceIconNotRightOfDivider(.iconLeftOfDivider), .ownReadNotOk(.failed)]
        let result = evaluate(
            membership([a]), preconditions: .blocked(reasons), lengthApplied: true,
            checks: [a.key: hiddenClean]
        )
        #expect(result == .blocked(reasons: reasons))
        #expect(!result.isIceBarOffered)
        #expect(!result.countsAsLabSuccess)
    }

    // MARK: - verified hidden

    @Test("D-c: every member observed absent, no cap, is verified hidden")
    func allAbsentIsVerified() {
        let a = item("a", pid: 1), b = item("b", pid: 2)
        let result = evaluate(membership([a, b]), checks: [a.key: hiddenClean, b.key: hiddenClean])
        #expect(result == .verifiedHidden)
        #expect(result.isIceBarOffered)
        #expect(result.countsAsLabSuccess)
    }

    @Test("D-c: one member not observed absent is never verified")
    func oneMissingCheckIsNotVerified() {
        let a = item("a", pid: 1), b = item("b", pid: 2)
        let result = evaluate(membership([a, b]), checks: [a.key: hiddenClean])
        #expect(result == .requestedNotVerified(reasons: [.membersUnchecked([b.tagKey])]))
        #expect(!result.countsAsLabSuccess)
    }

    @Test("D-c: a check list shorter than the member list is not verified, naming who lacks a check")
    func shorterCheckListNamesTheRest() {
        let a = item("a", pid: 1), b = item("b", pid: 2), c = item("c", pid: 3)
        let result = evaluate(membership([a, b, c]), checks: [b.key: hiddenClean])
        #expect(result == .requestedNotVerified(reasons: [.membersUnchecked([a.tagKey, c.tagKey])]))
    }

    @Test("D-c: a check for a key that is not a member is ignored")
    func checkForNonMemberIsIgnored() {
        let a = item("a", pid: 1)
        let stranger = item("z", pid: 9)
        let verified = evaluate(membership([a]), checks: [a.key: hiddenClean, stranger.key: hiddenClean])
        #expect(verified == .verifiedHidden)
        let drawnStranger = evaluate(membership([a]), checks: [a.key: hiddenClean, stranger.key: .checked(.stillDrawn)])
        #expect(drawnStranger == .verifiedHidden)
    }

    @Test("D-c: an unverifiable pixel result is not proof of absence")
    func unverifiableIsNotProof() {
        let a = item("a", pid: 1)
        let result = evaluate(membership([a]), checks: [a.key: .checked(.unverifiable(.weakMatch))])
        #expect(result == .requestedNotVerified(reasons: [.membersUnchecked([a.tagKey])]))
    }

    // MARK: - empty member set

    @Test("D-c: an empty member set is never verified, it is requested-not-verified with no members")
    func emptyMemberSetIsNeverVerified() {
        let result = evaluate(membership([]), checks: [:])
        #expect(result == .requestedNotVerified(reasons: [.noMembers]))
        #expect(!result.countsAsLabSuccess)
        #expect(result.isIceBarOffered)
    }

    @Test("D-c: an empty member set stays unverified even when a stray check says hidden")
    func emptyMemberSetIgnoresStrayChecks() {
        let stranger = item("z", pid: 9)
        let result = evaluate(membership([]), checks: [stranger.key: hiddenClean])
        #expect(result == .requestedNotVerified(reasons: [.noMembers]))
    }

    // MARK: - hiding requested, not verified

    @Test("D-c: no length applied yet is requested-not-verified, and any old check is not consulted")
    func noLengthApplied() {
        let a = item("a", pid: 1)
        let result = evaluate(membership([a]), lengthApplied: false, checks: [a.key: .checked(.stillDrawn)])
        #expect(result == .requestedNotVerified(reasons: [.lengthNotApplied]))
    }

    @Test("D-c: no reference is named as such")
    func noReference() {
        let a = item("a", pid: 1)
        let result = evaluate(membership([a]), checks: [a.key: .skipped(.noReference)])
        #expect(result == .requestedNotVerified(reasons: [.noReference, .membersUnchecked([a.tagKey])]))
    }

    @Test("D-c: a refused baseline and a failed capture are named as capture refused", arguments: [
        SectionItemCheck.refusedAtBaseline(.noInk), .skipped(.captureFailed),
    ])
    func captureRefused(check: SectionItemCheck) {
        let a = item("a", pid: 1)
        let result = evaluate(membership([a]), checks: [a.key: check])
        #expect(result == .requestedNotVerified(reasons: [.captureRefused, .membersUnchecked([a.tagKey])]))
    }

    @Test("D-a, D-c: a stale member caps at not verified even when every other member is absent")
    func staleMemberCaps() {
        let a = item("a", pid: 1)
        let gone = TagKey(namespace: "com.example.gone", title: "g/p9")
        let result = evaluate(membership([a], previous: [gone]), checks: [a.key: hiddenClean])
        #expect(result == .requestedNotVerified(reasons: [.staleMembers([gone])]))
    }

    @Test("D-a, D-c: a stacked member caps at not verified, and the pixel check skipping it is not double-counted")
    func stackedMemberCaps() {
        let a = item("a", pid: 1), s = item("s", pid: 2, position: .stacked)
        let result = evaluate(membership([a, s]), checks: [a.key: hiddenClean, s.key: .skipped(.stacked)])
        #expect(result == .requestedNotVerified(reasons: [.stackedMembers([s.tagKey])]))
    }

    @Test("D-a, D-c: a stale member whose process cannot be read is named stale, not unchecked")
    func unreadableMemberIsNamedStale() {
        let a = item("a", pid: 1)
        let result = evaluate(membership([a], addressable: false), checks: [a.key: hiddenClean])
        #expect(result == .requestedNotVerified(reasons: [.staleMembers([a.tagKey])]))
    }

    @Test("D-c: a pending layout change keeps the state at not verified until re-checked")
    func pendingLayoutChange() {
        let a = item("a", pid: 1)
        let result = evaluate(membership([a]), checks: [a.key: hiddenClean], pending: .frontmostAppChanged)
        #expect(result == .requestedNotVerified(reasons: [.layoutChangePending(.frontmostAppChanged)]))
    }

    @Test("D-c: reasons accumulate, none is dropped")
    func reasonsAccumulate() {
        let s = item("s", pid: 2, position: .stacked)
        let gone = TagKey(namespace: "com.example.gone", title: "g/p9")
        let result = evaluate(
            membership([s], previous: [gone]), lengthApplied: false, checks: [:], pending: .itemsChanged
        )
        #expect(result == .requestedNotVerified(reasons: [
            .lengthNotApplied, .staleMembers([gone]), .stackedMembers([s.tagKey]), .layoutChangePending(.itemsChanged),
        ]))
    }

    // MARK: - visible / failed

    @Test("D-c: a member observed drawn is visible / failed, naming it")
    func drawnMemberFails() {
        let a = item("a", pid: 1), b = item("b", pid: 2)
        let result = evaluate(membership([a, b]), checks: [a.key: hiddenClean, b.key: .checked(.stillDrawn)])
        #expect(result == .visibleFailed(drawn: [b.tagKey]))
        #expect(result.isIceBarOffered)
        #expect(!result.countsAsLabSuccess)
    }

    @Test("D-c: a drawn member is visible / failed regardless of caps, pending changes and other reasons")
    func drawnBeatsCaps() {
        let a = item("a", pid: 1), s = item("s", pid: 2, position: .stacked)
        let gone = TagKey(namespace: "com.example.gone", title: "g/p9")
        let result = evaluate(
            membership([a, s], previous: [gone]), checks: [a.key: .checked(.stillDrawn)], pending: .menuWidthChanged
        )
        #expect(result == .visibleFailed(drawn: [a.tagKey]))
    }

    @Test("D-c: several drawn members are all named, in member order")
    func severalDrawn() {
        let a = item("a", pid: 1), b = item("b", pid: 2)
        let result = evaluate(membership([a, b]), checks: [a.key: .checked(.stillDrawn), b.key: .checked(.stillDrawn)])
        #expect(result == .visibleFailed(drawn: [a.tagKey, b.tagKey]))
    }

    // MARK: - D-d: a fold is neither proof nor failure

    @Test("D-d: a fold the pixel check saw is not verified and not visible / failed")
    func foldIsNeitherProofNorFailure() {
        let a = item("a", pid: 1), b = item("b", pid: 2)
        let result = evaluate(membership([a, b]), checks: [a.key: hiddenClean, b.key: .checked(.hidden(folded: true))])
        #expect(result == .requestedNotVerified(reasons: [.foldSeen([b.tagKey])]))
        #expect(!result.countsAsLabSuccess)
        if case .visibleFailed = result { Issue.record("a fold must not read as visible / failed") }
    }

    @Test("D-d: a fold on every member is still not verified, and not a failure")
    func foldOnEveryMember() {
        let a = item("a", pid: 1)
        let result = evaluate(membership([a]), checks: [a.key: .checked(.hidden(folded: true))])
        #expect(result == .requestedNotVerified(reasons: [.foldSeen([a.tagKey])]))
    }

    @Test("D-d: a fold does not hide a member that was observed drawn")
    func foldDoesNotMaskDrawn() {
        let a = item("a", pid: 1), b = item("b", pid: 2)
        let result = evaluate(membership([a, b]), checks: [a.key: .checked(.hidden(folded: true)), b.key: .checked(.stillDrawn)])
        #expect(result == .visibleFailed(drawn: [b.tagKey]))
    }

    // MARK: - D-d: no shipped constant

    @Test("D-d: the state carries no length, only whether one was applied")
    func noLengthIsCarried() {
        let a = item("a", pid: 1)
        let applied = evaluate(membership([a]), lengthApplied: true, checks: [a.key: hiddenClean])
        let notApplied = evaluate(membership([a]), lengthApplied: false, checks: [a.key: hiddenClean])
        #expect(applied == .verifiedHidden)
        #expect(notApplied != .verifiedHidden)
    }

    // MARK: - predicates

    @Test("D-c: the IceBar is offered in every state but blocked; only verified counts as lab success")
    func predicates() {
        let states: [PreferenceHidingState] = [
            .blocked(reasons: [.ownReadNotOk(.failed)]), .verifiedHidden,
            .requestedNotVerified(reasons: [.noMembers]), .visibleFailed(drawn: []),
        ]
        #expect(states.map(\.isIceBarOffered) == [false, true, true, true])
        #expect(states.map(\.countsAsLabSuccess) == [false, true, false, false])
    }

    @Test("a check refused because its baseline is too old is its own reason, after a capture refusal, the member still unchecked")
    func staleBaselineIsItsOwnReason() {
        let a = fixtureItem(identifier: "a", pid: 1, frame: barFrame(minX: 40, width: 24))
        let b = fixtureItem(identifier: "b", pid: 2, frame: barFrame(minX: 80, width: 24))
        let membership = PreferenceHidingMembership.resolve(
            leftOfDivider: [a, b], previousMembers: [], releasedTags: [],
            childIdentifiersByPID: [1: ["a"], 2: ["b"]]
        )
        let state = PreferenceHidingStateRule.evaluate(
            preconditions: .ok, membership: membership, lengthApplied: true,
            checks: [a.key: .skipped(.baselineStale), b.key: .refusedAtBaseline(.noInk)],
            pendingLayoutChange: nil
        )
        #expect(state == .requestedNotVerified(reasons: [.captureRefused, .baselineStale, .membersUnchecked([a.tagKey, b.tagKey])]))
    }
}

