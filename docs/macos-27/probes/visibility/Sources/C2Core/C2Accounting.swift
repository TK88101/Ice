// T1 (docs/plans/2026-09-28-c2-protocol.md section 1 and the feasibility
// plan's 6.2): settling retries, each sitting's verdict, and the rule that
// the first non-passing configuration ends the sitting.

/// One attempt of one cycle, before 6.2's retry rule.
public enum C2CycleOutcome: Equatable, Sendable {
    case pass
    case fail
    case inconclusive
}

/// One cycle after the retry rule.
public enum C2Settled: Equatable, Sendable {
    case pass
    case fail
    /// Inconclusive three times: a failure for a mandatory criterion.
    case notShown
}

extension C2Settled {
    /// Sitting B: a collar or baseline point passes only when the whole
    /// hidden section hid without the fold, every other check passing.
    public init(reading: C2Reading) {
        switch reading {
        case .hiddenNoFold: self = .pass
        case .notShown: self = .notShown
        case .hiddenFolded, .stillDrawn: self = .fail
        }
    }
}

public enum C2Retry {
    public static let maxAttempts = 3

    /// One measured length: `nil` attempts are inconclusive cycles (no
    /// reading at all); the first real reading settles it, and three
    /// inconclusive attempts make it `notShown`. `nil` when another attempt
    /// is due.
    public static func settleReading(_ attempts: [C2Reading?]) -> C2Reading? {
        if let reading = attempts.lazy.compactMap({ $0 }).first { return reading }
        return attempts.count >= maxAttempts ? .notShown : nil
    }

    /// The settled outcome, or `nil` when another attempt is due.
    public static func settle(_ attempts: [C2CycleOutcome]) -> C2Settled? {
        for attempt in attempts {
            switch attempt {
            case .pass: return .pass
            case .fail: return .fail
            case .inconclusive: continue
            }
        }
        return attempts.count >= maxAttempts ? .notShown : nil
    }
}

/// Sitting A's outcome for one configuration (one `vizprobe c2-config` process
/// or several, when the range expands).
public enum C2BracketOutcome: Equatable, Sendable {
    case bracketed(C2Span)
    case noBand
    case notShown(String)
    case safetyStop
}

/// Sitting B's outcome for one configuration: its settled cycles in order
/// (9 collar points, then 5 baseline cycles), or a safety stop.
public enum C2ConfirmOutcome: Equatable, Sendable {
    case completed([C2Settled])
    case safetyStop
}

public struct C2ConfigurationResult<Outcome: Equatable & Sendable>: Equatable, Sendable {
    public let configuration: String
    public let outcome: Outcome

    public init(configuration: String, outcome: Outcome) {
        self.configuration = configuration
        self.outcome = outcome
    }
}

public enum C2Verdict: Equatable, Sendable {
    /// Sitting A only: every configuration bracketed; the chosen length.
    case length(Double, intersection: C2Span)
    /// Sitting B only.
    case pass
    /// `configuration` is `nil` when no single configuration is to blame.
    case provisionalFail(configuration: String?, reason: String)
    case safetyStop(configuration: String)
}

public enum C2Accounting {
    public static let baselineCycles = 5
    public static var cyclesPerConfigurationInSittingB: Int { C2Band.collar(0).count + baselineCycles }

    public static func sittingA(_ results: [C2ConfigurationResult<C2BracketOutcome>]) -> C2Verdict {
        guard !results.isEmpty else { return .provisionalFail(configuration: nil, reason: "no configuration ran") }
        var bands = [C2Span]()
        for result in results {
            switch result.outcome {
            case .bracketed(let band): bands.append(band)
            case .noBand: return .provisionalFail(configuration: result.configuration, reason: "no band")
            case .notShown(let why): return .provisionalFail(configuration: result.configuration, reason: "not shown: \(why)")
            case .safetyStop: return .safetyStop(configuration: result.configuration)
            }
        }
        guard let common = C2Band.intersection(bands) else {
            return .provisionalFail(configuration: nil, reason: "empty intersection")
        }
        guard let length = C2Band.length(common) else {
            return .provisionalFail(configuration: nil, reason: "intersection \(Int(common.lo))-\(Int(common.hi)) narrower than \(Int(C2Band.minimumIntersectionPt)) pt")
        }
        return .length(length, intersection: common)
    }

    public static func sittingB(_ results: [C2ConfigurationResult<C2ConfirmOutcome>]) -> C2Verdict {
        guard !results.isEmpty else { return .provisionalFail(configuration: nil, reason: "no configuration ran") }
        for result in results {
            guard case .completed(let cycles) = result.outcome else {
                return .safetyStop(configuration: result.configuration)
            }
            if cycles.contains(.fail) {
                return .provisionalFail(configuration: result.configuration, reason: "a collar or baseline cycle failed")
            }
            if cycles.contains(.notShown) {
                return .provisionalFail(configuration: result.configuration, reason: "a collar or baseline cycle not shown")
            }
            if cycles.count < cyclesPerConfigurationInSittingB {
                return .provisionalFail(configuration: result.configuration, reason: "ended after \(cycles.count) of \(cyclesPerConfigurationInSittingB) cycles")
            }
        }
        return .pass
    }

    public static func shouldContinue(afterA outcome: C2BracketOutcome) -> Bool {
        if case .bracketed = outcome { return true }
        return false
    }

    public static func shouldContinue(afterB outcome: C2ConfirmOutcome) -> Bool {
        guard case .completed(let cycles) = outcome else { return false }
        return cycles.count == cyclesPerConfigurationInSittingB && cycles.allSatisfy { $0 == .pass }
    }
}
