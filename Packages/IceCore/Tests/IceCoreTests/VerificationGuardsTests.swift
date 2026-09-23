import Testing
@testable import IceCore

/// `RoomGuard` and `BaselineReuse` are D16's two numeric gates: whether
/// there is enough free bar to capture without the indicator pushing an
/// item behind the overflow chevron, and whether a previous baseline is
/// still trustworthy enough to skip a fresh capture.
@Suite("RoomGuard.hasRoom")
struct RoomGuardTests {
    private func item(minX: Double, pid: Int32 = 1, position: ItemPosition = .onBar) -> DiscoveredItem {
        let key = ItemKey(namespace: "com.example.a", identifier: "x", pid: pid, childIndex: nil)
        return DiscoveredItem(
            key: key, basis: .declared,
            process: ProcessInfoRecord(pid: pid, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
            frame: BarRect(minX: minX, minY: 4.5, width: 20, height: 24), position: position,
            title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
        )
    }

    private func set(items: [DiscoveredItem], visibleControlItem: DiscoveredItem? = nil) -> DiscoveredItemSet {
        DiscoveredItemSet(items: items, visibleControlItem: visibleControlItem, hiddenDivider: nil, alwaysHiddenDivider: nil, ownRead: .ok, systemElements: [], dropped: [], completeness: .complete)
    }

    @Test("no items at all -> room is assumed (true)")
    func noItemsAssumesRoom() {
        #expect(RoomGuard.hasRoom(set: set(items: []), notchMaxX: 100) == true)
    }

    @Test("free room of exactly 41 pt is enough")
    func exactly41PtIsEnough() {
        let s = set(items: [item(minX: 141)]) // 141 - 100 = 41
        #expect(RoomGuard.hasRoom(set: s, notchMaxX: 100) == true)
    }

    @Test("free room of 40.9 pt is not enough")
    func justBelow41IsNotEnough() {
        let s = set(items: [item(minX: 140.9)])
        #expect(RoomGuard.hasRoom(set: s, notchMaxX: 100) == false)
    }

    @Test("own items count toward the leftmost -- the visibleControlItem is included")
    func ownItemsCountToo() {
        let ownItem = item(minX: 130, pid: 900)
        let s = set(items: [item(minX: 500)], visibleControlItem: ownItem)
        #expect(RoomGuard.hasRoom(set: s, notchMaxX: 100) == false) // 130 - 100 = 30 < 41
    }

    @Test("a parked item does not count as the leftmost -- only on-bar items do")
    func parkedItemsDoNotCount() {
        let parked = item(minX: 7, pid: 1, position: .parked)
        let onBar = item(minX: 500, pid: 2)
        let s = set(items: [parked, onBar])
        #expect(RoomGuard.hasRoom(set: s, notchMaxX: 100) == true)
    }
}

@Suite("BaselineReuse.isReusable")
struct BaselineReuseTests {
    private func key(_ n: Int32) -> ItemKey {
        ItemKey(namespace: "com.example.a", identifier: "x\(n)", pid: n, childIndex: nil)
    }

    @Test("identical baseline and fresh frames, well within age -> reusable")
    func identicalFramesAreReusable() {
        let frames: [ItemKey: BarRect] = [key(1): BarRect(minX: 100, minY: 4.5, width: 20, height: 24)]
        #expect(BaselineReuse.isReusable(baselineFrames: frames, freshFrames: frames, age: 10) == true)
    }

    @Test("a shift of exactly the tolerance (0.5 pt) is still reusable")
    func exactlyTolerancePtIsReusable() {
        let baseline: [ItemKey: BarRect] = [key(1): BarRect(minX: 100, minY: 4.5, width: 20, height: 24)]
        let fresh: [ItemKey: BarRect] = [key(1): BarRect(minX: 100.5, minY: 4.5, width: 20.5, height: 24)]
        #expect(BaselineReuse.isReusable(baselineFrames: baseline, freshFrames: fresh, age: 10) == true)
    }

    @Test("a shift of 0.51 pt is not reusable")
    func justPastTolerancePtIsNotReusable() {
        let baseline: [ItemKey: BarRect] = [key(1): BarRect(minX: 100, minY: 4.5, width: 20, height: 24)]
        let fresh: [ItemKey: BarRect] = [key(1): BarRect(minX: 100.51, minY: 4.5, width: 20, height: 24)]
        #expect(BaselineReuse.isReusable(baselineFrames: baseline, freshFrames: fresh, age: 10) == false)
    }

