import Testing
@testable import IceCore

/// `ItemCatalog.build` is the single place that turns raw per-process reads
/// into a `DiscoveredItemSet` (plan section 4.1.5, task T4 API). Every rule
/// tested here matters because getting any one wrong either loses real items
/// (own records misrouted, a stray extra turning a real item positional) or
/// invents fake ones (an agent frame counted as a status item, a dropped
/// record surviving into `items`).
@Suite("ItemCatalog.build: trust and ordering")
struct ItemCatalogBuildTrustAndOrderingTests {
    let bounds = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)
    let ownIDs = OwnIdentifiers(visible: "Ice.ControlItem.visible", hidden: "Ice.ControlItem.hidden", alwaysHidden: "Ice.ControlItem.alwaysHidden")

    @Test("untrusted -> permissionDenied, nothing read")
    func untrustedIsPermissionDenied() {
        let set = ItemCatalog.build(reads: [], agentPID: nil, bounds: bounds, isTrusted: false, ownIdentifiers: ownIDs, now: 0)
        #expect(set.completeness == .permissionDenied)
        #expect(set.items.isEmpty)
    }

    @Test("complete-but-empty publishes an empty set, not a failure")
    func completeButEmpty() {
        let set = ItemCatalog.build(reads: [], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.completeness == .complete)
        #expect(set.items.isEmpty)
        #expect(set.ownRead == .notRead)
    }

    @Test("items are ordered by frame minX, then pid, then childIndex; no-frame items last")
    func orderingByMinXThenPidThenChildIndex() {
        let reads = [
            thirdParty(pid: 10, identifier: "z", minX: 500),
            thirdParty(pid: 11, identifier: "a", minX: 100),
            thirdParty(pid: 12, identifier: "none", minX: 0, hasFrame: false),
            thirdParty(pid: 5, identifier: "same-x-later-pid", minX: 100),
        ]
        let set = ItemCatalog.build(reads: reads, agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        // Two items share minX 100 (pid 11 and pid 5) -- pid 5 sorts first;
        // pid 10 at minX 500 comes after both; the no-frame item is last.
        #expect(set.items.map(\.key.pid) == [5, 11, 10, 12])
    }

    @Test("when minX and pid both tie, childIndex breaks it (two positional records at the same frame minX)")
    func orderingTieBreaksOnChildIndex() {
        let recordA = ExtrasRecord(childIndex: 1, role: ok("AXMenuBarItem"), identifier: ok("shared"), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 300, minY: 4.5, width: 14, height: 24)))
        let recordB = ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: ok("shared"), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 300, minY: 4.5, width: 14, height: 24)))
        // Both records share minX 300 and pid 7; only childIndex (0 before
        // 1) differs, so it alone must decide the order.
        let read = RawRead(process: process(pid: 7), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: [recordA, recordB])
        let set = ItemCatalog.build(reads: [read], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.items.count == 2)
        #expect(set.items.map(\.key.childIndex) == [0, 1])
    }

    @Test("agent pid's items become frames-only systemElements, never listed status items")
    func agentItemsBecomeSystemElements() {
        let agentRecords = [
            ExtrasRecord(childIndex: 0, role: ok("AXGroup"), identifier: ok(), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 1438, minY: 0, width: 26, height: 33))),
            ExtrasRecord(childIndex: 1, role: ok("AXHostingView"), identifier: ok(), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 1480, minY: 0, width: 22, height: 33))),
        ]
        let agentRead = RawRead(process: process(pid: 999), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: agentRecords)
        let set = ItemCatalog.build(reads: [agentRead], agentPID: 999, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.items.isEmpty)
        #expect(Set(set.systemElements) == Set([BarRect(minX: 1438, minY: 0, width: 26, height: 33), BarRect(minX: 1480, minY: 0, width: 22, height: 33)]))
    }

    @Test("any failed read (own or third-party) makes the pass incomplete, naming every failed pid")
    func anyFailedReadIsIncomplete() {
        let ok1 = thirdParty(pid: 1, identifier: "a", minX: 100)
        let failing = RawRead(process: process(pid: 2), extrasError: "cannotComplete", extrasElapsed: 0.24, childrenError: nil, childrenElapsed: nil, records: [])
        let set = ItemCatalog.build(reads: [ok1, failing], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.completeness == .incomplete(failedPIDs: [2]))
        #expect(set.items.map(\.key.pid) == [1])
    }

    @Test("no failed reads at all -> complete")
    func noFailuresIsComplete() {
        let set = ItemCatalog.build(reads: [thirdParty(pid: 1, identifier: "a", minX: 100)], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.completeness == .complete)
    }
}

