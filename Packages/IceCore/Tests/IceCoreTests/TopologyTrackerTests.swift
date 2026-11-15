import Testing
@testable import IceCore

/// Plan 2026-11-15-secondary-display, T2d: while more than one display is
/// connected (and the topology is not a measured one), Ice does not hide; a
/// topology change blocks at once and is decided only when it has held 2 s;
/// work begun under an older topology is dropped.
@Suite("TopologyTracker")
struct TopologyTrackerTests {
    let one = DisplayTopology(fingerprint: "1:1728x1117", count: 1)
    let two = DisplayTopology(fingerprint: "1:1728x1117|7:1314x985", count: 2)

    @Test("a single display, held, does not block")
    func singleHeld() {
        var tracker = TopologyTracker()
        tracker.observe(one, now: 0)
        #expect(tracker.blockReason(now: 0, supported: true) == nil)
    }

    @Test("the first topology seen is not a change: no settling at launch")
    func firstIsNotAChange() {
        var tracker = TopologyTracker()
        tracker.observe(two, now: 100)
        #expect(tracker.blockReason(now: 100, supported: false) == .multipleDisplays(2))
        #expect(tracker.generation == 0)
    }

    @Test("two displays block, unless the topology is a supported one")
    func twoDisplays() {
        var tracker = TopologyTracker()
        tracker.observe(two, now: 0)
        #expect(tracker.blockReason(now: 10, supported: false) == .multipleDisplays(2))
        #expect(tracker.blockReason(now: 10, supported: true) == nil)
    }

    @Test("a change blocks at once and bumps the generation; decided after 2 s held")
    func changeSettles() {
        var tracker = TopologyTracker()
        tracker.observe(two, now: 0)
        tracker.observe(one, now: 50)
        #expect(tracker.generation == 1)
        #expect(tracker.blockReason(now: 50, supported: true) == .displaysSettling)
        #expect(tracker.blockReason(now: 51.9, supported: true) == .displaysSettling)
        #expect(tracker.blockReason(now: 52, supported: true) == nil)
    }

    @Test("two changes within 2 s settle from the last one")
    func flapping() {
        var tracker = TopologyTracker()
        tracker.observe(one, now: 0)
        tracker.observe(two, now: 10)
        tracker.observe(one, now: 11)
        #expect(tracker.generation == 2)
        #expect(tracker.blockReason(now: 12.5, supported: true) == .displaysSettling)
        #expect(tracker.blockReason(now: 13, supported: true) == nil)
    }

    @Test("connect, disconnect, connect: each a change; the same topology observed again is not")
    func connectDisconnectConnect() {
        var tracker = TopologyTracker()
        tracker.observe(one, now: 0)
        tracker.observe(two, now: 5)
        tracker.observe(one, now: 6)
        tracker.observe(two, now: 7)
        tracker.observe(two, now: 8)
        #expect(tracker.generation == 3)
        #expect(tracker.blockReason(now: 8.5, supported: false) == .displaysSettling)
        #expect(tracker.blockReason(now: 9, supported: false) == .multipleDisplays(2))
        #expect(tracker.blockReason(now: 20, supported: false) == .multipleDisplays(2))
    }

    @Test("work carrying an older generation is not accepted")
    func staleWork() {
        var tracker = TopologyTracker()
        tracker.observe(one, now: 0)
        let begun = tracker.generation
        #expect(tracker.accepts(begun))
        tracker.observe(two, now: 1)
        #expect(!tracker.accepts(begun))
        #expect(tracker.accepts(tracker.generation))
    }

    @Test("before any observation nothing blocks and every generation 0 is current")
    func unobserved() {
        let tracker = TopologyTracker()
        #expect(tracker.blockReason(now: 0, supported: false) == nil)
        #expect(tracker.accepts(0))
    }
}

@Suite("IceBarHidingStatus, displays")
struct DisplayStatusTests {
    @Test("the two display reasons have an owner line and a log name")
    func lines() {
        let multiple = IceBarHidingStatus.state(.blocked(reasons: [.multipleDisplays(2)]))
        let settling = IceBarHidingStatus.state(.blocked(reasons: [.displaysSettling]))
        #expect(multiple.logSummary == "blocked(multipleDisplays:2)")
        #expect(settling.logSummary == "blocked(displaysSettling)")
        #expect(multiple.message?.contains("more than one display") == true)
        #expect(settling.message?.contains("displays changed") == true)
    }
}

@Suite("PreferenceHidingPreconditionResult.adding")
struct PreconditionAddingTests {
    @Test("adding a reason blocks an ok result and appends to a blocked one")
    func adding() {
        #expect(PreferenceHidingPreconditionResult.ok.adding(.displaysSettling) == .blocked([.displaysSettling]))
        let blocked = PreferenceHidingPreconditionResult.blocked([.ownReadNotOk(.failed)])
        #expect(blocked.adding(.multipleDisplays(2)) == PreferenceHidingPreconditionResult.blocked([.ownReadNotOk(.failed), .multipleDisplays(2)]))
    }
}
