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

    @Test("the policy's numbers stay inside what was measured")
    func policyWithinMeasurements() {
        // FINDINGS "The capture indicator, timed": never sooner than 10.2 s
        // after a burst's first capture, gone 20.5 s after its last.
        #expect(parameters.budget < 10.2)
        #expect(parameters.clearAfter > 20.5)
    }
}
