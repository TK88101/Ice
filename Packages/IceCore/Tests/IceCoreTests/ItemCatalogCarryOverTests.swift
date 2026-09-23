import Testing
@testable import IceCore

/// `ItemCatalog.carryOver` keeps a failed pid's last-known items on screen
/// for as long as that process keeps failing to read, bounded by real
/// elapsed time rather than a pass count (plan section 4.1.5, "carry-over";
/// risk table, "a hung app"; contract amendments adopted 2026-09-23: round 1
/// dropped the original "≤ 3 passes" cap so a hung app's items would not
/// vanish on a timer while the app itself never quit, round 2 replaced the
/// now-unbounded carry with a `freshness`-seconds time bound so a process
/// that fails forever cannot leave ghost items on screen forever).
/// `carriedPasses` is kept only as a diagnostic counter. An item is removed
/// only when its process is read successfully and the item is absent from
/// that read, when the process's identity (`bundleID`/`launchTime`) changed
/// (a pid reuse), or when it has gone stale.
@Suite("ItemCatalog.carryOver")
struct ItemCatalogCarryOverTests {
    private func item(pid: Int32, identifier: String = "gear", carriedPasses: Int = 0, isSelf: Bool = false, bundleID: String = "com.example.a", launchTime: Double? = 10, minX: Double = 100, lastConfirmedAt: Double = 0) -> DiscoveredItem {
        let key = ItemKey(namespace: bundleID, identifier: identifier, pid: pid, childIndex: nil)
        return DiscoveredItem(
            key: key, basis: .declared,
            process: ProcessInfoRecord(pid: pid, bundleID: bundleID, localizedName: nil, executableName: nil, launchTime: launchTime, isSelf: isSelf),
            frame: BarRect(minX: minX, minY: 4.5, width: 20, height: 24), position: .onBar,
            title: nil, description: nil, help: nil, carriedPasses: carriedPasses, lastConfirmedAt: lastConfirmedAt
        )
    }

    private func set(items: [DiscoveredItem], failedPIDs: [Int32], staleProcesses: [Int32: ProcessInfoRecord] = [:], dropped: [DroppedItem] = []) -> DiscoveredItemSet {
        DiscoveredItemSet(
            items: items, visibleControlItem: nil, hiddenDivider: nil, alwaysHiddenDivider: nil,
            ownRead: .ok, systemElements: [], dropped: dropped, staleProcesses: staleProcesses,
            completeness: failedPIDs.isEmpty ? .complete : .incomplete(failedPIDs: failedPIDs)
        )
    }

    @Test("previous nil -> current returned untouched")
    func noPreviousReturnsCurrent() {
        let current = set(items: [], failedPIDs: [])
        let result = ItemCatalog.carryOver(previous: nil, current: current, now: 100)
        #expect(result == current)
    }

    @Test("current complete -> nothing to carry, current returned untouched")
    func completeCurrentReturnsUntouched() {
        let previous = set(items: [item(pid: 5)], failedPIDs: [])
        let current = set(items: [], failedPIDs: [])
        let result = ItemCatalog.carryOver(previous: previous, current: current, now: 100)
        #expect(result == current)
    }

    @Test("a previous item of a failed pid, unchanged process, within freshness, is carried with carriedPasses + 1 and an unchanged lastConfirmedAt")
    func unchangedProcessWithinFreshnessIsCarried() {
        let previousItem = item(pid: 5, carriedPasses: 0, lastConfirmedAt: 0)
        let previous = set(items: [previousItem], failedPIDs: [])
        let current = set(items: [], failedPIDs: [5], staleProcesses: [5: previousItem.process])
        let result = ItemCatalog.carryOver(previous: previous, current: current, now: 10)
        #expect(result.items.count == 1)
        #expect(result.items.first?.carriedPasses == 1)
        #expect(result.items.first?.lastConfirmedAt == 0)
        #expect(result.items.first?.key == previousItem.key)
    }

