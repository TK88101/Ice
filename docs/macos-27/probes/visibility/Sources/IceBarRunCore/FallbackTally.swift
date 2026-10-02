// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q7-Q9): the fallback
// rate of the pre-registration's section 4 at one length (U20).

/// One cycle's observations, and whether a rest control made it inconclusive (Q8).
public struct CycleRecord: Equatable, Sendable {
    public let observations: [ObservationRecord]
    public let controlMiss: Bool

    public init(observations: [ObservationRecord], controlMiss: Bool) {
        self.observations = observations
        self.controlMiss = controlMiss
    }
}

public enum LengthVerdict: Equatable, Sendable {
    case pass
    case fail
    /// More than 2 inconclusive of 20: the repeat is inconclusive.
    case inconclusive
    case noGo
    /// Not exactly 20 observations: never certifies.
    case incomplete(Int)
}

public struct FallbackParameters: Equatable, Sendable {
    public let observations: Int
    /// The rate fails at this many (6 of 20, 30 %).
    public let ceiling: Int
    /// More than this many inconclusive makes the repeat inconclusive.
    public let maxInconclusive: Int

    public static let preRegistered = FallbackParameters(observations: 20, ceiling: 6, maxInconclusive: 2)
}

public struct LengthTally: Equatable, Sendable {
    public let denominator: Int
    public let numerator: Int
    public let inconclusive: Int
    public let noGo: Int
    /// The numerator split by cause; the counts add up to it.
    public let byCause: [ObservationCause: Int]
    public let verdict: LengthVerdict
}

public enum FallbackTally {
    /// Q8: a control miss makes every observation of the cycle inconclusive; a NO-GO stays.
    public static func effective(_ cycle: CycleRecord) -> [ObservationRecord] {
        guard cycle.controlMiss else { return cycle.observations }
        return cycle.observations.map { o in
            o.outcome == .noGo ? o : ObservationRecord(outcome: .inconclusive, cause: .memberControl, oracleClean: o.oracleClean, attempts: o.attempts)
        }
    }

    /// Q9.
    public static func tally(_ cycles: [CycleRecord], parameters p: FallbackParameters = .preRegistered) -> LengthTally {
        let all = cycles.flatMap(effective)
        let counted = all.filter { $0.outcome == .inconclusive || ($0.outcome == .notGranted && $0.oracleClean) }
        var byCause = [ObservationCause: Int]()
        for o in counted { byCause[o.cause ?? .inconclusive, default: 0] += 1 }
        let inconclusive = all.filter { $0.outcome == .inconclusive }.count
        let noGo = all.filter { $0.outcome == .noGo }.count
        let verdict: LengthVerdict
        if noGo > 0 {
            verdict = .noGo
        } else if all.count != p.observations {
            verdict = .incomplete(all.count)
        } else if inconclusive > p.maxInconclusive {
            verdict = .inconclusive
        } else {
            verdict = counted.count < p.ceiling ? .pass : .fail
        }
        return LengthTally(denominator: all.count, numerator: counted.count, inconclusive: inconclusive, noGo: noGo, byCause: byCause, verdict: verdict)
    }
}
