// Route C part 2 (docs/plans/2026-10-02-icebar-c-claim.md): the thresholds of
// the pre-registration's section 3 and the start-up check that must pass
// before any capture (U23; claim plan R18).
import IceCore

/// Section 3's numbers and section 2's counts. Fixed by the pre-registration;
/// never tuned. Distances are max-channel, alpha ignored.
public struct ClaimParameters: Equatable, Sendable {
    /// Rule 1 (a): every region pixel of every kept capture within this of the stored image.
    public let tAgree: Int
    /// Rule 1 (b): no cluster deviating from its row median by more than this.
    public let tBg: Int
    /// Rule 3: no cluster differing from the stored image by more than this.
    public let tDiff: Int
    /// Rule 1's contrast gate: C_r at least this (`T_diff` + 3 `T_bg` + 1).
    public let contrastMin: Int
    /// The smallest cluster rules 1 (b) and 3 see: the frozen `foldClusterMinPx`.
    public let clusterMinPx: Int
    /// Section 2: kept baseline samples (samples 2-5).
    public let keptSamples: Int
    /// Section 2: captures of one attempt (3 samples x 2).
    public let observationCaptures: Int

    public init(tAgree: Int, tBg: Int, tDiff: Int, contrastMin: Int, clusterMinPx: Int, keptSamples: Int, observationCaptures: Int) {
        self.tAgree = tAgree
        self.tBg = tBg
        self.tDiff = tDiff
        self.contrastMin = contrastMin
        self.clusterMinPx = clusterMinPx
        self.keptSamples = keptSamples
        self.observationCaptures = observationCaptures
    }

    public static let preRegistered = ClaimParameters(
        tAgree: 8, tBg: 32, tDiff: 32, contrastMin: 129,
        clusterMinPx: DetectorParameters.preRegistered.foldClusterMinPx,
        keptSamples: 4, observationCaptures: 6
    )
}

public enum AbortReason: Equatable, Sendable {
    case agreeNotBelowDiff
    case backgroundAboveDiff
    case contrastNotDerived
    case clusterNotFrozen
    case detectorInvalid
    /// Live certification only at scale 2 (section 2, "scale").
    case unsupportedScale(Double)
}

public enum StartupOutcome: Equatable, Sendable {
    case ready
    /// Every violated invariant, in section 3's order.
    case abort([AbortReason])
}

public enum StartupCheck {
    public static let requiredScale = 2.0

    public static func evaluate(claim: ClaimParameters, detector: DetectorParameters, scale: Double) -> StartupOutcome {
        var reasons = [AbortReason]()
        if claim.tAgree >= claim.tDiff { reasons.append(.agreeNotBelowDiff) }
        if claim.tBg > claim.tDiff { reasons.append(.backgroundAboveDiff) }
        if claim.contrastMin != claim.tDiff + 3 * claim.tBg + 1 { reasons.append(.contrastNotDerived) }
        if claim.clusterMinPx != detector.foldClusterMinPx { reasons.append(.clusterNotFrozen) }
        if !detector.isValid { reasons.append(.detectorInvalid) }
        if scale != requiredScale { reasons.append(.unsupportedScale(scale)) }
        return reasons.isEmpty ? .ready : .abort(reasons)
    }
}
