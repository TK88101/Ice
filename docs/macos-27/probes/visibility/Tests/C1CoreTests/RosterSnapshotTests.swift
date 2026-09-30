import Testing
@testable import C1Core

/// Section 3 condition 4: "the roster equals the snapshot (no item
/// appeared, left or reordered)". The snapshot also carries the capture
/// indicator's frame (section 3's own definition of "the roster snapshot"),
/// used by the baseline-equivalence check (`BaselineEquivalenceTests`) --
/// its equality is not itself one of the four roster outcomes.
@Suite("RosterSnapshotCheck")
struct RosterSnapshotCheckTests {
    let frame = BarFrame(minX: 10, minY: 0, width: 20, height: 22)

    func snapshot(_ items: [String], frame: BarFrame? = nil) -> RosterSnapshot {
        RosterSnapshot(items: items, indicatorFrame: frame ?? self.frame)
    }

    @Test("no previous snapshot fails closed")
    func missingSnapshot() {
        #expect(RosterSnapshotCheck.compare(current: snapshot(["a", "b"]), previous: nil) == .missingSnapshot)
    }

    @Test("the same items, same order, same indicator -> equal")
    func equal() {
        let previous = snapshot(["a", "b"])
        let current = snapshot(["a", "b"])
        #expect(RosterSnapshotCheck.compare(current: current, previous: previous) == .equal)
    }

    @Test("a new item on the bar -> appeared")
    func appeared() {
        let previous = snapshot(["a", "b"])
        let current = snapshot(["a", "b", "c"])
        #expect(RosterSnapshotCheck.compare(current: current, previous: previous) == .appeared(["c"]))
    }

    @Test("an item gone from the bar -> left")
    func left() {
        let previous = snapshot(["a", "b", "c"])
        let current = snapshot(["a", "c"])
        #expect(RosterSnapshotCheck.compare(current: current, previous: previous) == .left(["b"]))
    }

    @Test("the same items in a different order -> reordered")
    func reordered() {
        let previous = snapshot(["a", "b"])
        let current = snapshot(["b", "a"])
        #expect(RosterSnapshotCheck.compare(current: current, previous: previous) == .reordered)
    }

    @Test("appeared takes priority over left when both happen at once")
    func appearedTakesPriorityOverLeft() {
        let previous = snapshot(["a", "b"])
        let current = snapshot(["a", "c"]) // b left, c appeared
        #expect(RosterSnapshotCheck.compare(current: current, previous: previous) == .appeared(["c"]))
    }
}
