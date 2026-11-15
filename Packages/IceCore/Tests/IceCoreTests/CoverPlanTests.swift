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

    @Test("verified: its owner is hit somewhere and no other item is; a point that answers nothing or fails says nothing")
    func verified() {
        #expect(CoverPlan.isVerified(owner: 6, hits: [.silent, .silent, .owner(6)]))
        #expect(CoverPlan.isVerified(owner: 6, hits: [.owner(6), .owner(6), .owner(6)]))
        #expect(CoverPlan.isVerified(owner: 6, hits: [.failed, .owner(6), .silent]))
        #expect(!CoverPlan.isVerified(owner: 6, hits: [.silent, .silent, .silent]))
        #expect(!CoverPlan.isVerified(owner: 6, hits: [.failed, .failed, .failed]))
        #expect(!CoverPlan.isVerified(owner: 6, hits: [.owner(6), .owner(20), .owner(6)]))
        #expect(!CoverPlan.isVerified(owner: 6, hits: []))
    }

    @Test("silent: every point answers nothing; a failed call or an owner is not silence")
    func silent() {
        #expect(CoverPlan.isSilent([.silent, .silent, .silent]))
        #expect(!CoverPlan.isSilent([.silent, .failed, .silent]))
        #expect(!CoverPlan.isSilent([.silent, .owner(6), .silent]))
        #expect(!CoverPlan.isSilent([]))
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

/// Plan 2026-11-15-cover, Amendment B: a member whose app answers no hit test
/// is covered on the tree's word, once it has stood still and silent.
@Suite("CoverSilentTrack")
struct CoverSilentTrackTests {
    /// A second on at every pass.
    final class Clock {
        private var now = 0.0

        func tick() -> Double {
            now += 1
            return now
        }
    }

    let own: Int32 = 900
    let quiet: [CoverHit] = [.silent, .silent, .silent]
    let clock = Clock()

    func slot(_ owner: Int32, _ minX: Double, _ width: Double) -> CoverSlot {
        CoverSlot(owner: owner, minX: minX, maxX: minX + width)
    }

    /// One pass, a second after the last, over one candidate: tested with `hits` (not tested when `nil`),
    /// in a read that lists `slots` (the candidate alone by default).
    func pass(
        _ track: CoverSilentTrack, _ candidate: CoverSlot, hits: [CoverHit]? = [.silent, .silent, .silent], slots: [CoverSlot]? = nil
    ) -> CoverSilentTrack {
        track.advanced(
            candidates: [candidate], hitVerified: [], slots: slots ?? [candidate], hits: hits.map { [candidate: $0] } ?? [:], own: own,
            now: clock.tick()
        )
    }

    /// `passes` passes over the same read, the candidate tested and silent in each.
    func after(_ passes: Int, _ candidate: CoverSlot, slots: [CoverSlot]? = nil) -> CoverSilentTrack {
        (0..<passes).reduce(CoverSilentTrack()) { track, _ in pass(track, candidate, slots: slots) }
    }

    @Test("three silent passes with the slot unchanged stand; two do not")
    func stands() {
        let member = slot(3, 440, 28)
        #expect(after(2, member).standing.isEmpty)
        #expect(after(3, member).standing == [member])
        #expect(after(5, member).standing == [member])
    }

    @Test("passes closer together than the spacing count once: two reads of one moment are one observation")
    func spacing() {
        let member = slot(3, 440, 28)
        func pass(_ track: CoverSilentTrack, at now: Double) -> CoverSilentTrack {
            track.advanced(candidates: [member], hitVerified: [], slots: [member], hits: [member: quiet], own: own, now: now)
        }
        let crowded = [100.3, 100.3, 100.4, 101.0].reduce(CoverSilentTrack(), pass)
        #expect(crowded.standing.isEmpty)
        #expect(pass(pass(crowded, at: 101.3), at: 102.3).standing == [member])
        #expect([100.3, 100.3, 101.3, 101.3, 102.3].reduce(CoverSilentTrack(), pass).standing == [member])
    }

    @Test("a frame that moves more than a point starts again; within a point it goes on, at the new frame")
    func frames() {
        let member = slot(3, 440, 28)
        let nudged = CoverSlot(owner: 3, minX: 440.5, maxX: 468.5)
        let moved = slot(3, 442, 28)
        #expect(pass(after(2, member), nudged).standing == [nudged])
        let again = pass(after(3, member), moved)
        #expect(again.standing.isEmpty)
        #expect(pass(pass(again, moved), moved).standing == [moved])
    }

    @Test("a slot that goes and comes back starts again")
    func goneAndBack() {
        let member = slot(3, 440, 28)
        let gone = after(3, member).advanced(candidates: [], hitVerified: [], slots: [], hits: [:], own: own, now: clock.tick())
        let back = pass(gone, member)
        #expect(gone.standing.isEmpty && back.standing.isEmpty)
    }

    @Test("a failed call at any point resets the count and never counts towards it")
    func failed() {
        let member = slot(3, 440, 28)
        let broken: [CoverHit] = [.silent, .failed, .silent]
        #expect((0..<4).reduce(CoverSilentTrack()) { track, _ in pass(track, member, hits: broken) }.standing.isEmpty)
        let reset = pass(after(3, member), member, hits: broken)
        #expect(reset.standing.isEmpty)
        #expect(pass(reset, member).standing.isEmpty)
    }

    @Test("another item hit at any point takes the standing away")
    func vetoed() {
        let member = slot(3, 440, 28)
        let other: [CoverHit] = [.silent, .owner(20), .silent]
        #expect(pass(after(3, member), member, hits: other).standing.isEmpty)
    }

    @Test("a distinct slot that overlaps it, whoever owns it, removes it on that pass; an exact duplicate from another window does not")
    func overlaps() {
        let member = slot(3, 440, 28)
        let visible = slot(20, 460, 30)
        let sibling = slot(3, 450, 28)
        let touching = slot(20, 468, 30)
        // The same slot listed half a point off by another window: a distinct slot, by B3 (exact duplicates only).
        let nearCopy = CoverSlot(owner: 3, minX: 440.5, maxX: 468.5)
        for other in [visible, sibling, nearCopy] {
            #expect(pass(after(3, member), member, hits: nil, slots: [member, other]).standing.isEmpty)
            #expect(!after(3, member).stands(member, among: [member, other], own: own))
            #expect(after(4, member, slots: [member, other]).standing.isEmpty)
        }
        #expect(after(3, member, slots: [member, member, touching]).standing == [member])
        #expect(after(3, member).stands(member, among: [member, member, touching], own: own))
    }

    @Test("Ice's own divider, 16 pt at the right edge inside the last member's slot, is no overlap; any other slot of Ice's is")
    func ownDivider() {
        let member = slot(3, 602, 38)
        let divider = slot(own, 624, 16)
        #expect(after(3, member, slots: [member, divider]).standing == [member])
        #expect(after(3, member).stands(member, among: [member, divider], own: own))
        // Its icon, a divider-wide slot elsewhere in the member's slot, one that reaches out of it, and another app's.
        for other in [slot(own, 620, 33), slot(own, 610, 16), slot(own, 630, 16), slot(own, 618, 22), slot(20, 624, 16)] {
            #expect(after(3, member, slots: [member, other]).standing.isEmpty)
            #expect(!after(3, member).stands(member, among: [member, other], own: own))
        }
    }

    @Test("a standing slot that was not tested in a pass stays while the tree lists it; one that does not stand yet needs the test")
    func untested() {
        let member = slot(3, 440, 28)
        #expect(pass(after(3, member), member, hits: nil).standing == [member])
        #expect(pass(pass(after(2, member), member, hits: nil), member).standing.isEmpty)
    }

    @Test("a candidate the hit test confirmed is not tracked, and each silent slot has its own count")
    func separate() {
        let first = slot(3, 432, 28), second = slot(3, 460, 28), answering = slot(1, 500, 38)
        var track = CoverSilentTrack()
        for _ in 0..<2 {
            track = track.advanced(
                candidates: [first, answering], hitVerified: [answering], slots: [first, answering],
                hits: [first: quiet, answering: [.owner(1), .owner(1), .owner(1)]], own: own, now: clock.tick()
            )
        }
        track = track.advanced(
            candidates: [first, second, answering], hitVerified: [answering], slots: [first, second, answering],
            hits: [first: quiet, second: quiet], own: own, now: clock.tick()
        )
        #expect(track.standing == [first])
        #expect(!track.stands(second, among: [first, second, answering], own: own))
        #expect(!track.stands(answering, among: [first, second, answering], own: own))
    }
}
