import Testing
@testable import IceWatchCore

/// The watchdog's trip rules (plan 2026-09-24-ice-first-run.md, section 5).
/// Frames are display-local points on a 1728 pt wide, 33 pt high bar; the
/// numbers mirror recorded ones: a 17.5 pt `«`, a 16 pt pill, a ≈ 20 pt
/// capture indicator, items that overflow behind `«` overlapping it by more
/// than half.
@Suite("TripEvaluator")
struct TripEvaluatorTests {
    let bar = BarLine(minX: 0, maxX: 1728, height: 33)

    func frame(_ x: Double, _ w: Double, y: Double = 4.5) -> WatchFrame {
        WatchFrame(minX: x, minY: y, width: w, height: 24)
    }

    func item(_ pid: Int32, _ x: Double, _ w: Double = 24, child: Int = 0, isIce: Bool = false, y: Double = 4.5) -> WatchItem {
        WatchItem(id: ItemID(pid: pid, child: child), identifier: "", frame: frame(x, w, y: y), isIce: isIce)
    }

    func tick(agents: [WatchFrame] = [], agentState: ReadState = .ok, duration: Double = 0.03, _ processes: [ProcessRead]) -> Tick {
        Tick(duration: duration, agentFrames: agents, agentState: agentState, processes: processes)
    }

    func read(_ pid: Int32, _ items: [WatchItem], _ state: ReadState = .ok) -> ProcessRead {
        ProcessRead(pid: pid, state: state, items: items)
    }

    // A quiet bar: two user items side by side with the recorded 2 pt AX
    // padding overlap, the clock-sized agent frame far right.
    var quiet: Tick {
        tick(agents: [frame(1592, 116)], [read(10, [item(10, 1100)]), read(11, [item(11, 1122)])])
    }

    @Test("a quiet bar never trips")
    func quietBar() {
        var evaluator = TripEvaluator(bar: bar)
        for _ in 0..<5 {
            #expect(evaluator.evaluate(quiet).isEmpty)
        }
    }

    @Test("an item overlapping a chevron-width agent frame trips on its first tick")
    func foldWithOverlapTripsAtOnce() {
        var evaluator = TripEvaluator(bar: bar)
        // Recorded overflow: the item's frame overlaps `«` by 54-68 %.
        let folded = tick(agents: [frame(1000, 17.5)], [read(10, [item(10, 1005, 14)])])
        #expect(evaluator.evaluate(folded) == [.foldWithOverlap(ItemID(pid: 10, child: 0))])
    }

    @Test("a chevron-width agent frame alone trips on its second tick, not its first")
    func foldPersistingNeedsTwoTicks() {
        var evaluator = TripEvaluator(bar: bar)
        let chevron = tick(agents: [frame(1000, 17.5)], [read(10, [item(10, 1100)])])
        #expect(evaluator.evaluate(chevron).isEmpty)
        #expect(evaluator.evaluate(chevron) == [.foldPersisting])
    }

    @Test("a chevron that goes away after one tick clears the pending fold")
    func chevronClears() {
        var evaluator = TripEvaluator(bar: bar)
        let chevron = tick(agents: [frame(1000, 17.5)], [read(10, [item(10, 1100)])])
        #expect(evaluator.evaluate(chevron).isEmpty)
        #expect(evaluator.evaluate(quiet).isEmpty)
        #expect(evaluator.evaluate(chevron).isEmpty)
    }

    @Test("an unreadable MenuBarAgent neither trips nor clears a pending fold")
    func unreadableAgentKeepsPending() {
        var evaluator = TripEvaluator(bar: bar)
        let chevron = tick(agents: [frame(1000, 17.5)], [read(10, [item(10, 1100)])])
        let agentFailed = tick(agentState: .failed, [read(10, [item(10, 1100)])])
        #expect(evaluator.evaluate(chevron).isEmpty)
        #expect(evaluator.evaluate(agentFailed).isEmpty)
        #expect(evaluator.evaluate(chevron) == [.foldPersisting])
    }

    @Test("the pill and the capture indicator never trip")
    func pillAndIndicator() {
        var evaluator = TripEvaluator(bar: bar)
        // The pill (16 pt) and the indicator (≈ 20 pt), each overlapped by an
        // item as they would be when drawn right next to it.
        let pill = tick(agents: [frame(1035, 16)], [read(10, [item(10, 1040, 14)])])
        let indicator = tick(agents: [frame(1143, 20)], [read(10, [item(10, 1150, 14)])])
        for _ in 0..<3 {
            #expect(evaluator.evaluate(pill).isEmpty)
            #expect(evaluator.evaluate(indicator).isEmpty)
        }
    }

