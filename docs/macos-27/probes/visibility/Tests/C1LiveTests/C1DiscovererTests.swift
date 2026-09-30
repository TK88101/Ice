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
    func parked(_ id: String, _ x: Double, pid: Int32 = 30) -> DiscoveredItem { fixtureItem(identifier: id, pid: pid, minX: x, position: .parked) }

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

    // MARK: - Amendment v8 (parked items)

    /// Amendment v8's first bullet: "items the catalogue classifies as
    /// parked ... are not owner items: out of the divider count" -- the
    /// owner's own bar always lists 2-3 of them (frames below the bar,
    /// minX 7/-1), always left of the spacer's own minX in the status
    /// area, which made `discover` reject every real composed set before
    /// this fix (crosscheck-rework7.json finding #0).
    @Test("Target alone left of the spacer, two parked items also left of it -> still accepted")
    func parkedItemsLeftOfDividerStillAccepted() async {
        let items = [target(10), spacer(30), protected(50), parked("parked-1", 7), parked("parked-2", -1, pid: 31)]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result?.set.hiddenDivider?.frame?.minX == 30)
        #expect(result?.set.hiddenDivider?.isUsable == true)
    }

    /// A parked item is not removed from the roster either (only excluded
    /// from the divider count) -- it stays an observed item, same as the
    /// spacer.
    @Test("a parked item stays in the composed roster, not removed")
    func parkedItemStaysObserved() async {
        let items = [target(10), spacer(30), protected(50), parked("parked-1", 7)]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result?.set.items.contains { $0.key == parked("parked-1", 7).key } == true)
    }

    /// A second, genuinely on-bar item left of Target must still reject --
    /// the parked exclusion must not swallow a real obstruction.
    @Test("an on-bar owner item left of Target, alongside a parked one -> still rejected")
    func onBarOwnerStillRejectedAlongsideParked() async {
        let items = [owner("owner-1", 5), target(10), spacer(30), protected(50), parked("parked-1", 7)]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result == nil)
    }

    @Test("a parked Target -> rejected (a parked item cannot anchor the section)")
    func parkedTargetRejected() async {
        let items = [
            DiscoveredItem(
                key: targetKey, basis: .declared,
                process: ProcessInfoRecord(pid: targetKey.pid, bundleID: targetKey.namespace, localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
                frame: BarRect(minX: 10, minY: 0, width: 9, height: 12), position: .parked,
                title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
            ),
            spacer(30), protected(50),
        ]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result == nil)
    }

    @Test("a parked spacer -> rejected (no usable divider from a parked frame)")
    func parkedSpacerRejected() async {
        let items = [
            target(10),
            DiscoveredItem(
                key: spacerKey, basis: .declared,
                process: ProcessInfoRecord(pid: spacerKey.pid, bundleID: spacerKey.namespace, localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
                frame: BarRect(minX: 30, minY: 0, width: 9, height: 12), position: .parked,
                title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
            ),
            protected(50),
        ]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result == nil)
    }

    @Test("a parked Protected -> rejected")
    func parkedProtectedRejected() async {
        let items = [
            target(10), spacer(30),
            DiscoveredItem(
                key: protectedKey, basis: .declared,
                process: ProcessInfoRecord(pid: protectedKey.pid, bundleID: protectedKey.namespace, localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
                frame: BarRect(minX: 50, minY: 0, width: 9, height: 12), position: .parked,
                title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
            ),
        ]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items))])
        let result = await discovery.discover(previous: nil)
        #expect(result == nil)
    }

    // MARK: - G1 (Amendment v7)

    /// G1: the live raw discoverer (`MenuBarDiscoverer` over
    /// `HarnessProcesses`, `Sources/vizprobe/StageC1Live.swift`) never
    /// reads `ownRead: .ok` -- `HarnessProcesses` drops this process's own
    /// `isSelf` read before `ItemCatalog.build` ever sees it
    /// (`vizprobe/StageRun.swift:32`), so `ownRead` stays at its initial
    /// `.notRead` (`Packages/IceCore/Sources/IceCore/ItemCatalog.swift:86`).
    /// This discoverer supplies its own divider from the spacer's `minX`
    /// (I4/section 2), so the harness's own (self-filtered, always
    /// negative) own-process read is irrelevant to whether the composed
    /// set can be checked at all -- it must compose `ownRead: .ok`, not
    /// forward the base's `.notRead` unchanged.
    ///
    /// Today's `C1Discoverer.discover` (`Sources/C1Live/C1Discoverer.swift:57`)
    /// does forward it unchanged, so `CheckPlan.make`
    /// (`Packages/IceCore/Sources/IceCore/CheckPlan.swift:25`, whose own
    /// first guard is `set.ownRead == .ok`) returns
    /// `.skip(.dividerUnavailable)` here, not `.observe` -- expected RED,
    /// the one C1LiveTests case rework #7a's brief asks for. The fix
    /// (`ownRead: .ok` in the composed set) is a one-line source change
    /// left to the next worker.
    @Test("G1: a base set with ownRead .notRead (the harness self-filtering) still composes a usable divider, and the composed set must pass CheckPlan.make as .observe")
    func ownReadNotReadStillPassesCheckPlan() async {
        let items = [target(10), spacer(30), protected(50)]
        let discovery = discoverer([fixtureDiscovery(set: fixtureSet(items: items, ownRead: .notRead))])
        let result = await discovery.discover(previous: nil)

        guard let composed = result?.set else {
            Issue.record("expected the composition to succeed (Target alone left of the spacer, Protected right of it) regardless of ownRead")
            return
        }
        #expect(composed.hiddenDivider?.isUsable == true)

        let plan = CheckPlan.make(sections: [.hidden], set: composed, sectionMap: [:], explicitCandidates: nil)
        switch plan {
        case .observe:
            break
        case .skip(let reason):
            Issue.record("G1: expected .observe, got .skip(\(reason)) -- C1Discoverer must compose ownRead: .ok (it supplies its own divider) instead of forwarding the raw harness's .notRead")
        }
    }
}
