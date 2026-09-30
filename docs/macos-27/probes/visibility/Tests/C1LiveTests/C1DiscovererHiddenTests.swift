import IceCore
import MenuBarDiscovery
import Testing
@testable import C1Live

/// C2 T3 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 2): the discoverer
/// accepts exactly the k hidden items left of the divider.
@Suite("C1DiscovererHidden")
struct C1DiscovererHiddenTests {
    func item(_ id: String, _ pid: Int32, _ x: Double, position: ItemPosition = .onBar) -> DiscoveredItem {
        fixtureItem(identifier: id, pid: pid, minX: x, position: position)
    }
    func target(_ x: Double) -> DiscoveredItem { item("vz-target", 10, x) }
    func hidden2(_ x: Double, position: ItemPosition = .onBar) -> DiscoveredItem { item("vz-hidden-2", 13, x, position: position) }
    func hidden3(_ x: Double) -> DiscoveredItem { item("vz-hidden-3", 14, x) }
    func spacer(_ x: Double) -> DiscoveredItem { item("vz-spacer", 11, x) }
    func protected(_ x: Double) -> DiscoveredItem { item("vz-protected", 12, x) }

    func discoverer(_ items: [DiscoveredItem]) -> C1Discoverer {
        C1Discoverer(
            base: FakeDiscoverer(results: [fixtureDiscovery(set: fixtureSet(items: items))]),
            targetKey: target(0).key, spacerKey: spacer(0).key, protectedKey: protected(0).key,
            extraHiddenKeys: [hidden2(0).key, hidden3(0).key]
        )
    }

    @Test("Target and both extra hidden items left of the spacer -> accepted")
    func accepted() async {
        let result = await discoverer([target(10), hidden2(40), hidden3(70), spacer(100), protected(130)]).discover(previous: nil)
        #expect(result?.set.hiddenDivider?.frame?.minX == 100)
    }

    @Test("an extra hidden item right of the divider -> rejected")
    func extraRightOfDivider() async {
        let result = await discoverer([target(10), hidden2(40), spacer(100), hidden3(110), protected(130)]).discover(previous: nil)
        #expect(result == nil)
    }

    @Test("an extra hidden item missing or parked -> rejected")
    func extraMissingOrParked() async {
        #expect(await discoverer([target(10), hidden3(70), spacer(100), protected(130)]).discover(previous: nil) == nil)
        #expect(await discoverer([target(10), hidden2(40, position: .parked), hidden3(70), spacer(100), protected(130)]).discover(previous: nil) == nil)
    }

    @Test("an owner item among the hidden section -> rejected")
    func ownerAmongHidden() async {
        let result = await discoverer([target(10), item("owner", 20, 30), hidden2(40), hidden3(70), spacer(100), protected(130)]).discover(previous: nil)
        #expect(result == nil)
    }
}