@Suite("ItemCatalog.build: own process")
struct ItemCatalogBuildOwnProcessTests {
    let bounds = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)
    let ownIDs = OwnIdentifiers(visible: "Ice.ControlItem.visible", hidden: "Ice.ControlItem.hidden", alwaysHidden: "Ice.ControlItem.alwaysHidden")

    @Test("own records matching each identifier take their role; the visible one is keyed identifier-only")
    func ownRecordsTakeTheirRoles() {
        let visibleFrame = BarRect(minX: 1600, minY: 4.5, width: 20, height: 24)
        let hiddenFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let alwaysHiddenFrame = BarRect(minX: 900, minY: 0, width: 16, height: 33)
        let records = [
            ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: ok("Ice.ControlItem.visible"), title: ok(), description: ok(), help: ok(), frame: okFrame(visibleFrame)),
            ExtrasRecord(childIndex: 1, role: ok("AXMenuBarItem"), identifier: ok("Ice.ControlItem.hidden"), title: ok(), description: ok(), help: ok(), frame: okFrame(hiddenFrame)),
            ExtrasRecord(childIndex: 2, role: ok("AXMenuBarItem"), identifier: ok("Ice.ControlItem.alwaysHidden"), title: ok(), description: ok(), help: ok(), frame: okFrame(alwaysHiddenFrame)),
        ]
        let own = RawRead(process: process(pid: 900, isSelf: true), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: records)
        let set = ItemCatalog.build(reads: [own], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)

        #expect(set.ownRead == .ok)
        #expect(set.visibleControlItem?.tagKey == TagKey(namespace: "com.example.a", title: "Ice.ControlItem.visible"))
        #expect(set.visibleControlItem?.frame == visibleFrame)
        #expect(set.hiddenDivider?.frame == hiddenFrame)
        #expect(set.hiddenDivider?.isUsable == true)
        #expect(set.alwaysHiddenDivider?.frame == alwaysHiddenFrame)
        #expect(set.items.isEmpty) // own records never land in `items`
    }

    @Test("an own record matching none of the three identifiers is dropped(.ownUnrecognized)")
    func ownUnrecognizedRecordIsDropped() {
        let records = [
            ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: ok("Ice.ControlItem.hidden"), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 1100, minY: 0, width: 16, height: 33))),
            ExtrasRecord(childIndex: 1, role: ok("AXMenuBarItem"), identifier: ok("something-else"), title: ok(), description: ok(), help: ok(), frame: okFrame()),
        ]
        let own = RawRead(process: process(pid: 900, isSelf: true), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: records)
        let set = ItemCatalog.build(reads: [own], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.dropped.contains(DroppedItem(key: nil, pid: 900, reason: .ownUnrecognized)))
    }

    @Test("own read outcome .failed -> ownRead .failed, and the pid is in failedPIDs")
    func ownReadFailed() {
        let own = RawRead(process: process(pid: 900, isSelf: true), extrasError: "cannotComplete", extrasElapsed: 0.24, childrenError: nil, childrenElapsed: nil, records: [])
        let set = ItemCatalog.build(reads: [own], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.ownRead == .failed)
        #expect(set.completeness == .incomplete(failedPIDs: [900]))
    }

    @Test("own read ok but the hidden divider identifier absent -> identifiersMissing")
    func ownReadOkButHiddenIdentifierMissing() {
        let records = [
            ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: ok("Ice.ControlItem.visible"), title: ok(), description: ok(), help: ok(), frame: okFrame()),
        ]
        let own = RawRead(process: process(pid: 900, isSelf: true), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: records)
        let set = ItemCatalog.build(reads: [own], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.ownRead == .identifiersMissing)
        #expect(set.hiddenDivider == nil)
    }

    @Test("own process absent from reads entirely -> notRead")
    func ownProcessAbsentIsNotRead() {
        let set = ItemCatalog.build(reads: [thirdParty(pid: 1, identifier: "a", minX: 100)], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.ownRead == .notRead)
        #expect(set.hiddenDivider == nil)
        #expect(set.visibleControlItem == nil)
    }
}

