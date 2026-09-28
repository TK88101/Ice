// C2 T3 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 3): C1's real stage
// orchestration with k > 1 hidden items, on the fake bar -- every hidden item
// is launched, placed, verified, restored and reaped; one that never hides
// keeps the section from ever counting as hidden.
import C1Core
import C1Stage
import Foundation
import Testing

@Suite("I7 -- C2 hidden section (k > 1)", .serialized)
struct I7C2HiddenSectionTests {
    @Test("k = 3 on a bar that hides every item -> PASS, every hidden item launched, placed left of the spacer, and quit")
    func threeHiddenPass() {
        let world = FakeBarWorld()
        let run = I7.run(world: world, extraHidden: 2)

        let trail = run.evidence.allRecords().filter { ["verify.section", "verify.skipped", "step.abort", "preflight.orderFailed", "preflight.notSettled", "step3.baselineAttempt", "run.verdict"].contains($0.kind) }.prefix(6).map { "\($0.kind) \($0.fields)" }
        #expect(run.code == 0, "\(trail.joined(separator: "\n"))")
        #expect(run.evidence.lastVerdict() == "pass")
        let launched = run.evidence.allRecords().first { $0.kind == "step2.launched" }
        #expect((launched?.fields["extraHidden"] as? [Any])?.count == 2)
        let gate = run.evidence.allRecords().first { $0.kind == "placement.gateRead" }
        #expect((gate?.fields["extraHiddenMinXs"] as? [Any])?.count == 2)
        #expect(world.commandLog.contains("hidden-2.quit"))
        #expect(world.commandLog.contains("hidden-3.quit"))
        #expect(world.commandLog.contains("target.quit"))
    }

    @Test("k = 3 with hidden-3 never hiding -> no scanned length hides the section: PROVISIONAL FAIL, every helper reaped")
    func oneItemNeverHides() {
        let world = FakeBarWorld()
        world.setHiddenExtraNeverHides(3)
        let run = I7.run(world: world, extraHidden: 2)

        #expect(run.code == 1)
        #expect(run.evidence.lastVerdict()?.hasPrefix("provisionalFail") == true)
        #expect(!run.evidence.allRecords().contains { $0.kind == "cycle" && ($0.fields["reading"] as? String) == "hidden(folded: false)" })
        // For the right reason: hidden-3 (the third item) stays drawn while the others hide.
        let section = run.evidence.allRecords().first { $0.kind == "verify.section" }
        #expect(section?.fields["readings"] as? [String] == ["hidden(folded: false)", "hidden(folded: false)", "stillDrawn"])
        #expect(world.commandLog.contains("hidden-2.quit"))
        #expect(world.commandLog.contains("hidden-3.quit"))
    }

    @Test("k = 1 (no extra hidden item) records an empty extra list -- C1 unchanged")
    func kOneRecordsNoExtras() {
        let world = FakeBarWorld()
        let run = I7.run(world: world, dry: true)
        let launched = run.evidence.allRecords().first { $0.kind == "step2.launched" }
        #expect((launched?.fields["extraHidden"] as? [Any])?.isEmpty == true)
        #expect(!world.commandLog.contains { $0.hasPrefix("hidden-") })
    }
}