    @Test("a chevron-width agent frame off the bar is ignored")
    func chevronOffBar() {
        var evaluator = TripEvaluator(bar: bar)
        let parked = tick(agents: [frame(7, 17.5, y: 1105)], [read(10, [item(10, 1100)])])
        #expect(evaluator.evaluate(parked).isEmpty)
        #expect(evaluator.evaluate(parked).isEmpty)
    }

    @Test("Ice's own items never form the item side of a fold")
    func iceItemOverlappingChevron() {
        var evaluator = TripEvaluator(bar: bar)
        let iceFolded = tick(agents: [frame(1000, 17.5)], [read(20, [item(20, 1005, 14, isIce: true)])])
        // Not at once (the item side is Ice's); the chevron alone still trips
        // on its second tick.
        #expect(evaluator.evaluate(iceFolded).isEmpty)
        #expect(evaluator.evaluate(iceFolded) == [.foldPersisting])
    }

    @Test("two stacked items trip on the second tick, not the first")
    func stackNeedsTwoTicks() {
        var evaluator = TripEvaluator(bar: bar)
        let stacked = tick([read(10, [item(10, 1100)]), read(11, [item(11, 1104)])])
        #expect(evaluator.evaluate(stacked).isEmpty)
        #expect(evaluator.evaluate(stacked) == [.stack(ItemID(pid: 10, child: 0), ItemID(pid: 11, child: 0))])
    }

    @Test("the recorded 2 pt padding overlap is not a stack")
    func paddingOverlap() {
        var evaluator = TripEvaluator(bar: bar)
        // 24 pt items, 2 pt overlap = 8 % of the narrower.
        let adjacent = tick([read(10, [item(10, 1100)]), read(11, [item(11, 1122)])])
        #expect(evaluator.evaluate(adjacent).isEmpty)
        #expect(evaluator.evaluate(adjacent).isEmpty)
    }

    @Test("Ice's own items never form a stack")
    func iceItemsNeverStack() {
        var evaluator = TripEvaluator(bar: bar)
        // The hidden divider at 10 000 pt has an AX frame 5002 pt wide that
        // covers its neighbours (recorded); it must not trip anything.
        let divider = WatchItem(id: ItemID(pid: 20, child: 1), identifier: "Ice.ControlItem.Hidden", frame: frame(1012, 5002), isIce: true)
        let wide = tick([read(10, [item(10, 1016, 14)]), read(20, [divider])])
        #expect(evaluator.evaluate(wide).isEmpty)
        #expect(evaluator.evaluate(wide).isEmpty)
    }

    @Test("a failed read neither trips nor clears a pending stack")
    func failedReadKeepsPendingStack() {
        var evaluator = TripEvaluator(bar: bar)
        let stacked = tick([read(10, [item(10, 1100)]), read(11, [item(11, 1104)])])
        let failed = tick([read(10, [item(10, 1100)]), read(11, [], .failed)])
        #expect(evaluator.evaluate(stacked).isEmpty)
        #expect(evaluator.evaluate(failed).isEmpty)
        #expect(evaluator.evaluate(stacked) == [.stack(ItemID(pid: 10, child: 0), ItemID(pid: 11, child: 0))])
    }

    @Test("a stack that resolves clears the pending pair")
    func stackResolves() {
        var evaluator = TripEvaluator(bar: bar)
        let stacked = tick([read(10, [item(10, 1100)]), read(11, [item(11, 1104)])])
        let apart = tick([read(10, [item(10, 1100)]), read(11, [item(11, 1122)])])
        #expect(evaluator.evaluate(stacked).isEmpty)
        #expect(evaluator.evaluate(apart).isEmpty)
        #expect(evaluator.evaluate(stacked).isEmpty)
    }

    @Test("a slow tick is not evaluated and keeps what is pending")
    func slowTick() {
        var evaluator = TripEvaluator(bar: bar)
        let chevron = tick(agents: [frame(1000, 17.5)], [read(10, [item(10, 1100)])])
        let slowFolded = tick(agents: [frame(1000, 17.5)], duration: 0.6, [read(10, [item(10, 1005, 14)])])
        #expect(evaluator.evaluate(chevron).isEmpty)
        #expect(evaluator.evaluate(slowFolded).isEmpty)
        #expect(evaluator.evaluate(chevron) == [.foldPersisting])
    }

    @Test("an item that moves along the bar, or goes missing, or is parked, does not trip")
    func movedMissingParked() {
        var evaluator = TripEvaluator(bar: bar)
        #expect(evaluator.evaluate(quiet).isEmpty)
        let moved = tick([read(10, [item(10, 1132)]), read(11, [item(11, 1154)])])
        let missing = tick([read(10, [item(10, 1132)]), read(11, [])])
        let parked = tick([read(10, [item(10, 1132)]), read(11, [item(11, 7, y: 1105)])])
        for t in [moved, missing, parked, parked] {
            #expect(evaluator.evaluate(t).isEmpty)
        }
    }
}
