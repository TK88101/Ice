// T7 (docs/plans/2026-10-03-icebar-c-runner.md): the live call sites of
// `OverlapGuard` (deviation 2 C3: window-server bounds at every capture, every
// helper) and `BControl` (C5: one observation per S0 and S-adv capture), the
// member rest controls (Q8), the S1 left-of-notch rule (Q5), and the claim
// API used as part 2 hands it over. Faults are injected into each phase in turn.
import C2Core
import Foundation
import IceBarOracle
import IceBarRunCore
@testable import IceBarStage
import IceCore
import Testing

enum Run {
    /// One step on a fresh fake bar; `setup` adjusts the world first.
    static func step(_ kind: StepKind, members: Int = 2, coloured: Bool = false, faults: [Int: Fault] = [:],
                     setup: (FakeWorld) -> Void = { _ in }) -> (report: StepReport, step: IceBarStep, world: FakeWorld, evidence: FakeEvidence) {
        let world = FakeWorld(templates: StageFixtures.templates)
        setup(world)
        world.faults = faults
        let evidence = FakeEvidence()
        let step = IceBarStep(environment: Fake.environment(world, evidence: evidence), plan: Fake.plan(kind, members: members, coloured: coloured),
                              templates: StageFixtures.templates)
        return (step.run(), step, world, evidence)
    }

    /// The first capture index of `phase` in a clean run of the same step.
    static func firstCapture(_ phase: String, in step: IceBarStep) -> Int? {
        step.recorder.entries.firstIndex { $0.phase == phase }
    }

    /// Members never pushed off: every hidden-state baseline is refused (they are drawn in the region).
    static let membersStay: (FakeWorld) -> Void = { $0.spacerPushes = false }
}

@Suite("T7 (a): OverlapGuard at every capture")
struct OverlapGuardCallSiteTests {
    @Test("exactly one bounds read per capture, every glyph helper listed; every judged capture judged once")
    func everyCapture() {
        let run = Run.step(.s1Confirm(144))
        #expect(run.report.status == .completed)
        let entries = run.step.recorder.entries
        #expect(entries.count == run.world.captures)
        #expect(entries.allSatisfy { Set($0.bounds.keys) == Set(Roster.visibleGlyphs + ["hidden2", "hidden3"]) })
        #expect(run.step.judgedCaptures == entries.filter { $0.phase != "warm-up" }.count)
        #expect(run.report.cycles.count == 5)
        #expect(run.report.cycles.allSatisfy { !$0.controlMiss && $0.observations.allSatisfy { $0.outcome == .granted } })
    }

    @Test("a missing window or a 0.6 pt overlap in an attempt makes that attempt inconclusive; 0.5 pt does not",
          arguments: [Fault.windowMissing("hidden2"), .windowMissing("reference"), .windowOverlap("hidden2", "hidden3", 0.6)])
    func attempt(fault: Fault) throws {
        let clean = Run.step(.s1Confirm(144))
        let index = try #require(Run.firstCapture("attempt", in: clean.step))
        let run = Run.step(.s1Confirm(144), faults: [index: fault])
        let first = try #require(run.report.cycles.first?.observations.first)
        #expect(first.outcome == .inconclusive)
        let tolerated = Run.step(.s1Confirm(144), faults: [index: .windowOverlap("hidden2", "hidden3", 0.5)])
        #expect(tolerated.report.cycles.first?.observations.first?.outcome == .granted)
    }

    @Test("a missing window at a rest or restore control makes the cycle inconclusive", arguments: ["rest control", "restore control"])
    func control(phase: String) throws {
        let clean = Run.step(.s1Confirm(144))
        let index = try #require(Run.firstCapture(phase, in: clean.step))
        let run = Run.step(.s1Confirm(144), faults: [index: .windowMissing("hidden3")])
        #expect(run.report.cycles.first?.controlMiss == true)
        #expect(run.report.cycles.dropFirst().allSatisfy { !$0.controlMiss })
    }