    @Test("a deadline-truncated pass (extrasError \"notAttempted\") still fails the read and keeps the previous item")
    func deadlineTruncatedPassKeepsPreviousItem() {
        let previousItem = item(pid: 5, lastConfirmedAt: 0)
        let previous = set(items: [previousItem], failedPIDs: [])
        let notAttempted = RawRead(process: previousItem.process, extrasError: "notAttempted", extrasElapsed: 0, childrenError: nil, childrenElapsed: nil, records: [])
        #expect(ReadClassifier.outcome(notAttempted) == .failed(.unexpectedError(call: "extrasBar", error: "notAttempted")))

        let built = ItemCatalog.build(reads: [notAttempted], agentPID: nil, bounds: BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33), isTrusted: true, ownIdentifiers: OwnIdentifiers(visible: "v", hidden: "h", alwaysHidden: "a"), now: 10)
        #expect(built.completeness == .incomplete(failedPIDs: [5]))

        let current = set(items: [], failedPIDs: [5], staleProcesses: [5: previousItem.process])
        let result = ItemCatalog.carryOver(previous: previous, current: current, now: 10)
        #expect(result.items.count == 1)
    }

    @Test("carried exactly at the freshness bound (30.0 s elapsed)")
    func carriedExactlyAtFreshnessBound() {
        let previousItem = item(pid: 5, lastConfirmedAt: 0)
        let previous = set(items: [previousItem], failedPIDs: [])
        let current = set(items: [], failedPIDs: [5], staleProcesses: [5: previousItem.process])
        let result = ItemCatalog.carryOver(previous: previous, current: current, now: 30.0, freshness: 30)
        #expect(result.items.count == 1)
    }

    @Test("dropped(.stale) just past the freshness bound (30.1 s elapsed)")
    func droppedJustPastFreshnessBound() {
        let previousItem = item(pid: 5, lastConfirmedAt: 0)
        let previous = set(items: [previousItem], failedPIDs: [])
        let current = set(items: [], failedPIDs: [5], staleProcesses: [5: previousItem.process])
        let result = ItemCatalog.carryOver(previous: previous, current: current, now: 30.1, freshness: 30)
        #expect(result.items.isEmpty)
        #expect(result.dropped.contains(DroppedItem(key: previousItem.key, pid: 5, reason: .stale)))
    }

    @Test("ten consecutive failed passes within the freshness window still carry, lastConfirmedAt never advancing")
    func tenConsecutiveFailedPassesWithinFreshnessStillCarry() {
        var previous: DiscoveredItemSet? = set(items: [item(pid: 5, carriedPasses: 0, lastConfirmedAt: 0)], failedPIDs: [])
        let staleProcess = item(pid: 5).process

        var now = 0.0
        for pass in 1...10 {
            now = Double(pass) * 2 // ten passes, 2 s apart -- 20 s total, within the default 30 s freshness bound
            let current = set(items: [], failedPIDs: [5], staleProcesses: [5: staleProcess])
            previous = ItemCatalog.carryOver(previous: previous, current: current, now: now)
        }

        #expect(previous?.items.count == 1)
        #expect(previous?.items.first?.carriedPasses == 10)
        #expect(previous?.items.first?.lastConfirmedAt == 0)
    }

    @Test("a successful read for the pid that no longer includes the item drops it (not carried)")
    func successfulReadWithoutTheItemDropsIt() {
        let previousItem = item(pid: 5)
        let previous = set(items: [previousItem], failedPIDs: [])
        // pid 5 is not in failedPIDs this pass -- it was read successfully,
        // and current.items already reflects that fresh (empty) result, so
        // carryOver must not touch it at all.
        let current = set(items: [], failedPIDs: [])
        let result = ItemCatalog.carryOver(previous: previous, current: current, now: 5)
        #expect(result.items.isEmpty)
    }

    @Test("pid reuse: a fresh ProcessInfoRecord with a different launchTime for the failed pid stops the carry")
    func pidReuseWithChangedLaunchTimeIsNotCarried() {
        let previousItem = item(pid: 5, bundleID: "com.example.a", launchTime: 10)
        let previous = set(items: [previousItem], failedPIDs: [])
        let reused = ProcessInfoRecord(pid: 5, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 999, isSelf: false)
        let current = set(items: [], failedPIDs: [5], staleProcesses: [5: reused])
        let result = ItemCatalog.carryOver(previous: previous, current: current, now: 5)
        #expect(result.items.isEmpty)
    }

    @Test("pid reuse: a fresh ProcessInfoRecord with a different bundleID for the failed pid stops the carry")
    func pidReuseWithChangedBundleIDIsNotCarried() {
        let previousItem = item(pid: 5, bundleID: "com.example.a", launchTime: 10)
        let previous = set(items: [previousItem], failedPIDs: [])
        let reused = ProcessInfoRecord(pid: 5, bundleID: "com.example.b", localizedName: nil, executableName: nil, launchTime: 10, isSelf: false)
        let current = set(items: [], failedPIDs: [5], staleProcesses: [5: reused])
        let result = ItemCatalog.carryOver(previous: previous, current: current, now: 5)
        #expect(result.items.isEmpty)
    }

    @Test("no fresh process info available for the failed pid -> unchanged is assumed, item is carried")
    func noFreshInfoStillCarries() {
        let previousItem = item(pid: 5, lastConfirmedAt: 0)
        let previous = set(items: [previousItem], failedPIDs: [])
        let current = set(items: [], failedPIDs: [5], staleProcesses: [:])
        let result = ItemCatalog.carryOver(previous: previous, current: current, now: 5)
        #expect(result.items.count == 1)
    }

    @Test("own items are never carried, even if the own pid is in failedPIDs")
    func ownItemsAreNeverCarried() {
        let ownItem = item(pid: 900, isSelf: true)
        let previous = set(items: [ownItem], failedPIDs: [])
        let current = set(items: [], failedPIDs: [900], staleProcesses: [900: ownItem.process])
        let result = ItemCatalog.carryOver(previous: previous, current: current, now: 5)
        #expect(result.items.isEmpty)
    }

    @Test("a collision introduced by carrying (forced fixture) drops both colliding items")
    func collisionAfterCarryDropsBoth() {
        // Force the scenario directly: a carried item and a freshly-read
        // current item share the exact same tagKey. This should not arise
        // from real AX data (a third-party tagTitle always embeds its pid),
        // but carryOver must still detect and drop it rather than publish a
        // duplicate.
        let sharedKey = ItemKey(namespace: "com.example.a", identifier: "gear", pid: 5, childIndex: nil)
        let carriedCandidate = DiscoveredItem(
            key: sharedKey, basis: .declared,
            process: ProcessInfoRecord(pid: 5, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
            frame: BarRect(minX: 100, minY: 4.5, width: 20, height: 24), position: .onBar,
            title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
        )
        let currentItemSameTag = DiscoveredItem(
            key: sharedKey, basis: .declared,
            process: ProcessInfoRecord(pid: 5, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
            frame: BarRect(minX: 400, minY: 4.5, width: 20, height: 24), position: .onBar,
            title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 5
        )
        let previous = set(items: [carriedCandidate], failedPIDs: [])
        // pid 5 is in failedPIDs here purely to exercise the carry path;
        // currentItemSameTag stands in for an item that happens (by forced
        // fixture) to collide on tag with what gets carried.
        let current = set(items: [currentItemSameTag], failedPIDs: [5], staleProcesses: [5: carriedCandidate.process])
        let result = ItemCatalog.carryOver(previous: previous, current: current, now: 5)
        #expect(result.items.isEmpty)
        #expect(result.dropped.contains { $0.reason == .identityCollision })
    }

    @Test("items are re-sorted by frame minX after carrying")
    func itemsAreResortedAfterCarry() {
        let carriedFarRight = item(pid: 5, minX: 900)
        let currentNearLeft = item(pid: 6, identifier: "left", minX: 50)
        let previous = set(items: [carriedFarRight], failedPIDs: [])
        let current = set(items: [currentNearLeft], failedPIDs: [5], staleProcesses: [5: carriedFarRight.process])
        let result = ItemCatalog.carryOver(previous: previous, current: current, now: 5)
        #expect(result.items.map(\.key.pid) == [6, 5])
    }
}
