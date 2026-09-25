import Testing
@testable import C1Core

/// Section 1's verdicts: PASS, (provisional) FAIL, safety stop (with its
/// "needing the owner's attention" escalation from section 4), and
/// INCONCLUSIVE.
@Suite("RunAccounting")
struct RunAccountingTests {
    /// A clean run that should PASS: the scan completed all 19 lengths,
    /// found a band, and all five smoke cycles pass every check.
    func passingInput() -> RunAccounting.Input {
        var scan = Array(repeating: TargetReading.stillDrawn, count: ScanPlanner.lengths.count)
        scan[9] = .hidden(folded: false)
        return RunAccounting.Input(
            preflightEverPassed: true,
            capturesStayedUnreadable: false,
            scanReadings: scan,
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
        input.scanReadings = Array(repeating: .hidden(folded: true), count: ScanPlanner.lengths.count)
        #expect(RunAccounting.decide(input) == .provisionalFail("no scanned length gave hidden(folded: false)"))
    }

    @Test("item 6: the scan did not complete all 19 lengths -> INCONCLUSIVE, never PASS from a partial scan")
    func incompleteScanIsInconclusive() {
        var input = passingInput()
        input.scanReadings = Array(repeating: TargetReading.hidden(folded: false), count: ScanPlanner.lengths.count - 1)
        #expect(RunAccounting.decide(input) == .inconclusive("the scan did not complete all \(ScanPlanner.lengths.count) lengths"))
    }

    @Test("item 6: an empty scan (preflight failed before any length) -> INCONCLUSIVE")
    func emptyScanIsInconclusive() {
        var input = passingInput()
        input.scanReadings = []
        #expect(RunAccounting.decide(input) == .inconclusive("the scan did not complete all \(ScanPlanner.lengths.count) lengths"))
    }

    @Test("item 6: an incomplete scan is checked before 'no band found' -- both would otherwise apply")
    func incompleteScanCheckedBeforeNoBandFound() {
        var input = passingInput()
        input.scanReadings = [.stillDrawn, .stillDrawn]
        #expect(RunAccounting.decide(input) == .inconclusive("the scan did not complete all \(ScanPlanner.lengths.count) lengths"))
    }

    @Test("item 6: a safety stop still overrides an incomplete scan")
    func safetyStopOverridesIncompleteScan() {
        var input = passingInput()
        input.scanReadings = [.hidden(folded: false)]
        input.safetyStop = .stop
        #expect(RunAccounting.decide(input) == .safetyStop)
    }

    @Test("round 3 item 1: zero completed smoke cycles (the first smoke preflight failed) -> INCONCLUSIVE, never PASS")
    func zeroSmokeCyclesIsInconclusive() {
        var input = passingInput()
        input.smokeReadings = []
        input.smokeChecksPassed = []
        #expect(RunAccounting.decide(input) == .inconclusive("the smoke did not complete all \(RunAccounting.smokeCycleCount) cycles"))
    }

    @Test("round 3 item 1: one completed smoke cycle (preflight failed on the second) -> INCONCLUSIVE, never PASS")
    func oneSmokeCycleIsInconclusive() {
        var input = passingInput()
        input.smokeReadings = [.hidden(folded: false)]
        input.smokeChecksPassed = [true]
        #expect(RunAccounting.decide(input) == .inconclusive("the smoke did not complete all \(RunAccounting.smokeCycleCount) cycles"))
    }

    @Test("round 3 item 1: mismatched smokeReadings/smokeChecksPassed counts (either short) -> INCONCLUSIVE")
    func mismatchedSmokeCountsIsInconclusive() {
        var input = passingInput()
        input.smokeChecksPassed = [true, true, true, true]
        #expect(RunAccounting.decide(input) == .inconclusive("the smoke did not complete all \(RunAccounting.smokeCycleCount) cycles"))
    }

    @Test("round 3 item 1: an incomplete smoke is checked before its own refusal/midpoint/checks content")
    func incompleteSmokeCheckedBeforeContentChecks() {
        var input = passingInput()
        input.smokeReadings = [.refused, .refused]
        input.smokeChecksPassed = [true, true]
        #expect(RunAccounting.decide(input) == .inconclusive("the smoke did not complete all \(RunAccounting.smokeCycleCount) cycles"))
    }

    @Test("round 3 item 1: a safety stop still overrides an incomplete smoke")
    func safetyStopOverridesIncompleteSmoke() {
        var input = passingInput()
        input.smokeReadings = []
        input.smokeChecksPassed = []
        input.safetyStop = .stop
        #expect(RunAccounting.decide(input) == .safetyStop)
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