    @Test("a missing window in an S-adv step's baseline makes that step inconclusive (not the endpoint)")
    func sAdvBaseline() throws {
        let variant = SAdvVariant(appearance: .dark, colouredMembers: false)
        let clean = Run.step(.sAdvSweep(variant))
        #expect(clean.report.sweep == .pass, "\(clean.report.reason ?? "")")
        let steps = clean.evidence.log.filter { $0.hasPrefix("sAdv.step") }
        let index = try #require(Run.firstCapture("baseline", in: clean.step))
        let run = Run.step(.sAdvSweep(variant), faults: [index: .windowMissing("hidden2")])
        let faulted = run.evidence.log.filter { $0.hasPrefix("sAdv.step") }
        #expect(faulted.first?.contains("inconclusive") == true)
        #expect(faulted.count == steps.count)
    }

    @Test("C3 in S0: every helper listed and the visible helpers' bounds on their AX frames")
    func s0C3() throws {
        let clean = Run.step(.s0, setup: Run.membersStay)
        #expect(clean.report.s0?.c3 == .holds)
        let index = try #require(Run.firstCapture("baseline", in: clean.step))
        let run = Run.step(.s0, faults: [index: .windowMissing("alt")], setup: Run.membersStay)
        #expect(run.report.s0?.c3 == .notListed("alt"))
    }
}

@Suite("T7 (b): BControl over S0 and S-adv")
struct BControlCallSiteTests {
    @Test("S0: one BControl observation per judged capture, warm-up excluded")
    func s0Count() {
        let run = Run.step(.s0, setup: Run.membersStay)
        #expect(run.report.s0?.outcome == .pass, "\(run.report.reason ?? "")")
        #expect(run.report.chevronObservations.count == run.step.judgedCaptures)
        #expect(run.report.chevronObservations.count == run.step.recorder.entries.filter { $0.phase != "warm-up" }.count)
    }

    @Test("`«` read by AX but not drawn, in any S0 phase: BControl reports the mismatch and the sitting stops before S1",
          arguments: ["rest control", "baseline", "attempt", "restore control", "final control"])
    func s0Mismatch(phase: String) throws {
        let clean = Run.step(.s0, setup: Run.membersStay)
        let index = try #require(Run.firstCapture(phase, in: clean.step))
        let run = Run.step(.s0, faults: [index: .chevronOnlyInAX], setup: Run.membersStay)
        let outcome = BControl.evaluate(run.report.chevronObservations.map(\.observation))
        guard case .mismatch = outcome else { Issue.record("\(outcome)"); return }
        guard case .end(.interrupted) = Sitting.afterSAdv(.pass, bControl: outcome) else { Issue.record("not stopped"); return }
    }

    @Test("`«` read by AX but not drawn during an S-adv sweep: mismatch")
    func sweepMismatch() throws {
        let variant = SAdvVariant(appearance: .dark, colouredMembers: true)
        let clean = Run.step(.sAdvSweep(variant), coloured: true)
        let index = try #require(Run.firstCapture("attempt", in: clean.step))
        let run = Run.step(.sAdvSweep(variant), coloured: true, faults: [index: .chevronOnlyInAX])
        guard case .mismatch = BControl.evaluate(run.report.chevronObservations.map(\.observation)) else { Issue.record("no mismatch"); return }
    }

    @Test("S-adv's `«` rest state: members added until `«` shows, then two episodes -> valid")
    func chevronRest() {
        let run = Run.step(.sAdvChevron(SAdvVariant(appearance: .dark, colouredMembers: false)), members: 4) { world in
            world.chevronWhenRestBelowPt = 226
        }
        #expect(run.report.status == .completed, "\(run.report.reason ?? "")")
        let outcome = BControl.evaluate(run.report.chevronObservations.map(\.observation))
        guard case .valid(let captures, let episodes) = outcome else { Issue.record("\(outcome)"); return }
        #expect(captures >= BControl.minCaptures && episodes >= BControl.minEpisodes)
        #expect(Sitting.afterSAdv(.pass, bControl: outcome) == .proceed)
        #expect(run.world.items.isEmpty)
    }

