// C2 T3 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 3): the measurement
// mode -- one full cycle per listed length, a `c2.point` per length, C1's
// staged teardown, and no scan or smoke of its own.
import C1Core
import C1Stage
import Foundation
import Testing

@Suite("I7 -- C2 measurement mode", .serialized)
struct I7C2MeasureTests {
    private func points(_ run: I7.Run) -> [(Double?, String?)] {
        run.evidence.allRecords().filter { $0.kind == "c2.point" }.map { ($0.fields["length"] as? Double, $0.fields["reading"] as? String) }
    }

    @Test("every listed length measured once, in order -> exit 0, one point each, no scan or smoke cycle, clean teardown")
    func measuresEveryLength() {
        let world = FakeBarWorld()
        let run = I7.run(world: world, extraHidden: 1, lengthPlan: .measure([600, 720, 900]))

        #expect(run.code == 0)
        let measured = points(run)
        #expect(measured.map(\.0) == [600, 720, 900])
        #expect(measured.allSatisfy { $0.1 == "hiddenNoFold" })
        #expect(!run.evidence.allRecords().contains { $0.kind == "cycle" && (($0.fields["label"] as? String)?.hasPrefix("scan.") == true || ($0.fields["label"] as? String)?.hasPrefix("smoke.") == true) })
        #expect(run.evidence.allRecords().contains { $0.kind == "teardown.helperDomains" && $0.fields["empty"] as? Bool == true })
        #expect(world.commandLog.contains("hidden-2.quit"))
    }

    @Test("Target never hides -> every point stillDrawn, still a completed measurement")
    func targetNeverHides() {
        let world = FakeBarWorld()
        world.setTargetNeverHides(true)
        let run = I7.run(world: world, lengthPlan: .measure([600, 900]))

        #expect(run.code == 0)
        #expect(points(run).map(\.1) == ["stillDrawn", "stillDrawn"])
    }

    @Test("the measurement verdict: a safety stop wins, then the gate, then completeness")
    func measurementVerdict() {
        #expect(StageC1.measurementVerdict(safetyStop: .needingAttention, placementGateFailureReason: "x", measured: 1, planned: 1) == .safetyStopNeedingAttention)
        #expect(StageC1.measurementVerdict(safetyStop: .stop, placementGateFailureReason: nil, measured: 0, planned: 1) == .safetyStop)
        #expect(StageC1.measurementVerdict(safetyStop: nil, placementGateFailureReason: "helpers not leftmost", measured: 0, planned: 1) == .inconclusive("helpers not leftmost"))
        #expect(StageC1.measurementVerdict(safetyStop: nil, placementGateFailureReason: nil, measured: 1, planned: 2) == .inconclusive("measured 1 of 2 lengths"))
        #expect(StageC1.measurementVerdict(safetyStop: nil, placementGateFailureReason: nil, measured: 2, planned: 2) == .pass)
    }
}
