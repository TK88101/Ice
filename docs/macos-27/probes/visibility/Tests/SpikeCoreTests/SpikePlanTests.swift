// T0 (docs/plans/2026-10-03-icebar-build.md, section 7 note 1): spike A's
// profiles and lengths.
import C2Core
import SpikeCore
import Testing

@Suite("T0: spike A plan")
struct SpikePlanTests {
    @Test("profiles run k outermost, so k = 1 is decided first")
    func profileOrder() {
        let profiles = SpikeAPlan.profiles(members: [1, 2], menus: [.short, .mid])
        #expect(profiles == [
            SpikeProfile(members: 1, menu: .short), SpikeProfile(members: 1, menu: .mid),
            SpikeProfile(members: 2, menu: .short), SpikeProfile(members: 2, menu: .mid),
        ])
    }

    @Test("the standard plan is k = 1, 2, 4, 8 by short, mid")
    func standard() {
        #expect(SpikeAPlan.standardMembers == [1, 2, 4, 8])
        #expect(SpikeAPlan.standardMenus == [.short, .mid])
        #expect(SpikeAPlan.profiles(members: SpikeAPlan.standardMembers, menus: SpikeAPlan.standardMenus).count == 8)
    }

    @Test("the standard lengths are 408 to 1000 by 16, on C1's grid")
    func standardLengths() {
        let values = SpikeLengths.standard.values
        #expect(values.first == 408)
        #expect(values.contains(600) && values.contains(728) && values.contains(840))
        #expect(values.last == 1000)
        #expect(values.count == 38)
        #expect(values[1] - values[0] == 16)
    }

    @Test("lengths are refused outside vzhelper's 0...1000 or with a non-positive step")
    func refused() {
        #expect(SpikeLengths(from: 400, through: 1016, step: 16) == nil)
        #expect(SpikeLengths(from: -16, through: 400, step: 16) == nil)
        #expect(SpikeLengths(from: 400, through: 300, step: 16) == nil)
        #expect(SpikeLengths(from: 400, through: 400, step: 0) == nil)
        #expect(SpikeLengths(from: 400, through: 400, step: 16)?.values == [400])
    }

    @Test("a spec parses as from:through:step")
    func spec() {
        #expect(SpikeLengths(spec: "600:896:16")?.values.count == 19)
        #expect(SpikeLengths(spec: "600:896") == nil)
        #expect(SpikeLengths(spec: "a:b:c") == nil)
    }
}
