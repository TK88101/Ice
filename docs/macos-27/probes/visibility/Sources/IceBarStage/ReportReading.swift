// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q20): a step's
// verified `result.json` as each sequencer reads it. A missing or unverified
// report is a safety stop (fail closed, as C2's `readBack`).
import C2Core
import IceBarRunCore

public enum ReportReading {
    public static func s1(_ report: StepReport?, purpose: S1Purpose) -> S1StepResult {
        guard let report else { return .safetyStop("no verified step report") }
        switch report.status {
        case .safetyStop: return .safetyStop(report.reason ?? "safety stop")
        case .noGo: return .noGo(report.reason ?? "NO-GO")
        case .completed, .inconclusive: break
        }
        let completed = report.status == .completed
        switch purpose {
        case .bracket:
            let points = completed ? report.points.compactMap { p in C2Reading(name: p.reading).map { C2Point(length: p.length, reading: $0) } } : []
            return .bracket(points: points, completed: completed && points.count == report.points.count, noGo: false)
        case .confirm:
            return .confirm(cycles: completed ? report.cycles : [], completed: completed)
        }
    }

    public static func sweep(_ report: StepReport?) -> RepeatResult {
        guard let report else { return .inconclusive }
        if report.status == .noGo { return .noGo }
        return report.status == .completed ? report.sweep ?? .inconclusive : .inconclusive
    }

    public static func s0(_ report: StepReport?) -> S0Report {
        if let s0 = report?.s0 { return s0 }
        return S0Report(outcome: .notShown(report?.reason ?? "no verified step report"), c3: .notListed("no capture"), section8: .unmeasured([]))
    }
}
