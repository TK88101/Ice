import Testing
@testable import C1Core

/// Section 1's verdicts: PASS, (provisional) FAIL, safety stop (with its
/// "needing the owner's attention" escalation from section 4), and
/// INCONCLUSIVE.
@Suite("RunAccounting")
struct RunAccountingTests {
    /// A clean run that should PASS: the scan found a band, and all five
    /// smoke cycles pass every check.
    func passingInput() -> RunAccounting.Input {
        RunAccounting.Input(
            preflightEverPassed: true,
            capturesStayedUnreadable: false,
            scanReadings: [.stillDrawn, .hidden(folded: false), .stillDrawn],
            smokeReadings: Array(repeating: .hidden(folded: false), count: 5),
            smokeChecksPassed: Array(repeating: true, count: 5),
            safetyStop: nil
        )
    }

    @Test("a clean run -> PASS")
    func pass() {
        #expect(RunAccounting.decide(passingInput()) == .pass)
    }

    @Test("preflight never passed -> INCONCLUSIVE")
    func preflightNeverPassed() {
        var input = passingInput()
        input.preflightEverPassed = false
        #expect(RunAccounting.decide(input) == .inconclusive("preflight never passed or captures stayed unreadable"))
    }

    @Test("captures stayed unreadable -> INCONCLUSIVE")
    func capturesUnreadable() {
        var input = passingInput()
        input.capturesStayedUnreadable = true
        #expect(RunAccounting.decide(input) == .inconclusive("preflight never passed or captures stayed unreadable"))
    }

    @Test("no scanned length gave hidden(folded: false) -> provisional FAIL")
    func noBandFound() {
        var input = passingInput()
        input.scanReadings = [.stillDrawn, .hidden(folded: true), .refused]
        #expect(RunAccounting.decide(input) == .provisionalFail("no scanned length gave hidden(folded: false)"))
    }

    @Test("more than one smoke refusal -> provisional FAIL, named as such")
    func multipleSmokeRefusals() {
        var input = passingInput()
        input.smokeReadings = [.refused, .refused, .hidden(folded: false), .hidden(folded: false), .hidden(folded: false)]
        #expect(RunAccounting.decide(input) == .provisionalFail("smoke gave a refusal in more than one of five cycles"))
    }

    @Test("one smoke refusal (not more than one) still fails, but as 'not hidden at the midpoint'")
    func oneSmokeRefusal() {
        var input = passingInput()
        input.smokeReadings = [.refused, .hidden(folded: false), .hidden(folded: false), .hidden(folded: false), .hidden(folded: false)]
        #expect(RunAccounting.decide(input) == .provisionalFail("the band found in the scan was not hidden at its midpoint in the smoke"))
    }

    @Test("a smoke cycle stillDrawn at the midpoint -> provisional FAIL")
    func smokeNotHiddenAtMidpoint() {
        var input = passingInput()
        input.smokeReadings = [.stillDrawn, .hidden(folded: false), .hidden(folded: false), .hidden(folded: false), .hidden(folded: false)]
        #expect(RunAccounting.decide(input) == .provisionalFail("the band found in the scan was not hidden at its midpoint in the smoke"))
    }

    @Test("every smoke reading hidden but one cycle's other checks fail -> provisional FAIL")
    func smokeChecksFail() {
        var input = passingInput()
        input.smokeChecksPassed = [true, true, false, true, true]
        #expect(RunAccounting.decide(input) == .provisionalFail("a smoke cycle failed fold/Protected/templated/residual/restored"))
    }

    @Test("a safety stop overrides everything else, even a run that would otherwise PASS")
    func safetyStopOverridesPass() {
        var input = passingInput()
        input.safetyStop = .stop
        #expect(RunAccounting.decide(input) == .safetyStop)
    }

    @Test("a safety stop needing the owner's attention is reported as such")
    func safetyStopNeedingAttention() {
        var input = passingInput()
        input.safetyStop = .needingAttention
        #expect(RunAccounting.decide(input) == .safetyStopNeedingAttention)
    }

    @Test("a safety stop is checked before preflight/capture INCONCLUSIVE reasons")
    func safetyStopBeforeInconclusive() {
        var input = passingInput()
        input.preflightEverPassed = false
        input.safetyStop = .stop
        #expect(RunAccounting.decide(input) == .safetyStop)
    }
}
