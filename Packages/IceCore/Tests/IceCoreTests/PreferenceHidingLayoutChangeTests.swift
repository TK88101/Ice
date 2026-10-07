import Testing
@testable import IceCore

/// Plan 2026-10-07-icebar-preference-hiding, D-e: a layout change keeps the
/// requested set, drops verified to not verified pending re-check, and never
/// asks for the section to be shown.
@Suite("PreferenceHidingLayoutChange")
struct PreferenceHidingLayoutChangeTests {
    let events: [PreferenceHidingLayoutChange] = [.frontmostAppChanged, .menusCrossingNotch, .itemsAdded]

    @Test("D-e: verified hidden drops to not verified pending re-check, for each event", arguments: [
        PreferenceHidingLayoutChange.frontmostAppChanged, .menusCrossingNotch, .itemsAdded,
    ])
    func verifiedDropsToNotVerified(event: PreferenceHidingLayoutChange) {
        let next = PreferenceHidingState.verifiedHidden.afterLayoutChange(event)
        #expect(next == .requestedNotVerified(reasons: [.layoutChangePending(event)]))
        #expect(next.isIceBarOffered)
        #expect(!next.countsAsLabSuccess)
    }

    @Test("D-e: blocked stays blocked, with its reasons, until re-evaluated")
    func blockedStays() {
        let blocked = PreferenceHidingState.blocked(reasons: [.discoveryIncomplete(.permissionDenied)])
        for event in events {
            #expect(blocked.afterLayoutChange(event) == blocked)
        }
    }

    @Test("D-e: visible / failed stays as it is until re-evaluated")
    func failedStays() {
        let failed = PreferenceHidingState.visibleFailed(drawn: [TagKey(namespace: "n", title: "a/p1")])
        for event in events {
            #expect(failed.afterLayoutChange(event) == failed)
        }
    }

    @Test("D-e: a not-verified state keeps its reasons and gains the pending change")
    func notVerifiedKeepsReasonsAndGainsPending() {
        let state = PreferenceHidingState.requestedNotVerified(reasons: [.noReference])
        #expect(state.afterLayoutChange(.itemsAdded) == .requestedNotVerified(reasons: [.noReference, .layoutChangePending(.itemsAdded)]))
    }

    @Test("D-e: a second change replaces the pending one, it does not pile up")
    func secondChangeReplacesPending() {
        let state = PreferenceHidingState.verifiedHidden
            .afterLayoutChange(.frontmostAppChanged)
            .afterLayoutChange(.menusCrossingNotch)
        #expect(state == .requestedNotVerified(reasons: [.layoutChangePending(.menusCrossingNotch)]))
    }

    @Test("D-e: the evaluation keeps the requested member set, the checks' chevron record and the members")
    func evaluationKeepsMembers() {
        let a = fixtureItem(identifier: "a", pid: 1, frame: barFrame(minX: 40, width: 24))
        let members = PreferenceHidingMembership.resolve(
            leftOfDivider: [a], previousMembers: [], releasedTags: [], childIdentifiersByPID: [1: ["a"]]
        )
        let verified = PreferenceHidingStateRule.evaluate(
            preconditions: .ok, membership: members, lengthApplied: true,
            checks: [a.key: .checked(.hidden(folded: false))], chevronListed: true, pendingLayoutChange: nil
        )
        #expect(verified.state == .verifiedHidden)
        let changed = verified.afterLayoutChange(.itemsAdded)
        #expect(changed.members == verified.members)
        #expect(changed.chevronListed == true)
        #expect(changed.state == .requestedNotVerified(reasons: [.layoutChangePending(.itemsAdded)]))
    }

    @Test("D-e: a long menu is not a reason to show the section, the result is never a different member set or a blocked state")
    func longMenuNeverShows() {
        let states: [PreferenceHidingState] = [
            .verifiedHidden, .requestedNotVerified(reasons: []), .visibleFailed(drawn: []),
        ]
        for state in states {
            let next = state.afterLayoutChange(.menusCrossingNotch)
            #expect(next.isIceBarOffered)
            if case .blocked = next { Issue.record("a layout change must not block") }
        }
    }
}