@Suite("ItemCatalog.build: third-party keying, roles, and position")
struct ItemCatalogBuildThirdPartyTests {
    let bounds = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)
    let ownIDs = OwnIdentifiers(visible: "Ice.ControlItem.visible", hidden: "Ice.ControlItem.hidden", alwaysHidden: "Ice.ControlItem.alwaysHidden")

    @Test("a non-AXMenuBarItem extra is dropped(.unrecognizedRole) and never reaches keying")
    func nonMenuBarItemRoleIsDroppedBeforeKeying() {
        let records = [
            ExtrasRecord(childIndex: 0, role: ok("AXStaticText"), identifier: ok(), title: ok(), description: ok(), help: ok(), frame: okFrame()),
        ]
        let read = RawRead(process: process(pid: 5), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: records)
        let set = ItemCatalog.build(reads: [read], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.items.isEmpty)
        #expect(set.dropped.contains(DroppedItem(key: nil, pid: 5, reason: .unrecognizedRole("AXStaticText"))))
    }

    @Test("a wrong-role extra sharing an identifier with a real item does not make the real item positional")
    func unrecognizedRoleDoesNotPoisonKeying() {
        // Both records declare identifier "gear" -- if the wrong-role one were
        // handed to ItemKeying, "gear" would count twice and the real item
        // would key .positional. Filtering it out first must prevent that.
        let records = [
            ExtrasRecord(childIndex: 0, role: ok("AXStaticText"), identifier: ok("gear"), title: ok(), description: ok(), help: ok(), frame: okFrame()),
            ExtrasRecord(childIndex: 1, role: ok("AXMenuBarItem"), identifier: ok("gear"), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 200, minY: 4.5, width: 20, height: 24))),
        ]
        let read = RawRead(process: process(pid: 5), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: records)
        let set = ItemCatalog.build(reads: [read], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.items.count == 1)
        #expect(set.items.first?.basis == .declared)
        #expect(set.items.first?.key.childIndex == nil)
    }

    @Test("obstacles for PositionRule are other on-bar third-party frames and system elements, never own items")
    func obstaclesExcludeOwnItems() {
        let ownVisible = ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: ok("Ice.ControlItem.visible"), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 995, minY: 0, width: 30, height: 33)))
        let ownRead = RawRead(process: process(pid: 900, isSelf: true), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: [ownVisible])
        // This third-party item sits under the own item's frame; because own
        // items must never be obstacles, it must read onBar, not stacked.
        let third = thirdParty(pid: 5, identifier: "gear", minX: 1000, width: 20)
        let set = ItemCatalog.build(reads: [ownRead, third], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.items.first?.position == .onBar)
    }

    @Test("a third-party item stacked under another third-party item's frame reads .stacked")
    func thirdPartyItemsCanStackEachOther() {
        let a = thirdParty(pid: 1, identifier: "a", minX: 1008, width: 14)
        let chevronLike = thirdParty(pid: 2, identifier: "b", minX: 1012.5, width: 17.5)
        let set = ItemCatalog.build(reads: [a, chevronLike], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        let itemA = set.items.first { $0.key.pid == 1 }
        #expect(itemA?.position == .stacked)
    }

    @Test("system element frames count as obstacles too")
    func systemElementFramesAreObstacles() {
        let agentRecords = [ExtrasRecord(childIndex: 0, role: ok("AXGroup"), identifier: ok(), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 1438, minY: 0, width: 26, height: 33)))]
        let agentRead = RawRead(process: process(pid: 999), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: agentRecords)
        let third = thirdParty(pid: 5, identifier: "gear", minX: 1440, width: 20)
        let set = ItemCatalog.build(reads: [agentRead, third], agentPID: 999, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.items.first?.position == .stacked)
    }

    @Test("a parked item is not counted as an obstacle for anyone else")
    func parkedItemsAreNotObstacles() {
        let parked = thirdParty(pid: 1, identifier: "parked", minX: 7, minY: 1105, width: 24)
        let onBar = thirdParty(pid: 2, identifier: "onbar", minX: 7, width: 24)
        let set = ItemCatalog.build(reads: [parked, onBar], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        let parkedItem = set.items.first { $0.key.pid == 1 }
        let onBarItem = set.items.first { $0.key.pid == 2 }
        #expect(parkedItem?.position == .parked)
        #expect(onBarItem?.position == .onBar)
    }

    @Test("a process with no extras (ReadOutcome.none) contributes nothing and is not a failure")
    func noExtrasContributesNothing() {
        let read = RawRead(process: process(pid: 5), extrasError: "noValue", extrasElapsed: 0.01, childrenError: nil, childrenElapsed: nil, records: [])
        let set = ItemCatalog.build(reads: [read], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.items.isEmpty)
        #expect(set.completeness == .complete)
    }
}

