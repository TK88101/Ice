import Testing

@testable import IceCore

/// The behavior these tests pin down is what broke Ice on macOS 27: a cache pass
/// that failed still recorded the window identifiers it had observed, so the
/// "has the menu bar changed?" check answered "no" forever and no pass ever ran
/// again. The empty-list cases are the ones that actually bit -- on macOS 27 the
/// window list is empty, and an empty list compared against the initial empty
/// list reports "unchanged" unless validity is tracked separately from content.
@Suite("Menu bar item cache state")
struct MenuBarItemCacheStateTests {
    @Test("A fresh state caches even when the window list is empty")
    func freshStateCachesEmptyList() {
        let state = MenuBarItemCacheState()

        #expect(state.shouldCacheItems(for: []))
    }

    @Test("A fresh state caches a non-empty window list")
    func freshStateCachesNonEmptyList() {
        let state = MenuBarItemCacheState()

        #expect(state.shouldCacheItems(for: [1, 2, 3]))
    }

    @Test("An unchanged window list is not cached again after a success")
    func unchangedListIsSkippedAfterSuccess() {
        var state = MenuBarItemCacheState()

        state.commit(for: [1, 2, 3])

        #expect(!state.shouldCacheItems(for: [1, 2, 3]))
    }

    @Test("A changed window list is cached again after a success")
    func changedListIsCachedAfterSuccess() {
        var state = MenuBarItemCacheState()

        state.commit(for: [1, 2, 3])

        #expect(state.shouldCacheItems(for: [1, 2]))
    }

    @Test("A failed attempt does not suppress a retry of the same window list")
    func failureDoesNotSuppressRetryOfSameList() {
        var state = MenuBarItemCacheState()

        state.recordFailure()

        #expect(state.shouldCacheItems(for: [1, 2, 3]))
    }

    @Test("A failed attempt on an empty window list still retries")
    func failureOnEmptyListStillRetries() {
        var state = MenuBarItemCacheState()

        state.recordFailure()

        #expect(state.shouldCacheItems(for: []))
    }

    @Test("The first failure is reported")
    func firstFailureIsReported() {
        var state = MenuBarItemCacheState()

        #expect(state.recordFailure() == .report)
    }

    @Test("A repeated failure is not reported again")
    func repeatedFailureIsNotReported() {
        var state = MenuBarItemCacheState()

        state.recordFailure()

        #expect(state.recordFailure() == .alreadyReported)
    }

    @Test("A failure following a success is reported again")
    func failureAfterSuccessIsReportedAgain() {
        var state = MenuBarItemCacheState()

        state.recordFailure()
        state.commit(for: [1, 2, 3])

        #expect(state.recordFailure() == .report)
    }

    @Test("Committing after a failure reports the recovery")
    func commitAfterFailureReportsRecovery() {
        var state = MenuBarItemCacheState()

        state.recordFailure()

        #expect(state.commit(for: [1, 2, 3]) == .recovered)
    }

    @Test("Committing without a preceding failure reports nothing")
    func commitWithoutFailureReportsNothing() {
        var state = MenuBarItemCacheState()

        #expect(state.commit(for: [1, 2, 3]) == .unremarkable)
        #expect(state.commit(for: [4, 5]) == .unremarkable)
    }

    @Test("Invalidating forces the next pass to run")
    func invalidatingForcesNextPass() {
        var state = MenuBarItemCacheState()

        state.commit(for: [1, 2, 3])
        state.invalidate()

        #expect(state.shouldCacheItems(for: [1, 2, 3]))
    }

    @Test("Invalidating is not a failure, so the next failure is still reported")
    func invalidatingDoesNotCountAsFailure() {
        var state = MenuBarItemCacheState()

        state.recordFailure()
        state.invalidate()

        #expect(state.recordFailure() == .report)
    }

    @Test("Invalidating after a failure still forces the next pass")
    func invalidatingAfterFailureStillForcesNextPass() {
        var state = MenuBarItemCacheState()

        state.recordFailure()
        state.invalidate()

        #expect(state.shouldCacheItems(for: [1, 2, 3]))
    }
}
