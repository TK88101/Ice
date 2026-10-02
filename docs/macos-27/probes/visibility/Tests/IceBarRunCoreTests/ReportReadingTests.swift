// Q20: a step's `result.json`, as each sequencer reads it.
import C2Core
import IceBarRunCore
import Testing

@Suite("Q20: reading a step's report")
struct ReportReadingTests {
    func report(_ status: StepStatus, reason: String? = nil) -> StepReport { StepReport(status: status, reason: reason) }

    @Test("S1 band batch: settled points; an aborted batch is short; NO-GO and safety stops pass through")
    func bracket() {
        var done = report(.completed)
        done.points = [ReportPoint(length: 520, reading: "hiddenNoFold"), ReportPoint(length: 536, reading: "stillDrawn")]
        #expect(ReportReading.s1(done, purpose: .bracket) == .bracket(points: [C2Point(length: 520, reading: .hiddenNoFold), C2Point(length: 536, reading: .stillDrawn)],
                                                                      completed: true))
        var aborted = report(.inconclusive, reason: "x")
        aborted.points = [ReportPoint(length: 520, reading: "nonsense")]
        #expect(ReportReading.s1(aborted, purpose: .bracket) == .bracket(points: [], completed: false))
        #expect(ReportReading.s1(report(.noGo, reason: "NO-GO at 520.0 pt"), purpose: .bracket) == .noGo("NO-GO at 520.0 pt"))
        #expect(ReportReading.s1(report(.safetyStop, reason: "foreign"), purpose: .confirm(replicate: false)) == .safetyStop("foreign"))
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
}
