// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q4-Q5, Q14-Q16):
// the oracle per attempt, the live `«` (b) control's episodes (deviation 2 C5),
// section 8's report from S0, and S0's own verdict.
import IceBarClaim
import IceBarOracle
import IceCore

public enum OracleSummary {
    /// Q4: an attempt's oracle reading, the OR over its samples' verdicts; no sample: inconclusive.
    public static func combine(_ verdicts: [AttemptVerdict]) -> OracleAttempt {
        OracleAttempt(
            seesMember: verdicts.contains(where: \.seesMember),
            seesChevron: verdicts.contains(where: \.seesChevron),
            chevronNotEvaluable: verdicts.contains(where: \.chevronNotEvaluable),
            inconclusive: verdicts.isEmpty || verdicts.contains(where: \.inconclusive)
        )
    }

    /// Q4: one sample's `OverlapGuard` outcome, the first non-clear of its captures'.
    public static func overlap(_ outcomes: [OverlapOutcome]) -> OverlapOutcome {
        guard !outcomes.isEmpty else { return .missing("no capture") }
        return outcomes.first { $0 != .clear } ?? .clear
    }

    /// Q5 (S1): a member `drawn(full)` left of the notch, or an unexplained
    /// sighting (anonymous, deviation 2 C1) whose box ends at or left of the notch.
    public static func memberLeftOfNotch(_ captures: [CaptureLabels], members: Set<String>, notch: PtSpan?, scale: Double) -> Bool {
        captures.contains { capture in
            let full = members.contains { id in
                if case .drawn(.full, _, .leftOfNotch)? = capture.labels[id] { return true }
                return false
            }
            guard let notch else { return full }
            return full || capture.sightings.contains { !$0.explained && Double($0.xPx + $0.width) / scale <= notch.lo }
        }
    }
}

/// Q14: one `BObservation` per capture of S0 and S-adv; an episode is a
/// maximal run of consecutive reads with `«` (a), numbered across the sitting.
public struct ChevronEpisodes: Equatable, Sendable {
    public private(set) var all: [BObservation] = []
    private var episode = 0
    private var previousRead = false

    public init() {}

    /// One sample: its read's (a), and its captures' (b).
    public mutating func observe(readShowsChevron: Bool, captures: [ChevronSighting]) -> [BObservation] {
        if readShowsChevron, !previousRead { episode += 1 }
        previousRead = readShowsChevron
        let made = captures.map { BObservation(episode: episode, axChevron: readShowsChevron, pixels: $0) }
        all += made
        return made
    }
}

public enum Section8Outcome: Equatable, Sendable {
    case consistent
    /// Every S0 baseline with the number fails its section 3 inequality.
    case contradiction([String])
    /// No S0 baseline produced the number: section 8 cannot be checked.
    case unmeasured([String])
}

public enum Section8Check {
    /// Q16, from every S0 baseline's measurements.
    public static func evaluate(_ measurements: [BaselineMeasurements], parameters p: ClaimParameters = .preRegistered) -> Section8Outcome {
        let quantities: [(name: String, fails: [Bool])] = [
            ("kept distance", measurements.compactMap(\.maxAgreementDistance).map { $0 > p.tAgree }),
            ("row spread", measurements.compactMap(\.largestRowCluster).map { $0 >= p.clusterMinPx }),
            ("texture", measurements.compactMap(\.texture).map { if case .refused = $0 { true } else { false } }),
            ("C_r", measurements.compactMap(\.contrast).map { $0.cR < p.contrastMin }),
        ]
        let unmeasured = quantities.filter(\.fails.isEmpty).map(\.name)
        if !unmeasured.isEmpty { return .unmeasured(unmeasured) }
        let contradicted = quantities.filter { $0.fails.allSatisfy { $0 } }.map(\.name)
        return contradicted.isEmpty ? .consistent : .contradiction(contradicted)
    }
}

public typealias S0CycleResult = RepeatResult

public enum S0Outcome: Equatable, Sendable {
    case pass
    case noGo
    case notShown(String)
    /// Fewer than 5 passing cycles so far.
    case incomplete
}

public enum S0Judge {
    public static let cycles = 5
    /// Q15: the claim granted in any attempt is NO-GO; a failed rest or restore control is inconclusive.
    public static func cycle(claimGranted: Bool, controlsPassed: Bool) -> S0CycleResult {
        if claimGranted { return .noGo }
        return controlsPassed ? .pass : .inconclusive
    }

    public static func stage(_ results: [S0CycleResult], finalControlPassed: Bool) -> S0Outcome {
        switch Repeats.judge(results, needed: cycles) {
        case .noGo: .noGo
        case .notShown: .notShown("a cycle inconclusive three times")
        case .incomplete: .incomplete
        case .pass: finalControlPassed ? .pass : .notShown("bar not restored after Menus quit")
        }
    }

    public static func nextCycleNeeded(_ results: [S0CycleResult]) -> Bool {
        stage(results, finalControlPassed: true) == .incomplete
    }
}
