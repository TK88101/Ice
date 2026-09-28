// C2 T3 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 4): the Menus helper
// on the fake bar -- calibrated to its width class, activated, checked
// frontmost before every cycle, and reaped.
import C1Core
import C1Stage
import C2Core
import Foundation
import Testing

@Suite("I7 -- C2 Menus", .serialized)
struct I7C2MenusTests {
    @Test("mid: calibrated to 11 menus (last edge 710), frontmost, measured, Menus quit at teardown")
    func midCalibratesAndMeasures() {
        let world = FakeBarWorld()
        let frontmost = FakeFrontmost()
        let run = I7.run(world: world, lengthPlan: .measure([700]), menus: .mid, frontmost: frontmost)

        #expect(run.code == 0)
        let calibrated = run.evidence.allRecords().first { $0.kind == "menus.calibrated" }
        #expect(calibrated?.fields["count"] as? Int == 11)
        #expect((calibrated?.fields["rightEdges"] as? [Double])?.last == 710)
        #expect(frontmost.commands.first == "menus 1")
        #expect(frontmost.commands.last == "menus 11")
        #expect(run.evidence.allRecords().contains { $0.kind == "c2.point" })
        #expect(world.commandLog.contains("menus.quit"))
    }

    @Test("long: 16 menus (last edge 1010)")
    func longCalibrates() {
        let run = I7.run(world: FakeBarWorld(), lengthPlan: .measure([700]), menus: .long)
        let calibrated = run.evidence.allRecords().first { $0.kind == "menus.calibrated" }
        #expect(calibrated?.fields["count"] as? Int == 16)
    }

    @Test("something else comes forward after the first length -> that length measured, the next not shown after three attempts, never a hide")
    func frontmostStolen() {
        let frontmost = FakeFrontmost()
        // Read 1: activation check; read 2: the first length's preflight;
        // from read 3 (the second length's preflight) on, stolen.
        frontmost.setStealAtRead(3)
        let run = I7.run(world: FakeBarWorld(), lengthPlan: .measure([700, 720]), menus: .short, frontmost: frontmost)

        #expect(run.evidence.allRecords().contains { $0.kind == "preflight.frontmostLost" })
        let points = run.evidence.allRecords().filter { $0.kind == "c2.point" }
        #expect(points.map { $0.fields["reading"] as? String } == ["hiddenNoFold", "notShown"])
        #expect(points.last?.fields["attempts"] as? Int == C2Retry.maxAttempts)
        #expect(!run.evidence.allRecords().contains { $0.kind == "preflight.relaunchOnce" })
    }
}
