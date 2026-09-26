/// Section 1: the target's read at one scanned length or one smoke cycle.
/// `.refused` lumps together every unverifiable/refusal outcome the plan's
/// wording covers ("stillDrawn, folded, or refused"; "unverifiable
/// (contradictsAccessibility) or any other refusal") -- `RunAccounting`
/// only ever needs to tell a refusal apart from a real reading, never which
/// refusal it was.
public enum TargetReading: Equatable, Sendable {
    case hidden(folded: Bool)
    case stillDrawn
    case refused
}

/// Section 1's four top-level verdicts, plus section 4's "needing the
/// owner's attention" escalation of a safety stop.
public enum Verdict: Equatable, Sendable {
    case pass
    case provisionalFail(String)
    case safetyStop
    case safetyStopNeedingAttention
    case inconclusive(String)
}

/// Section 1: turns what the run observed into one of the four verdicts.
public enum RunAccounting {
    /// Section 1 step 3: "5 cycles ... at that length."
    public static let smokeCycleCount = 5

    public enum SafetyStop: Equatable, Sendable {
        case stop
        case needingAttention
    }

    public struct Input: Equatable, Sendable {
        /// Section 3: the preflight passed at least once, so the run
        /// actually reached the scan.
        public var preflightEverPassed: Bool
        /// Section 1 INCONCLUSIVE: "captures stay unreadable."
        public var capturesStayedUnreadable: Bool
        /// Every scanned length's target reading, in scan order.
        public var scanReadings: [TargetReading]
        /// The midpoint length's target reading in each of the five smoke
        /// cycles, in cycle order.
        public var smokeReadings: [TargetReading]
        /// Per smoke cycle: fold absent, Protected drawn, every templated
        /// owner item drawn, no unexplained residual-strip change, Target
        /// `restored` after collapse -- section 1's PASS list, apart from
        /// the reading itself (carried in `smokeReadings`).
        public var smokeChecksPassed: [Bool]
        /// A safety stop (section 4), if the run had one. Overrides every
        /// other verdict -- section 1 lists it as its own unconditional
        /// FAIL case.
        public var safetyStop: SafetyStop?
        /// Amendment v8a: the placement gate's own failure reason (e.g.
        /// "helpers not leftmost: N owner items left"), when that is why
        /// the run stopped -- overrides the generic "preflight never
        /// passed" reason below with the specific one, verbatim, but is
        /// itself still overridden by a safety stop.
        public var placementGateFailureReason: String?

        public init(
            preflightEverPassed: Bool,
            capturesStayedUnreadable: Bool,
            scanReadings: [TargetReading],
            smokeReadings: [TargetReading],
            smokeChecksPassed: [Bool],
            safetyStop: SafetyStop?,
            placementGateFailureReason: String? = nil
        ) {
            self.preflightEverPassed = preflightEverPassed
            self.capturesStayedUnreadable = capturesStayedUnreadable
            self.scanReadings = scanReadings
            self.smokeReadings = smokeReadings
            self.smokeChecksPassed = smokeChecksPassed
            self.safetyStop = safetyStop
            self.placementGateFailureReason = placementGateFailureReason
        }
    }

    public static func decide(_ input: Input) -> Verdict {
        if let safetyStop = input.safetyStop {
            return safetyStop == .needingAttention ? .safetyStopNeedingAttention : .safetyStop
        }

        if let placementGateFailureReason = input.placementGateFailureReason {
            return .inconclusive(placementGateFailureReason)
        }

        guard input.preflightEverPassed, !input.capturesStayedUnreadable else {
            return .inconclusive("preflight never passed or captures stayed unreadable")
        }

        // Item 6 (Codex round 2): a preflight failure partway through the
        // scan must not let a later smoke -- run at whatever midpoint a
        // truncated scan happened to produce -- reach PASS. Only a scan
        // that read every one of section 5 step 2's 19 lengths may be
        // judged at all.
        guard input.scanReadings.count == ScanPlanner.lengths.count else {
            return .inconclusive("the scan did not complete all \(ScanPlanner.lengths.count) lengths")
        }

        guard input.scanReadings.contains(.hidden(folded: false)) else {
            return .provisionalFail("no scanned length gave hidden(folded: false)")
        }

        // Round 3 item 1: a smoke preflight that keeps failing after its 3
        // attempts (section 3) must not let the run reach PASS from a
        // shortened or empty smoke -- exactly `smokeCycleCount` completed
        // cycles or the run is INCONCLUSIVE, the same way an incomplete
        // scan already is.
        guard input.smokeReadings.count == Self.smokeCycleCount, input.smokeChecksPassed.count == Self.smokeCycleCount else {
            return .inconclusive("the smoke did not complete all \(Self.smokeCycleCount) cycles")
        }

        let refusals = input.smokeReadings.filter { $0 == .refused }.count
        guard refusals <= 1 else {
            return .provisionalFail("smoke gave a refusal in more than one of five cycles")
        }

        guard input.smokeReadings.allSatisfy({ $0 == .hidden(folded: false) }) else {
            return .provisionalFail("the band found in the scan was not hidden at its midpoint in the smoke")
        }

        guard input.smokeChecksPassed.allSatisfy({ $0 }) else {
            return .provisionalFail("a smoke cycle failed fold/Protected/templated/residual/restored")
        }

        return .pass
    }
}