@Suite("ItemCatalog.build: collision handling")
struct ItemCatalogBuildCollisionTests {
    let bounds = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)
    let ownIDs = OwnIdentifiers(visible: "Ice.ControlItem.visible", hidden: "Ice.ControlItem.hidden", alwaysHidden: "Ice.ControlItem.alwaysHidden")

    @Test("two records sharing an identifier in one process key .positional (distinct childIndex), never .identityCollision")
    func equalIdentifiersInOneProcessArePositionalNotCollided() {
        // A third-party tagTitle always embeds its pid, so two *different*
        // pids sharing a namespace and identifier never collide (pid differs
        // -> tagTitle differs). Within a single process, T2's ItemKeying
        // already turns equal identifiers into .positional, distinguished by
        // childIndex -- this pins that ItemCatalog.build does not further
        // collide those distinctly-childIndexed keys.
        let recordA = ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: ok("gear"), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 100, minY: 4.5, width: 20, height: 24)))
        let recordB = ExtrasRecord(childIndex: 1, role: ok("AXMenuBarItem"), identifier: ok("gear"), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 400, minY: 4.5, width: 20, height: 24)))
        let read = RawRead(process: process(pid: 1), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: [recordA, recordB])
        let set = ItemCatalog.build(reads: [read], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.items.count == 2)
        #expect(set.items.allSatisfy { $0.basis == .positional })
        #expect(set.dropped.isEmpty)
    }

    @Test("two records forced to the exact same key (identical childIndex, a contract-violating input) collide and are both dropped")
    func identicalKeysCollideAndAreBothDropped() {
        // Same pid, same identifier, same childIndex: ItemKeying.assign would
        // never itself produce two records with an identical childIndex from
        // one real read, but the collision splitter must still behave safely
        // rather than silently keep a stale duplicate if it ever happens.
        let recordA = ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: ok("gear"), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 100, minY: 4.5, width: 20, height: 24)))
        let recordB = ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: ok("gear"), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 400, minY: 4.5, width: 20, height: 24)))
        let read = RawRead(process: process(pid: 1), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: [recordA, recordB])
        let set = ItemCatalog.build(reads: [read], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDs, now: 0)
        #expect(set.items.isEmpty)
        #expect(set.dropped.filter { $0.reason == .identityCollision }.count == 2)
    }

    @Test("the own visible item can collide with a third-party item if its own identifier happens to look like that item's full tag")
    func ownVisibleItemCanCollideWithThirdPartyItem() {
        // Own tagTitle is the bare identifier (D9); a third-party tagTitle is
        // "<identifier>/p<pid>". If Ice's own visible identifier happens to
        // equal "x/p12" while a genuine third-party item at pid 12 declares
        // identifier "x", both resolve to the identical (namespace, "x/p12")
        // tag -- a real, if unlikely, collision the splitter must still
        // catch, dropping both and leaving no visibleControlItem.
        let ownIDsLookingLikeATag = OwnIdentifiers(visible: "x/p12", hidden: "Ice.ControlItem.hidden", alwaysHidden: "Ice.ControlItem.alwaysHidden")
        let ownRecord = ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: ok("x/p12"), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 1600, minY: 4.5, width: 20, height: 24)))
        let ownRead = RawRead(process: process(pid: 900, isSelf: true, bundleID: "com.example.a"), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: [ownRecord])
        let thirdPartyRecord = ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: ok("x"), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 200, minY: 4.5, width: 20, height: 24)))
        let thirdPartyRead = RawRead(process: process(pid: 12, bundleID: "com.example.a"), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: [thirdPartyRecord])

        let set = ItemCatalog.build(reads: [ownRead, thirdPartyRead], agentPID: nil, bounds: bounds, isTrusted: true, ownIdentifiers: ownIDsLookingLikeATag, now: 0)
        #expect(set.visibleControlItem == nil)
        #expect(set.items.isEmpty)
        #expect(set.dropped.filter { $0.reason == .identityCollision }.count == 2)
    }
}

// MARK: - Fixtures

private func process(pid: Int32, isSelf: Bool = false, bundleID: String = "com.example.a", launchTime: Double? = 10) -> ProcessInfoRecord {
    ProcessInfoRecord(pid: pid, bundleID: bundleID, localizedName: nil, executableName: nil, launchTime: launchTime, isSelf: isSelf)
}

private func ok(_ value: String = "") -> AttributeRead<String> {
    AttributeRead(value: value, error: "success")
}

private func okFrame(_ value: BarRect = BarRect(minX: 0, minY: 4.5, width: 20, height: 24)) -> AttributeRead<BarRect> {
    AttributeRead(value: value, error: "success")
}

private func thirdParty(pid: Int32, identifier: String, minX: Double, minY: Double = 4.5, width: Double = 20, hasFrame: Bool = true) -> RawRead {
    let resolvedFrame: BarRect? = hasFrame ? BarRect(minX: minX, minY: minY, width: width, height: 24) : nil
    let record = ExtrasRecord(
        childIndex: 0,
        role: ok("AXMenuBarItem"),
        identifier: ok(identifier),
        title: ok(),
        description: ok(),
        help: ok(),
        frame: resolvedFrame.map(okFrame) ?? AttributeRead(value: nil, error: "noValue")
    )
    return RawRead(process: process(pid: pid, bundleID: "com.example.\(pid)"), extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: [record])
}