    @Test("no `«` even with 16 members: insufficient, the sitting stops before S1")
    func noChevron() {
        let run = Run.step(.sAdvChevron(SAdvVariant(appearance: .dark, colouredMembers: false)), members: 4) { world in
            world.chevronWhenRestBelowPt = -1000
        }
        #expect(run.report.reason == "no « (a) with 16 members")
        guard case .end(.interrupted) = Sitting.afterSAdv(.pass, bControl: BControl.evaluate(run.report.chevronObservations.map(\.observation))) else {
            Issue.record("not stopped")
            return
        }
    }
}

@Suite("T7 (c), Q5, Q17, Q18: controls, the notch, S-adv")
struct StageRuleTests {
    @Test("a member not drawn at its rest control makes the cycle inconclusive")
    func restControlMiss() throws {
        let clean = Run.step(.s1Confirm(144))
        let index = try #require(Run.firstCapture("rest control", in: clean.step))
        let run = Run.step(.s1Confirm(144), faults: [index: .memberUndrawn("hidden2")])
        #expect(run.report.cycles.first?.controlMiss == true)
        let tally = FallbackTally.tally(run.report.cycles)
        #expect(tally.byCause[.memberControl] == 4)
    }

    @Test("S1: a member drawn left of the notch is NO-GO")
    func leftOfNotch() {
        let run = Run.step(.s1Bracket([240])) { $0.hiddenEdgePt = 0 }
        #expect(run.report.status == .noGo)
    }

    @Test("S0 passes when no claim is granted; it is NO-GO when one is")
    func s0Outcomes() {
        #expect(Run.step(.s0, setup: Run.membersStay).report.s0?.outcome == .pass)
        let granted = Run.step(.s0)
        #expect(granted.report.s0?.outcome == .noGo)
        #expect(granted.report.status == .noGo)
    }

    @Test("an S-adv sweep passes on its variant; the other appearance is inconclusive")
    func sweeps() {
        #expect(Run.step(.sAdvSweep(SAdvVariant(appearance: .dark, colouredMembers: true)), coloured: true).report.sweep == .pass)
        #expect(Run.step(.sAdvSweep(SAdvVariant(appearance: .light, colouredMembers: false))).report.sweep == .inconclusive)
    }

    @Test("the placement gate refuses a bar whose members are not left of the spacer; teardown still runs")
    func placement() {
        let run = Run.step(.s1Bracket([144])) { $0.newestRightmost = true }
        #expect(run.report.status == .inconclusive)
        #expect(run.report.reason?.hasPrefix("placement gate") == true)
        #expect(run.world.items.isEmpty)
    }
}

@Suite("T7 (d): the claim API as part 2 hands it over")
struct ClaimCallSiteTests {
    static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")

    static func text(_ target: String) throws -> String {
        let dir = sources.appendingPathComponent(target)
        return try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }.sorted()
            .map { try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }.joined(separator: "\n")
    }

    @Test("Claim.decide is called once, per attempt; RegionClear.evaluate never directly")
    func usage() throws {
        let stage = try Self.text("IceBarStage")
        let core = try Self.text("IceBarRunCore")
        #expect(stage.components(separatedBy: "Claim.decide(").count - 1 == 1)
        #expect(!stage.contains("RegionClear.evaluate") && !core.contains("RegionClear.evaluate"))
        #expect(stage.components(separatedBy: "HiddenBaseline.evaluate(").count - 1 == 1)
        #expect(stage.contains("StartupCheck.evaluate("))
    }
}

@Suite("Risk K6: `«` (b) and the chevron's own AX frame")
struct ChevronFrameTests {
    @Test("with its own frame in the oracle's context (D6), (b) cannot see a listed chevron; without it, it can")
    func blindInsideItsFrame() throws {
        let world = FakeWorld(templates: StageFixtures.templates)
        world.chevronWhenRestBelowPt = 1000
        _ = world.launch(arguments: ["--glyphs", "hidden2"])
        let image = world.capture()
        let chevron = FakeWorld.chevronFrame.span
        func sighting(_ frames: [PtSpan]) throws -> ChevronSighting {
            try Oracle.label(image: image, helpers: [], chevron: StageFixtures.chevron,
                             context: OracleContext(notch: FakeWorld.geometry.notch, agentFrames: frames, leftmostReferenceOriginPt: nil)).chevron
        }
        #expect(try sighting([chevron]) == .absent)
        #expect(try sighting([]) == .present)
    }
}