    @Test("a width shift of 0.51 pt is not reusable")
    func widthShiftJustPastToleranceIsNotReusable() {
        let baseline: [ItemKey: BarRect] = [key(1): BarRect(minX: 100, minY: 4.5, width: 20, height: 24)]
        let fresh: [ItemKey: BarRect] = [key(1): BarRect(minX: 100, minY: 4.5, width: 20.51, height: 24)]
        #expect(BaselineReuse.isReusable(baselineFrames: baseline, freshFrames: fresh, age: 10) == false)
    }

    @Test("age of exactly 600 s is reusable, 600.1 s is not")
    func ageBoundary() {
        let frames: [ItemKey: BarRect] = [key(1): BarRect(minX: 100, minY: 4.5, width: 20, height: 24)]
        #expect(BaselineReuse.isReusable(baselineFrames: frames, freshFrames: frames, age: 600.0) == true)
        #expect(BaselineReuse.isReusable(baselineFrames: frames, freshFrames: frames, age: 600.1) == false)
    }

    @Test("a baseline key missing from the fresh frames is not reusable")
    func missingKeyIsNotReusable() {
        let baseline: [ItemKey: BarRect] = [key(1): BarRect(minX: 100, minY: 4.5, width: 20, height: 24)]
        #expect(BaselineReuse.isReusable(baselineFrames: baseline, freshFrames: [:], age: 10) == false)
    }

    @Test("an empty baseline is trivially reusable (within age)")
    func emptyBaselineIsReusable() {
        #expect(BaselineReuse.isReusable(baselineFrames: [:], freshFrames: [:], age: 10) == true)
    }

    @Test("a fresh framed key the baseline never had is not reusable (the baseline cannot explain its ink)")
    func extraFreshKeyIsNotReusable() {
        let frame = BarRect(minX: 100, minY: 4.5, width: 20, height: 24)
        let baseline: [ItemKey: BarRect] = [key(1): frame]
        let fresh: [ItemKey: BarRect] = [key(1): frame, key(2): BarRect(minX: 60, minY: 4.5, width: 20, height: 24)]
        #expect(BaselineReuse.isReusable(baselineFrames: baseline, freshFrames: fresh, age: 10) == false)
    }
}

/// Deviation 5: a reused baseline must have been built for exactly the
/// roster the fresh plan names, or `verify` would report results for items
/// no longer in the section and none for items that joined it.
@Suite("BaselineReuse.sameRoster")
struct BaselineReuseRosterTests {
    private func key(_ n: Int32) -> ItemKey {
        ItemKey(namespace: "com.example.a", identifier: "x\(n)", pid: n, childIndex: nil)
    }

    @Test("the same targets in another order and the same per-item skips -> same roster")
    func sameTargetsAnyOrder() {
        #expect(BaselineReuse.sameRoster(
            baselineTargets: [key(1), key(2)], baselineSkipped: [key(3): .positional],
            freshTargets: [key(2), key(1)], freshSkipped: [key(3): .positional]
        ) == true)
    }

    @Test("a target that joined the section -> not the same roster")
    func targetAdded() {
        #expect(BaselineReuse.sameRoster(
            baselineTargets: [key(1)], baselineSkipped: [:],
            freshTargets: [key(1), key(2)], freshSkipped: [:]
        ) == false)
    }

    @Test("a target that left the section -> not the same roster")
    func targetRemoved() {
        #expect(BaselineReuse.sameRoster(
            baselineTargets: [key(1), key(2)], baselineSkipped: [:],
            freshTargets: [key(1)], freshSkipped: [:]
        ) == false)
    }

    @Test("a per-item skip that changed (stacked -> positional, or a new one) -> not the same roster")
    func skipChanged() {
        #expect(BaselineReuse.sameRoster(
            baselineTargets: [key(1)], baselineSkipped: [key(3): .stacked],
            freshTargets: [key(1)], freshSkipped: [key(3): .positional]
        ) == false)
        #expect(BaselineReuse.sameRoster(
            baselineTargets: [key(1)], baselineSkipped: [:],
            freshTargets: [key(1)], freshSkipped: [key(3): .stacked]
        ) == false)
    }
}
