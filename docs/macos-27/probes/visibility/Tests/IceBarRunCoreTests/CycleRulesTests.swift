// Q2, Q8, Q17, Q19: the per-cycle and per-step decisions the stage only gathers inputs for.
@testable import IceBarClaim
import C2Core
@testable import IceBarRunCore
import IceCore
import Testing

@Suite("Q2: one baseline's resolution")
struct BaselineJudgeTests {
    let selection = BaselineSelection(all: [], kept: [])
    func verdict(_ outcome: BaselineOutcome) -> BaselineVerdict {
        BaselineVerdict(outcome: outcome, measurements: BaselineMeasurements(maxAgreementDistance: 3), failedClauses: [])
    }

    @Test("a cadence refusal is no baseline: the claim gets a refusal, the cause the cadence")
    func cadence() {
        var evaluated = false
        let r = BaselineJudge.resolve(.failure(.timeout)) { _ in evaluated = true; return verdict(.refused(.disagree)) }
        #expect(!evaluated)
        #expect(r.status == .cadence(.timeout))
        #expect(r.claimInput == .refused(.keptCount(0)))
        #expect(r.measurements == nil)
    }

    @Test("otherwise HiddenBaseline.evaluate decides, measurements kept")
    func evaluated() {
        let r = BaselineJudge.resolve(.success(selection)) { _ in verdict(.refused(.texture)) }
        #expect(r.status == .refused(.texture))
        #expect(r.claimInput == .refused(.texture))
        #expect(r.measurements?.maxAgreementDistance == 3)
    }
}

@Suite("Q8, Q17, Q19: cycle and step rules")
struct CycleRulesTests {
    let dark = BarState(appearance: .dark, indicator: false)
    let lit = BarState(appearance: .dark, indicator: true)

    @Test("controls held: both passed and in every hold's state")
    func held() {
        #expect(CycleRules.controlsHeld(rest: (true, dark), restore: (true, dark), holds: [dark, dark]))
        #expect(!CycleRules.controlsHeld(rest: (false, dark), restore: (true, dark), holds: [dark]))
        #expect(!CycleRules.controlsHeld(rest: (true, dark), restore: nil, holds: [dark]))
        #expect(!CycleRules.controlsHeld(rest: (true, dark), restore: (true, dark), holds: [lit]))
        #expect(!CycleRules.controlsHeld(rest: (true, lit), restore: (true, dark), holds: [dark]))
    }

    @Test("a band-scan cycle's reading: inconclusive controls retry; in band iff some observation granted")
    func band() {
        #expect(CycleRules.bandReading(controlsPassed: false, outcomes: [.granted]) == nil)
        #expect(CycleRules.bandReading(controlsPassed: true, outcomes: [.notGranted, .granted]) == .hiddenNoFold)
        #expect(CycleRules.bandReading(controlsPassed: true, outcomes: [.notGranted, .inconclusive]) == .stillDrawn)
    }

    @Test("an S-adv step: NO-GO, then inconclusive (wrong variant or any inconclusive capture), then members seen or gone")
    func sAdvStep() {
        #expect(CycleRules.sAdvStep(noGo: true, appearanceMatches: false, anyInconclusive: true, seesMember: true) == .noGo)
        #expect(CycleRules.sAdvStep(noGo: false, appearanceMatches: false, anyInconclusive: false, seesMember: false) == .inconclusive)
        #expect(CycleRules.sAdvStep(noGo: false, appearanceMatches: true, anyInconclusive: true, seesMember: false) == .inconclusive)
        #expect(CycleRules.sAdvStep(noGo: false, appearanceMatches: true, anyInconclusive: false, seesMember: true) == .membersSeen)
        #expect(CycleRules.sAdvStep(noGo: false, appearanceMatches: true, anyInconclusive: false, seesMember: false) == .membersGone)
    }

    @Test("a sweep's repeat result")
    func sweep() {
        #expect(CycleRules.sweepResult(.noGo, controlsHeld: false) == .noGo)
        #expect(CycleRules.sweepResult(.done, controlsHeld: true) == .pass)
        #expect(CycleRules.sweepResult(.done, controlsHeld: false) == .inconclusive)
        #expect(CycleRules.sweepResult(.inconclusive("cap"), controlsHeld: true) == .inconclusive)
    }
}
