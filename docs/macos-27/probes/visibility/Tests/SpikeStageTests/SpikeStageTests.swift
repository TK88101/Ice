// T0: the spike stage on the fake bar -- the sweep finds the band, the
// stop rules, spike B's three outcomes, and a teardown that leaves nothing.
import C2Core
import SpikeCore
@testable import SpikeStage
import Testing

@Suite("T0: spike stage on the fake bar")
struct SpikeStageTests {
    @Test("spike A: the lengths that push the member off are the band, for k = 1 and k = 2; nothing is left behind")
    func band() {
        let world = SpikeFakeWorld(templates: SpikeFake.templates)
        let evidence = SpikeFakeEvidence()
        let result = SpikeFake.stage(world, plan: SpikeFake.plan(members: [1, 2], runB: false), evidence: evidence).run()
        #expect(result.a.band(members: 1, menu: .short) == Band(lo: 144, hi: 176, count: 2), "\(evidence.log.joined(separator: "\n"))")
        #expect(result.a.band(members: 2, menu: .short) == Band(lo: 144, hi: 176, count: 2))
        #expect(result.a.profiles.map(\.problem) == [nil, nil])
        #expect(result.a.profiles[0].records.map(\.outcome) == [.drawn(["hidden2"]), .drawn(["hidden2"]), .drawn(["hidden2"]), .drawn(["hidden2"]), .hiddenClean, .hiddenClean])
        #expect(result.b == nil)
        #expect(world.items.isEmpty)
        #expect(world.spacerLength == nil)
        #expect(evidence.kinds.filter { $0 == "step" }.count == 12)
        #expect(evidence.kinds.contains("teardown"))
    }

    @Test("every length is a jump from rest, with a restore control between")
    func jumpsFromRest() {
        let world = SpikeFakeWorld(templates: SpikeFake.templates)
        _ = SpikeFake.stage(world, plan: SpikeFake.plan(runB: false)).run()
        let spacer = world.commands.filter { $0.hasPrefix("length") || $0 == "rest" }
        #expect(spacer == ["length 16.0", "rest", "length 48.0", "rest", "length 80.0", "rest", "length 112.0", "rest", "length 144.0", "rest", "length 176.0", "rest", "rest"])
    }

    @Test("a bar with no room (the spacer pushes nothing): no band at k = 1, spike B not run, the owner is asked")
    func noBand() {
        let world = SpikeFakeWorld(templates: SpikeFake.templates)
        world.spacerPushes = false
        let result = SpikeFake.stage(world, plan: SpikeFake.plan(menus: [.short, .mid])).run()
        #expect(result.a.noBandAtOne)
        #expect(result.b == nil)
        #expect(result.stopQuestion == "k=1 找不到藏得住的長度，要不要繼續做 IceBar？（是／否）")
        #expect(world.presses == 0)
        #expect(world.items.isEmpty)
    }

    @Test("a placement that fails names the profile's problem and measures nothing")
    func placement() {
        let world = SpikeFakeWorld(templates: SpikeFake.templates)
        world.newestRightmost = true
        let result = SpikeFake.stage(world, plan: SpikeFake.plan(runB: false)).run()
        #expect(result.a.profiles[0].problem?.hasPrefix("placement gate") == true)
        #expect(result.a.profiles[0].records.isEmpty)
        #expect(world.items.isEmpty)
    }

    @Test("spike B: a press that opens the pushed-off member's menu is the pushed-off path, 5 of 5, each menu closed again")
    func pressedOff() {
        let world = SpikeFakeWorld(templates: SpikeFake.templates)
        let evidence = SpikeFakeEvidence()
        let result = SpikeFake.stage(world, plan: SpikeFake.plan(), evidence: evidence).run()
        let b = try! #require(result.b)
        #expect(b.length == 160)
        #expect(b.pushedOff.count == 5)
        #expect(b.pushedOff.allSatisfy { SpikeBRules.opened($0) && $0.closed && $0.signals == ["helper", "window"] && $0.pressError == 0 })
        #expect(b.fallback.isEmpty)
        #expect(SpikeBRules.path(b) == .pushedOff)
        #expect(result.stopQuestion == nil)
        #expect(result.lines[1].hasPrefix("點得開嗎：點得開。"))
        #expect(world.menuOpenPID == nil)
        #expect(world.items.isEmpty)
        #expect(world.commands.contains(SpikeHelperFlags.closeMenu))
        #expect(evidence.kinds.filter { $0 == "press" }.count == 5)
    }

    @Test("spike B: a press that only works while the member is drawn is the show-press-rehide path, re-hidden after each trial")
    func fallback() {
        let world = SpikeFakeWorld(templates: SpikeFake.templates)
        world.pressBehaviour = .onlyWhenDrawn
        let evidence = SpikeFakeEvidence()
        let result = SpikeFake.stage(world, plan: SpikeFake.plan(), evidence: evidence).run()
        let b = try! #require(result.b)
        #expect(b.pushedOff.filter(SpikeBRules.opened).isEmpty)
        #expect(b.fallback.count == 5)
        #expect(b.fallback.allSatisfy(SpikeBRules.opened))
        #expect(SpikeBRules.path(b) == .showPressRehide)
        #expect(result.stopQuestion == nil)
        #expect(evidence.log.filter { $0.hasPrefix("rehide") }.count == 5, "\(evidence.log.joined(separator: "\n"))")
        #expect(world.items.isEmpty)
    }

    @Test("spike B: a press that never opens the menu is no click path; the owner is asked")
    func never() {
        let world = SpikeFakeWorld(templates: SpikeFake.templates)
        world.pressBehaviour = .never
        let result = SpikeFake.stage(world, plan: SpikeFake.plan()).run()
        let b = try! #require(result.b)
        #expect(b.pushedOff.count == 5 && b.fallback.count == 5)
        #expect(b.pushedOff.allSatisfy { $0.openedAfter == nil && $0.signals.isEmpty })
        #expect(SpikeBRules.path(b) == .none)
        #expect(result.stopQuestion == "找不到可用的點擊方式，要不要繼續做 IceBar？（是／否）")
        #expect(world.items.isEmpty)
    }

    @Test("the member that gets a menu is spike B's only; spike A's members have none")
    func menuFlag() {
        let world = SpikeFakeWorld(templates: SpikeFake.templates)
        _ = SpikeFake.stage(world, plan: SpikeFake.plan(members: [1, 2])).run()
        #expect(world.presses == 5)
    }
}
