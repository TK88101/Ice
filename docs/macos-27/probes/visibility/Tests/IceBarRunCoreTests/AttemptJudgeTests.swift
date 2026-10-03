// U19 (pre-registration section 7) and the runner plan's Q4-Q6: an attempt is
// the atomic unit; an observation is up to three of them.
@testable import IceBarClaim
import IceBarOracle
@testable import IceBarRunCore
import IceCore
import Testing

enum Attempts {
    static let granted = ClaimOutcome(reasons: [], regionClear: .clear(largestCluster: 0))
    static let notClear = ClaimOutcome(reasons: [.notClear], regionClear: .notClear(.changed(index: 0, clusterPx: 20)))
    static let unreadable = ClaimOutcome(reasons: [.fold(.unreadable)], regionClear: .clear(largestCluster: 0))
    static let present = ClaimOutcome(reasons: [.fold(.present), .notClear], regionClear: .notClear(.changed(index: 1, clusterPx: 30)))
    static func noBaseline(_ refusal: BaselineRefusal) -> ClaimOutcome { ClaimOutcome(reasons: [.noBaseline(refusal)], regionClear: nil) }

    static let clean = OracleAttempt(seesMember: false, seesChevron: false, chevronNotEvaluable: false, inconclusive: false)
    static let member = OracleAttempt(seesMember: true, seesChevron: false, chevronNotEvaluable: false, inconclusive: false)
    static let chevron = OracleAttempt(seesMember: false, seesChevron: true, chevronNotEvaluable: false, inconclusive: false)
    static let controlMiss = OracleAttempt(seesMember: false, seesChevron: false, chevronNotEvaluable: false, inconclusive: true)
    static let notEvaluable = OracleAttempt(seesMember: false, seesChevron: false, chevronNotEvaluable: true, inconclusive: false)

    static func record(_ claim: ClaimOutcome, _ oracle: OracleAttempt, cadence: CadenceRefusal? = nil, leftOfNotch: Bool = false) -> AttemptRecord {
        AttemptRecord(claim: claim, oracle: oracle, cadence: cadence, memberLeftOfNotch: leftOfNotch)
    }
}

@Suite("U19: attempts and observations")
struct AttemptJudgeTests {
    typealias A = Attempts

    @Test("Q5: the class of one attempt, NO-GO first")
    func classes() {
        #expect(AttemptJudge.classify(A.record(A.granted, A.clean)) == .granted)
        #expect(AttemptJudge.classify(A.record(A.notClear, A.clean)) == .notGranted)
        #expect(AttemptJudge.classify(A.record(A.granted, A.member)) == .noGo)
        #expect(AttemptJudge.classify(A.record(A.granted, A.chevron)) == .noGo)
        #expect(AttemptJudge.classify(A.record(A.notClear, A.member)) == .notGranted)
        // A granted attempt with a control miss is not "granted and clean".
        #expect(AttemptJudge.classify(A.record(A.granted, A.controlMiss)) == .inconclusive)
        #expect(AttemptJudge.classify(A.record(A.granted, A.notEvaluable)) == .inconclusive)
        #expect(AttemptJudge.classify(A.record(A.notClear, A.controlMiss)) == .inconclusive)
        // NO-GO outranks inconclusive.
        let both = OracleAttempt(seesMember: true, seesChevron: false, chevronNotEvaluable: false, inconclusive: true)
        #expect(AttemptJudge.classify(A.record(A.granted, both)) == .noGo)
        // A cadence violation never certifies.
        #expect(AttemptJudge.classify(A.record(A.granted, A.clean, cadence: .spacing(index: 1))) == .inconclusive)
        // S1: a member seen left of the notch is NO-GO whatever the claim.
        #expect(AttemptJudge.classify(A.record(A.notClear, A.clean, leftOfNotch: true)) == .noGo)
    }

    @Test("Q3: stop after the first attempt whose claim is granted, else after three")
    func stopRule() {
        #expect(AttemptJudge.needsAnotherAttempt(claims: []))
        #expect(AttemptJudge.needsAnotherAttempt(claims: [A.record(A.notClear, A.clean)].map(\.claim)))
        #expect(!AttemptJudge.needsAnotherAttempt(claims: [A.record(A.granted, A.controlMiss)].map(\.claim)))
        #expect(!AttemptJudge.needsAnotherAttempt(claims: [A.record(A.granted, A.member)].map(\.claim)))
        #expect(AttemptJudge.needsAnotherAttempt(claims: Array(repeating: A.record(A.notClear, A.clean), count: 2).map(\.claim)))
        #expect(!AttemptJudge.needsAnotherAttempt(claims: Array(repeating: A.record(A.notClear, A.clean), count: 3).map(\.claim)))
    }

