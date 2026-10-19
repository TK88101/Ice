import Testing
@testable import IceCore

/// When a capture session may start so that the system's capture indicator
/// cannot be in what it reads (plan 2026-10-09-lab-first-run-followup, S3
/// design D1): the block comes about ten seconds after a burst's first
/// capture and is gone some twenty after its last.
@Suite("CaptureBurstRule")
struct CaptureBurstRuleTests {
    let parameters = CaptureBurstParameters.standard

    func rule(captures: [Double]) -> CaptureBurstRule {
        captures.reduce(into: CaptureBurstRule()) { $0.noteCapture(at: $1) }
    }

    @Test("nothing captured yet: any session may start")
    func firstBurst() {
        #expect(CaptureBurstRule().decision(for: .baseline, now: 100) == .go)
        #expect(CaptureBurstRule().decision(for: .observation, now: 100) == .go)
    }

    @Test("a second observation that still fits the burst may start")
    func secondObservationFits() {
        // An observation's captures at 100...101.5; the next would end by 107.
        let rule = rule(captures: [100, 101.5])
        #expect(rule.decision(for: .observation, now: 104.5) == .go)
        #expect(rule.decision(for: .observation, now: 105.5) == .go)
    }

    @Test("a session that would pass the budget waits until the bar is clear of the last capture")
    func waitsForClear() {
        let rule = rule(captures: [100, 101.5])
        #expect(rule.decision(for: .observation, now: 105.6) == .wait(until: 123.5))
        #expect(rule.decision(for: .baseline, now: 123.4) == .wait(until: 123.5))
        #expect(rule.decision(for: .baseline, now: 123.5) == .go)
        #expect(rule.decision(for: .observation, now: 123.4) == .wait(until: 123.5))
        #expect(rule.decision(for: .observation, now: 123.5) == .go)
    }

    @Test("the burst is counted from its first capture, the wait from its last")
    func burstBounds() {
        var rule = rule(captures: [100, 104.2])
        #expect(rule.burstStart == 100)
        #expect(rule.decision(for: .observation, now: 107.2) == .wait(until: 126.2))
        // A capture taken all the same moves the wait, not the burst.
        rule.noteCapture(at: 109)
        #expect(rule.burstStart == 100)
        #expect(rule.decision(for: .observation, now: 110) == .wait(until: 131))
    }

    @Test("a capture after the bar was clear begins a new burst")
    func newBurst() {
        var rule = rule(captures: [100, 104.2])
        rule.noteCapture(at: 126.2)
        #expect(rule.burstStart == 126.2)
        #expect(rule.burstAge == 0)
        #expect(CaptureBurstRule().burstAge == nil)
        #expect(rule.decision(for: .observation, now: 129) == .go)
    }

    @Test("a baseline never joins a burst: what it does before its first capture is not bounded (Codex review)")
    func baselineNeedsAClearBar() {
        // An observation's burst with all but nothing used of its budget.
        let rule = rule(captures: [100, 100.3])
        #expect(rule.decision(for: .observation, now: 100.4) == .go)
        #expect(rule.decision(for: .baseline, now: 100.4) == .wait(until: 122.3))
    }

    @Test("a baseline has its burst to itself: once closed, nothing joins it however early")
    func closedBurst() {
        var rule = rule(captures: [100, 100.5])
        rule.closeBurst()
        #expect(rule.decision(for: .observation, now: 101) == .wait(until: 122.5))
        // The next burst is open again.
        rule.noteCapture(at: 122.5)
        #expect(rule.decision(for: .observation, now: 124) == .go)
    }

    // MARK: - Sessions (plan 2026-10-19-verify-in-a-clean-burst, D1 and D5)

    func session(_ reservation: CaptureBurstReservation) -> BurstSession? {
        if case .go(let session) = reservation { session } else { nil }
    }

    @Test("a session on a clear bar opens a burst of its own at once, as its first session")
    func sessionOpensBurst() {
        var rule = CaptureBurstRule()
        let first = session(rule.begin(.observation, now: 100))
        #expect(first == BurstSession(burstID: 1, ordinal: 1, burstStartedAt: 100))
        #expect(rule.burstStart == 100)
        // Its own captures do not open another.
        rule.noteCapture(at: 100.2)
        rule.noteCapture(at: 101.5)
        #expect(rule.finish(first!) == ObservationBurst(burstID: 1, ordinal: 1, burstStartedAt: 100, capturedAt: 101.5))
    }

    @Test("a session that joins a burst is its second, and one after the bar is clear the first of a new one")
    func sessionOrdinals() {
        var rule = CaptureBurstRule()
        _ = rule.begin(.observation, now: 100)
        rule.noteCapture(at: 101.5)
        #expect(session(rule.begin(.observation, now: 104)) == BurstSession(burstID: 1, ordinal: 2, burstStartedAt: 100))
        rule.noteCapture(at: 105.5)
        #expect(rule.begin(.observation, now: 106) == .wait(until: 127.5))
        #expect(session(rule.begin(.observation, now: 127.5)) == BurstSession(burstID: 2, ordinal: 1, burstStartedAt: 127.5))
    }

    @Test("a burst opened by a capture outside any session counts it as its first: a session joining it is the second")
    func outsideCaptureIsFirst() {
        var rule = rule(captures: [100])
        #expect(session(rule.begin(.observation, now: 101))?.ordinal == 2)
    }

    @Test("a baseline is a session too, and a closed burst takes no further one")
    func baselineSessionCloses() {
        var rule = CaptureBurstRule()
        #expect(session(rule.begin(.baseline, now: 100))?.ordinal == 1)
        rule.noteCapture(at: 104.2)
        rule.closeBurst()
        #expect(rule.begin(.observation, now: 105) == .wait(until: 126.2))
        #expect(session(rule.begin(.observation, now: 126.2)) == BurstSession(burstID: 2, ordinal: 1, burstStartedAt: 126.2))
    }

    @Test("a session whose burst is no longer the current one has no burst to report")
    func finishAfterAnotherBurst() {
        var rule = CaptureBurstRule()
        let old = session(rule.begin(.observation, now: 100))!
        rule.noteCapture(at: 130)
        #expect(rule.finish(old) == nil)
    }

    @Test("an observation's burst age is from the burst's start to the session's last capture, fixed when it ends")
    func observationBurstAge() {
        var rule = CaptureBurstRule()
        let first = session(rule.begin(.observation, now: 100))!
        rule.noteCapture(at: 102.5)
        let read = rule.finish(first)
        #expect(read?.age == 2.5)
        // A later capture moves the clock, not what was read.
        rule.noteCapture(at: 104)
        #expect(read?.age == 2.5)
    }

    @Test("the policy's numbers stay inside what was measured")
    func policyWithinMeasurements() {
        // FINDINGS "The capture indicator, timed": never sooner than 10.2 s
        // after a burst's first capture, gone 20.5 s after its last.
        #expect(parameters.budget < 10.2)
        #expect(parameters.clearAfter > 20.5)
    }
}
