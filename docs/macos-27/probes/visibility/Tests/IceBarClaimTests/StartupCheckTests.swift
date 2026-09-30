// U23 (pre-registration section 7): the section 3 invariants checked at start,
// a violation aborts, a scale other than 2 aborts (claim plan R18).
@testable import IceBarClaim
import IceCore
import Testing

@Suite("U23 start-up invariants")
struct StartupCheckTests {
    func parameters(tAgree: Int = 8, tBg: Int = 32, tDiff: Int = 32, contrastMin: Int = 129, clusterMinPx: Int = 16) -> ClaimParameters {
        ClaimParameters(tAgree: tAgree, tBg: tBg, tDiff: tDiff, contrastMin: contrastMin, clusterMinPx: clusterMinPx,
                        keptSamples: 4, observationCaptures: 6)
    }

    @Test("the pre-registered numbers")
    func preRegistered() {
        let p = ClaimParameters.preRegistered
        #expect([p.tAgree, p.tBg, p.tDiff, p.contrastMin, p.clusterMinPx, p.keptSamples, p.observationCaptures] == [8, 32, 32, 129, 16, 4, 6])
        #expect(p.clusterMinPx == DetectorParameters.preRegistered.foldClusterMinPx)
    }

    @Test("pre-registered parameters at scale 2 are ready")
    func ready() {
        #expect(StartupCheck.evaluate(claim: .preRegistered, detector: .preRegistered, scale: 2) == .ready)
    }

    @Test("T_agree not below T_diff aborts")
    func agree() {
        let outcome = StartupCheck.evaluate(claim: parameters(tAgree: 32), detector: .preRegistered, scale: 2)
        #expect(outcome == .abort([.agreeNotBelowDiff]))
    }

    @Test("T_bg above T_diff aborts, and the contrast minimum no longer derives")
    func background() {
        let outcome = StartupCheck.evaluate(claim: parameters(tBg: 33), detector: .preRegistered, scale: 2)
        #expect(outcome == .abort([.backgroundAboveDiff, .contrastNotDerived]))
    }

    @Test("a contrast minimum other than T_diff + 3 T_bg + 1 aborts", arguments: [128, 130])
    func contrast(value: Int) {
        let outcome = StartupCheck.evaluate(claim: parameters(contrastMin: value), detector: .preRegistered, scale: 2)
        #expect(outcome == .abort([.contrastNotDerived]))
    }

    @Test("a cluster minimum other than the frozen foldClusterMinPx aborts")
    func cluster() {
        let outcome = StartupCheck.evaluate(claim: parameters(clusterMinPx: 15), detector: .preRegistered, scale: 2)
        #expect(outcome == .abort([.clusterNotFrozen]))
    }

    @Test("invalid detector parameters abort")
    func detector() {
        let outcome = StartupCheck.evaluate(claim: .preRegistered, detector: DetectorParameters(minSamples: 1), scale: 2)
        #expect(outcome == .abort([.detectorInvalid]))
    }

    @Test("a scale other than 2 aborts", arguments: [1.0, 1.5, 3.0])
    func scale(value: Double) {
        #expect(StartupCheck.evaluate(claim: .preRegistered, detector: .preRegistered, scale: value) == .abort([.unsupportedScale(value)]))
    }

    @Test("every violation is reported, not only the first")
    func all() {
        let outcome = StartupCheck.evaluate(claim: parameters(tAgree: 40, clusterMinPx: 8), detector: DetectorParameters(minSamples: 1), scale: 1)
        #expect(outcome == .abort([.agreeNotBelowDiff, .clusterNotFrozen, .detectorInvalid, .unsupportedScale(1)]))
    }
}