    @Test("U19: granted and clean on attempt 2 -> granted, attempts = 2")
    func grantedSecond() {
        let o = AttemptJudge.observation([A.record(A.notClear, A.clean), A.record(A.granted, A.clean)], timedOut: false, baseline: .accepted)
        #expect(o.outcome == .granted)
        #expect(o.attempts == 2)
        #expect(o.cause == nil)
        #expect(o.oracleClean)
    }

    @Test("U19: three not granted -> not granted")
    func threeNot() {
        let o = AttemptJudge.observation(Array(repeating: A.record(A.notClear, A.clean), count: 3), timedOut: false, baseline: .accepted)
        #expect(o.outcome == .notGranted)
        #expect(o.cause == .notClear)
        #expect(o.oracleClean)
    }

    @Test("U19: > 10 s -> not granted by timeout, even with a granted attempt")
    func timeout() {
        let o = AttemptJudge.observation([A.record(A.notClear, A.clean), A.record(A.granted, A.clean)], timedOut: true, baseline: .accepted)
        #expect(o.outcome == .notGranted)
        #expect(o.cause == .timeout)
    }

    @Test("U19: attempt 1 granted while the oracle sees a member -> NO-GO even if attempt 2 is clean; a timeout keeps it")
    func noGo() {
        let attempts = [A.record(A.granted, A.member), A.record(A.granted, A.clean)]
        #expect(AttemptJudge.observation(attempts, timedOut: false, baseline: .accepted).outcome == .noGo)
        let late = AttemptJudge.observation(attempts, timedOut: true, baseline: .accepted)
        #expect(late.outcome == .noGo)
        #expect(late.cause == .noGo)
        #expect(!late.oracleClean)
    }

    @Test("U19: a control miss on attempt 1 and a granted clean attempt 2 -> granted")
    func missThenGranted() {
        let o = AttemptJudge.observation([A.record(A.notClear, A.controlMiss), A.record(A.granted, A.clean)], timedOut: false, baseline: .accepted)
        #expect(o.outcome == .granted)
    }

    @Test("U19: a control miss on attempt 1 and nothing granted -> inconclusive (a timeout too)")
    func missNothing() {
        let attempts = [A.record(A.notClear, A.controlMiss), A.record(A.notClear, A.clean), A.record(A.notClear, A.clean)]
        let o = AttemptJudge.observation(attempts, timedOut: false, baseline: .accepted)
        #expect(o.outcome == .inconclusive)
        #expect(o.cause == .inconclusive)
        #expect(AttemptJudge.observation(attempts, timedOut: true, baseline: .accepted).outcome == .inconclusive)
    }

    @Test("Q6: oracle-clean means no attempt saw a member or a chevron")
    func oracleClean() {
        #expect(!AttemptJudge.observation([A.record(A.notClear, A.member), A.record(A.notClear, A.clean), A.record(A.notClear, A.clean)],
                                          timedOut: false, baseline: .accepted).oracleClean)
        #expect(!AttemptJudge.observation(Array(repeating: A.record(A.notClear, A.chevron), count: 3), timedOut: false, baseline: .accepted).oracleClean)
    }

    @Test("Q6: causes from the baseline, in their registered names")
    func baselineCauses() {
        func cause(_ status: BaselineStatus, _ refusal: BaselineRefusal) -> ObservationCause? {
            AttemptJudge.observation(Array(repeating: A.record(A.noBaseline(refusal), A.clean), count: 3), timedOut: false, baseline: status).cause
        }
        #expect(cause(.refused(.contrast), .contrast) == .contrastGate)
        #expect(cause(.refused(.contrastUnmeasurable), .contrastUnmeasurable) == .contrastGate)
        #expect(cause(.refused(.texture), .texture) == .texture)
        #expect(cause(.refused(.disagree), .disagree) == .baselineRefused)
        #expect(cause(.refused(.foldNotAbsent(.unreadable)), .foldNotAbsent(.unreadable)) == .baselineRefused)
        #expect(cause(.cadence(.timeout), .regionUndefined) == .timeout)
        #expect(cause(.cadence(.spacing(index: 2)), .regionUndefined) == .baselineRefused)
    }

    @Test("Q6: causes from the last attempt's claim")
    func claimCauses() {
        func cause(_ claim: ClaimOutcome) -> ObservationCause? {
            AttemptJudge.observation(Array(repeating: A.record(claim, A.clean), count: 3), timedOut: false, baseline: .accepted).cause
        }
        #expect(cause(A.unreadable) == .foldUnreadable)
        #expect(cause(A.present) == .foldPresent)
        #expect(cause(A.notClear) == .notClear)
    }

    @Test("Q6: an observation with no attempt at all is inconclusive")
    func empty() {
        #expect(AttemptJudge.observation([], timedOut: false, baseline: .accepted).outcome == .inconclusive)
    }
}
