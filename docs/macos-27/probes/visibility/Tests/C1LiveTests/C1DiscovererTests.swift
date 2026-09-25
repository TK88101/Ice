import IceCore
import MenuBarDiscovery
import Testing
@testable import C1Live

/// I4 (section 2's last paragraph): the spacer's real rest `minX` is the
/// divider; Target is the only section item; Protected is supplied
/// explicitly as the reference; the discoverer rejects the read unless
/// Target is the sole item left of the divider and Protected lies right of
/// it; the spacer is carried as an observed item.
@Suite("C1Discoverer")
struct C1DiscovererTests {
    func target(_ x: Double) -> DiscoveredItem { fixtureItem(identifier: "vz-target", pid: 10, minX: x) }
    func spacer(_ x: Double) -> DiscoveredItem { fixtureItem(identifier: "vz-spacer", pid: 11, minX: x) }
    func protected(_ x: Double) -> DiscoveredItem { fixtureItem(identifier: "vz-protected", pid: 12, minX: x) }
    func owner(_ id: String, _ x: Double, pid: Int32 = 20) -> DiscoveredItem { fixtureItem(identifier: id, pid: pid, minX: x) }

    // Real keys, not hand-built ones: `fixtureItem`'s namespace is derived
    // from the pid ("com.example.p<pid>"), so the keys this discoverer
    // matches against must come from the same fixture, not a hand-rolled
    // `ItemKey` that would never equal what `fixtureItem` actually produces.
    var targetKey: ItemKey { target(0).key }
    var spacerKey: ItemKey { spacer(0).key }
    var protectedKey: ItemKey { protected(0).key }

    func discoverer(_ results: [DiscoveryResult?]) -> C1Discoverer {
        C1Discoverer(base: FakeDiscoverer(results: results), targetKey: targetKey, spacerKey: spacerKey, protectedKey: protectedKey)
    }

    @Test("Target alone left of the spacer, Protected right of it -> accepted, divider at the spacer's minX")
    func accepted() async {
        let items = [target(10), spacer(30), protected(50)]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result?.set.hiddenDivider?.frame?.minX == 30)
        #expect(result?.set.hiddenDivider?.isUsable == true)
    }

    @Test("the spacer is carried as an observed item, not removed from the roster")
    func spacerStaysObserved() async {
        let items = [target(10), spacer(30), protected(50)]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result?.set.items.contains { $0.key == spacerKey } == true)
    }

    @Test("an owner item left of Target, so Target is not alone left of the divider -> rejected")
    func targetNotAloneOnLeft() async {
        let items = [owner("owner-1", 5), target(10), spacer(30), protected(50)]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result == nil)
    }

    @Test("Protected left of the divider instead of right -> rejected")
    func protectedOnTheLeft() async {
        let items = [target(10), protected(20), spacer(30)]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result == nil)
    }

    @Test("Target missing entirely -> rejected")
    func targetMissing() async {
        let items = [spacer(30), protected(50)]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result == nil)
    }

    @Test("Protected missing entirely -> rejected")
    func protectedMissing() async {
        let items = [target(10), spacer(30)]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result == nil)
    }

    @Test("the spacer missing entirely -> rejected (no minX to make a divider from)")
    func spacerMissing() async {
        let items = [target(10), protected(50)]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result == nil)
    }

    @Test("the base discoverer producing no result at all -> nil, unchanged")
    func baseProducesNothing() async {
        let discovery = discoverer([nil])
        let result = await discovery.discover(previous: nil)
        #expect(result == nil)
    }
}
