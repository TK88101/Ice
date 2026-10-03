// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q20): what one step
// process is asked to do, what it hands back (`result.json`), and how each
// sequencer reads a verified report. Pure; the step itself is `IceBarStage`.
import C2Core
import IceBarOracle

public enum StepKind: Equatable, Sendable {
    case s0
    /// One S-adv sweep, up and down.
    case sAdvSweep(SAdvVariant)
    /// S-adv's rest state with `«` up: the live (b) control's episodes.
    case sAdvChevron(SAdvVariant)
    /// One cycle per length, each retried up to three times when inconclusive.
    case s1Bracket([Double])
    /// Five cycles at the band's midpoint.
    case s1Confirm(Double)

    /// Coloured members only in a coloured S-adv sweep (Q10).
    public var colouredMembers: Bool {
        if case .sAdvSweep(let variant) = self { return variant.colouredMembers }
        return false
    }

    /// S1's left-of-notch NO-GO applies to S1 steps only (Q5).
    public var s1Rules: Bool {
        switch self {
        case .s1Bracket, .s1Confirm: true
        default: false
        }
    }
}

public enum StepStatus: String, Codable, Equatable, Sendable {
    case completed, inconclusive, noGo, safetyStop
}

public struct ReportPoint: Codable, Equatable, Sendable {
    public let length: Double
    /// `C2Reading`'s name (`C2Reading(name:)` reads it back).
    public let reading: String

    public init(length: Double, reading: String) {
        self.length = length
        self.reading = reading
    }
}

public struct ReportB: Codable, Equatable, Sendable {
    public let episode: Int
    public let axChevron: Bool
    public let pixels: ChevronSighting

    public init(_ observation: BObservation) {
        episode = observation.episode
        axChevron = observation.axChevron
        pixels = observation.pixels
    }

    public var observation: BObservation { BObservation(episode: episode, axChevron: axChevron, pixels: pixels) }
}

public struct S0Report: Codable, Equatable, Sendable {
    public let outcome: S0Outcome
    public let c3: C3Outcome
    public let section8: Section8Outcome

    public init(outcome: S0Outcome, c3: C3Outcome, section8: Section8Outcome) {
        self.outcome = outcome
        self.c3 = c3
        self.section8 = section8
    }
}

/// What one step process hands its sequencer (`result.json`).
public struct StepReport: Codable, Equatable, Sendable {
    public var status: StepStatus
    public var reason: String?
    public var roster: [RosterEntry] = []
    public var points: [ReportPoint] = []
    public var cycles: [CycleRecord] = []
    public var s0: S0Report?
    public var sweep: RepeatResult?
    public var chevronObservations: [ReportB] = []

    public init(status: StepStatus, reason: String? = nil) {
        self.status = status
        self.reason = reason
    }
}

/// A verified report as each sequencer reads it. A missing or unverified
/// report never gets here: the runner ends the sitting as a safety stop.
public enum ReportReading {
    public static func s1(_ report: StepReport, purpose: S1Purpose) -> S1StepResult {
        switch report.status {
        case .safetyStop: return .safetyStop(report.reason ?? "safety stop")
        case .noGo: return .noGo(report.reason ?? "NO-GO")
        case .completed, .inconclusive: break
        }
        let completed = report.status == .completed
        switch purpose {
        case .bracket:
            let points = completed ? report.points.compactMap { p in C2Reading(name: p.reading).map { C2Point(length: p.length, reading: $0) } } : []
            return .bracket(points: points, completed: completed && points.count == report.points.count)
        case .confirm:
            return .confirm(cycles: completed ? report.cycles : [], completed: completed)
        }
    }

    public static func sweep(_ report: StepReport) -> RepeatResult {
        if report.status == .noGo { return .noGo }
        return report.status == .completed ? report.sweep ?? .inconclusive : .inconclusive
    }
}
