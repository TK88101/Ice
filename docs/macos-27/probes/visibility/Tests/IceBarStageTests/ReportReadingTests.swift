// Q20: a step's `result.json`, as each sequencer reads it.
import C2Core
import IceBarRunCore
@testable import IceBarStage
import Testing

@Suite("Q20: reading a step's report")
struct ReportReadingTests {
    func report(_ status: StepStatus, reason: String? = nil) -> StepReport { StepReport(status: status, reason: reason) }

    @Test("S1 band batch: settled points; an aborted batch is short; NO-GO and safety stops pass through")
    func bracket() {
        var done = report(.completed)
        done.points = [ReportPoint(length: 520, reading: "hiddenNoFold"), ReportPoint(length: 536, reading: "stillDrawn")]
        #expect(ReportReading.s1(done, purpose: .bracket) == .bracket(points: [C2Point(length: 520, reading: .hiddenNoFold), C2Point(length: 536, reading: .stillDrawn)],
                                                                      completed: true, noGo: false))
        var aborted = report(.inconclusive, reason: "x")
        aborted.points = [ReportPoint(length: 520, reading: "nonsense")]
        #expect(ReportReading.s1(aborted, purpose: .bracket) == .bracket(points: [], completed: false, noGo: false))
        #expect(ReportReading.s1(report(.noGo, reason: "NO-GO at 520.0 pt"), purpose: .bracket) == .noGo("NO-GO at 520.0 pt"))
        #expect(ReportReading.s1(report(.safetyStop, reason: "foreign"), purpose: .confirm(replicate: false)) == .safetyStop("foreign"))
        #expect(ReportReading.s1(nil, purpose: .bracket) == .safetyStop("no verified step report"))
    }

    @Test("S1 midpoint: the cycles, complete only when the step completed")
    func confirm() {
        var done = report(.completed)
        done.cycles = [CycleRecord(observations: [], controlMiss: false)]
        #expect(ReportReading.s1(done, purpose: .confirm(replicate: true)) == .confirm(cycles: done.cycles, completed: true))
        #expect(ReportReading.s1(report(.inconclusive), purpose: .confirm(replicate: false)) == .confirm(cycles: [], completed: false))
    }

    @Test("an S-adv sweep: its sweep result; a step that never got that far is inconclusive")
    func sweep() {
        var done = report(.completed)
        done.sweep = .pass
        #expect(ReportReading.sweep(done) == .pass)
        #expect(ReportReading.sweep(report(.inconclusive)) == .inconclusive)
        #expect(ReportReading.sweep(report(.noGo)) == .noGo)
    }

    @Test("S0: its report, or not shown when the step ended without one")
    func s0() {
        var done = report(.completed)
        done.s0 = S0Report(outcome: .pass, c3: .holds, section8: .consistent)
        #expect(ReportReading.s0(done) == S0Report(outcome: .pass, c3: .holds, section8: .consistent))
        let none = ReportReading.s0(report(.inconclusive, reason: "placement gate: outOfOrder(\"ell\")"))
        #expect(none.outcome == .notShown("placement gate: outOfOrder(\"ell\")"))
    }
}
