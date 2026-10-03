// T7 (docs/plans/2026-10-03-icebar-c-runner.md): the real step orchestration on
// the fake bar -- launch, placement, warm-up, a cycle, teardown.
import C2Core
import IceBarRunCore
@testable import IceBarStage
import Testing

@Suite("T7: a step on the fake bar")
struct StepSmokeTests {
    @Test("pushed far enough the members are off: the length is in band; teardown leaves nothing")
    func inBand() {
        let world = FakeWorld(templates: StageFixtures.templates)
        let evidence = FakeEvidence()
        let step = IceBarStep(environment: Fake.environment(world, evidence: evidence), plan: Fake.plan(.s1Bracket([144])), templates: StageFixtures.templates)
        let report = step.run()
        #expect(report.status == .completed, "\(report.reason ?? "")")
        #expect(report.points == [ReportPoint(length: 144, reading: "hiddenNoFold")], "\(evidence.log.joined(separator: "\n"))")
        #expect(world.items.isEmpty)
    }

    @Test("pushed 16 pt the members are still drawn in the region: not in band")
    func stillDrawn() {
        let world = FakeWorld(templates: StageFixtures.templates)
        let step = IceBarStep(environment: Fake.environment(world), plan: Fake.plan(.s1Bracket([16])), templates: StageFixtures.templates)
        let report = step.run()
        #expect(report.status == .completed, "\(report.reason ?? "")")
        #expect(report.points == [ReportPoint(length: 16, reading: "stillDrawn")])
    }
}
