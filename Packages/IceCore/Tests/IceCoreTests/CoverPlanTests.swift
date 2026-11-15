import Testing
@testable import IceCore

/// Plan 2026-11-15-cover, D1 and D2: which slots a hit test must confirm, the
/// blocks the confirmed ones make, and the budget of image calls.
@Suite("CoverPlan")
struct CoverPlanTests {
    func slot(_ owner: Int32, _ minX: Double, _ width: Double) -> CoverSlot {
        CoverSlot(owner: owner, minX: minX, maxX: minX + width)
    }

    /// The owner's Sidecar bar, 2026-11-15: seven members, the divider's gap, the visible items.
    var sidecar: [CoverSlot] {
        [
            slot(1, 488, 38), slot(2, 526, 38), slot(3, 564, 38), slot(4, 602, 38), slot(5, 640, 31), slot(6, 671, 36),
            slot(7, 707, 32), slot(90, 753, 20), slot(20, 788, 42), slot(21, 830, 32), slot(99, 900, 33),
        ]
    }

    @Test("a pid is coverable only if every item it owns is a hidden member")
    func coverable() {
        #expect(CoverPlan.coverable(memberOwners: [1, 2, 2, 3], visibleOwners: [3, 20]) == [1, 2])
        #expect(CoverPlan.coverable(memberOwners: [], visibleOwners: [20]).isEmpty)
    }

    @Test("candidates are the slots of coverable owners, once each, left to right")
    func candidates() {
        let stale = slot(7, 1105, 32)
        let found = CoverPlan.candidates(slots: sidecar + [stale, slot(1, 488, 38)], coverable: [1, 7, 55])
        #expect(found == [slot(1, 488, 38), slot(7, 707, 32), stale])
        #expect(CoverPlan.candidates(slots: sidecar, coverable: []).isEmpty)
    }

    @Test("a slot is tested at a quarter, a half and three quarters of its width")
    func points() {
        #expect(CoverPlan.verificationPoints(slot(1, 100, 40)) == [110, 120, 130])
    }

    @Test("verified: its owner is hit somewhere and no other item is; blocked points say nothing")
    func verified() {
        #expect(CoverPlan.isVerified(owner: 6, hits: [nil, nil, 6]))
        #expect(CoverPlan.isVerified(owner: 6, hits: [6, 6, 6]))
        #expect(!CoverPlan.isVerified(owner: 6, hits: [nil, nil, nil]))
        #expect(!CoverPlan.isVerified(owner: 6, hits: [6, 20, 6]))
        #expect(!CoverPlan.isVerified(owner: 6, hits: []))
    }

    @Test("the owner's Sidecar members make one block, padded 4 pt where nothing else stands")
    func oneBlock() {
        let members = Array(sidecar.prefix(7))
        let blocks = CoverPlan.blocks(verified: members, others: Array(sidecar.dropFirst(7)), barWidth: 1314, notch: nil)
        #expect(blocks == [484...743])
    }

    @Test("an unverified slot between members splits the block, and padding stops at it")
    func splitByUnverified() {
        let verified = [slot(1, 488, 38), slot(2, 526, 38), slot(7, 707, 32)]
        let others = [slot(5, 640, 31), slot(6, 671, 36), slot(90, 753, 20)]
        let blocks = CoverPlan.blocks(verified: verified, others: others, barWidth: 1314, notch: nil)
        #expect(blocks == [484...568, 707...743])
    }

    @Test("padding never enters a neighbour's slot, on either side")
    func paddingStops() {
        let blocks = CoverPlan.blocks(verified: [slot(1, 100, 30)], others: [slot(20, 60, 38), slot(21, 132, 30)], barWidth: 500, notch: nil)
        #expect(blocks == [98...132])
    }

    @Test("many islands give one block each; slots 4 pt or less apart merge")
    func islands() {
        let verified = [slot(1, 10, 20), slot(2, 34, 20), slot(3, 100, 20), slot(4, 200, 20), slot(5, 300, 20)]
        let blocks = CoverPlan.blocks(verified: verified, others: [], barWidth: 400, notch: nil)
        #expect(blocks == [6...58, 96...124, 196...224, 296...324])
    }

    @Test("a block is clipped to the bar and kept out of the notch")
    func clipping() {
        #expect(CoverPlan.blocks(verified: [slot(1, 0, 30)], others: [], barWidth: 32, notch: nil) == [0...32])
        let notch = 771.5...956.5
        #expect(CoverPlan.blocks(verified: [slot(1, 930, 60)], others: [], barWidth: 1728, notch: notch) == [956.5...994])
        #expect(CoverPlan.blocks(verified: [slot(1, 760, 220)], others: [], barWidth: 1728, notch: notch) == [756...771.5, 956.5...984])
        #expect(CoverPlan.blocks(verified: [slot(1, 800, 100)], others: [], barWidth: 1728, notch: notch).isEmpty)
    }

    @Test("nothing verified, no block; a slot verified twice counts once")
    func edges() {
        #expect(CoverPlan.blocks(verified: [], others: sidecar, barWidth: 1314, notch: nil).isEmpty)
        #expect(CoverPlan.blocks(verified: [slot(1, 100, 30), slot(1, 100, 30)], others: [], barWidth: 500, notch: nil) == [96...134])
    }
}

@Suite("CoverCaptureBudget")
struct CoverCaptureBudgetTests {
    @Test("four image calls within a second, the fifth waits for the next session")
    func session() {
        var budget = CoverCaptureBudget()
        let taken1 = budget.take(2, now: 100)
        #expect(taken1)
        let taken2 = budget.take(2, now: 100.4)
        #expect(taken2)
        let taken3 = budget.take(1, now: 100.5)
        #expect(!taken3)
        let taken4 = budget.take(1, now: 111.9)
        #expect(!taken4)
        let taken5 = budget.take(1, now: 112)
        #expect(taken5)
    }

    @Test("a call after the session's second, with room left, still waits: the session is over")
    func windowCloses() {
        var budget = CoverCaptureBudget()
        let taken6 = budget.take(1, now: 0)
        #expect(taken6)
        let taken7 = budget.take(1, now: 1.5)
        #expect(!taken7)
        #expect(budget.nextAllowed(now: 1.5) == 12)
        let taken8 = budget.take(4, now: 12)
        #expect(taken8)
    }

    @Test("more than a session holds is refused and counts nothing")
    func tooMany() {
        var budget = CoverCaptureBudget()
        let taken9 = budget.take(5, now: 0)
        #expect(!taken9)
        let taken10 = budget.take(0, now: 0)
        #expect(!taken10)
        let taken11 = budget.take(4, now: 0)
        #expect(taken11)
    }

    @Test("before any call a session may start now")
    func fresh() {
        #expect(CoverCaptureBudget().nextAllowed(now: 7) == 7)
    }
}
