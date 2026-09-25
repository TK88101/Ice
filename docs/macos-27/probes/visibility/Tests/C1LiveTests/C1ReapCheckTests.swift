import Testing
@testable import C1Live

/// P0-6: "relaunch only after a discovery-confirmed reap; a teardown reap
/// failure is a safety stop needing attention." The confirmation itself is
/// this pure decision; the stage's own retry/timeout loop feeds it one
/// discovery attempt at a time.
@Suite("C1ReapCheck")
struct C1ReapCheckTests {
    @Test("none of the helper pids listed -> confirmed")
    func confirmedWhenNoneListed() {
        #expect(C1ReapCheck.confirmed(listedPIDs: [200, 201], helperPIDs: [10, 11, 12]))
    }

    @Test("a helper pid still listed -> not confirmed")
    func notConfirmedWhenStillListed() {
        #expect(!C1ReapCheck.confirmed(listedPIDs: [11, 200], helperPIDs: [10, 11, 12]))
    }

    @Test("a failed discovery pass (nil) is inconclusive, never confirmed")
    func failedPassNeverConfirms() {
        #expect(!C1ReapCheck.confirmed(listedPIDs: nil, helperPIDs: [10, 11, 12]))
    }

    @Test("no helpers were ever launched -> trivially confirmed, even with other items listed")
    func noHelpersIsTriviallyConfirmed() {
        #expect(C1ReapCheck.confirmed(listedPIDs: [200], helperPIDs: []))
    }

    @Test("an empty bar -> confirmed")
    func emptyBarConfirms() {
        #expect(C1ReapCheck.confirmed(listedPIDs: [], helperPIDs: [10]))
    }
}
