// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q3-Q6): one attempt
// is the atomic unit (pre-registration section 2); an observation is up to
// three attempts, judged by section 4 (U19).
import IceBarClaim
import IceCore

/// The oracle's reading of one attempt: the OR over its samples'
/// `AttemptVerdict`s (Q4).
public struct OracleAttempt: Equatable, Sendable {
    public let seesMember: Bool
    public let seesChevron: Bool
    public let chevronNotEvaluable: Bool
    public let inconclusive: Bool

    public init(seesMember: Bool, seesChevron: Bool, chevronNotEvaluable: Bool, inconclusive: Bool) {
        self.seesMember = seesMember
        self.seesChevron = seesChevron
        self.chevronNotEvaluable = chevronNotEvaluable
        self.inconclusive = inconclusive
    }
}

public struct AttemptRecord: Equatable, Sendable {
    public let claim: ClaimOutcome
    public let oracle: OracleAttempt
    /// The attempt's own samples broke the cadence (Q3): it never certifies.
    public let cadence: CadenceRefusal?
    /// S1 only (Q5): a member seen left of the notch in any capture.
    public let memberLeftOfNotch: Bool

    public init(claim: ClaimOutcome, oracle: OracleAttempt, cadence: CadenceRefusal?, memberLeftOfNotch: Bool) {
        self.claim = claim
        self.oracle = oracle
        self.cadence = cadence
        self.memberLeftOfNotch = memberLeftOfNotch
    }
}

public enum AttemptClass: String, Equatable, Sendable {
    case noGo, inconclusive, granted, notGranted
}

public enum ObservationOutcome: String, Codable, Equatable, Sendable {
    case noGo, inconclusive, granted, notGranted
}

/// Section 4's split by cause (Q6).
public enum ObservationCause: String, Codable, Equatable, Sendable, CaseIterable {
    case noGo, inconclusive, timeout
    case baselineRefused = "baseline refused"
    case contrastGate = "contrast gate"
    case texture
    case foldUnreadable = "fold unreadable"
    case foldPresent = "fold present"
    case notClear = "not clear"
    /// Q8: a member missed at a rest control made the whole cycle inconclusive.
    case memberControl = "member control"
}

/// What the cycle's baseline came to.
public enum BaselineStatus: Equatable, Sendable {
    case accepted
    case refused(BaselineRefusal)
    /// Q2: the baseline's own samples broke the cadence or timed out.
    case cadence(CadenceRefusal)
}

public struct ObservationRecord: Codable, Equatable, Sendable {
    public let outcome: ObservationOutcome
    /// `nil` only for a granted observation.
    public let cause: ObservationCause?
    /// No attempt's oracle saw a member or `«` (section 4's numerator condition).
    public let oracleClean: Bool
    public let attempts: Int

    public init(outcome: ObservationOutcome, cause: ObservationCause?, oracleClean: Bool, attempts: Int) {
        self.outcome = outcome
        self.cause = cause
        self.oracleClean = oracleClean
        self.attempts = attempts
    }
}

public enum AttemptJudge {
    /// Q5: NO-GO, then inconclusive, then granted (clean), then not granted.
    public static func classify(_ attempt: AttemptRecord) -> AttemptClass {
        let granted = attempt.claim.granted
        if attempt.memberLeftOfNotch || (granted && (attempt.oracle.seesMember || attempt.oracle.seesChevron)) { return .noGo }
        if attempt.cadence != nil || attempt.oracle.inconclusive || attempt.oracle.chevronNotEvaluable { return .inconclusive }
        return granted ? .granted : .notGranted
    }

    /// Q3: stop after the first attempt whose claim is granted, else after three.
    public static func needsAnotherAttempt(_ attempts: [AttemptRecord], parameters: CadenceParameters = .preRegistered) -> Bool {
        needsAnotherAttempt(claims: attempts.map(\.claim), parameters: parameters)
    }

    /// The same rule over the claims alone: the runner decides before the oracle has run.
    public static func needsAnotherAttempt(claims: [ClaimOutcome], parameters: CadenceParameters = .preRegistered) -> Bool {
        claims.count < parameters.maxAttempts && !claims.contains { $0.granted }
    }

    /// Q6.
    public static func observation(_ attempts: [AttemptRecord], timedOut: Bool, baseline: BaselineStatus) -> ObservationRecord {
        let classes = attempts.map(classify)
        let clean = !attempts.contains { $0.oracle.seesMember || $0.oracle.seesChevron }
        func record(_ outcome: ObservationOutcome, _ cause: ObservationCause?) -> ObservationRecord {
            ObservationRecord(outcome: outcome, cause: cause, oracleClean: clean, attempts: attempts.count)
        }
        if classes.contains(.noGo) { return record(.noGo, .noGo) }
        let granted = classes.contains(.granted)
        if attempts.isEmpty || (classes.contains(.inconclusive) && !granted) { return record(.inconclusive, .inconclusive) }
        if timedOut { return record(.notGranted, .timeout) }
        if granted { return record(.granted, nil) }
        return record(.notGranted, cause(baseline: baseline, last: attempts.last?.claim))
    }

    static func cause(baseline: BaselineStatus, last: ClaimOutcome?) -> ObservationCause {
        switch baseline {
        case .cadence(.timeout): return .timeout
        case .cadence: return .baselineRefused
        case .refused(.contrast), .refused(.contrastUnmeasurable): return .contrastGate
        case .refused(.texture): return .texture
        case .refused: return .baselineRefused
        case .accepted: break
        }
        switch last?.reasons.first {
        case .fold(.present)?: return .foldPresent
        case .fold?: return .foldUnreadable
        case .notClear?: return .notClear
        case .noBaseline?, nil: return .baselineRefused
        }
    }
}
