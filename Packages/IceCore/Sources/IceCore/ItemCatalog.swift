/// Everything one pass produced (plan section 4.1.5). `ItemCatalog.build` is
/// the only place that assembles it from raw reads; `ItemCatalog.carryOver`
/// is the only place that bridges two passes.
public struct DiscoveredItemSet: Equatable, Sendable {
    /// Third-party status items only -- own items live in
    /// `visibleControlItem`/`hiddenDivider`/`alwaysHiddenDivider`. Ordered by
    /// frame `minX`, then pid, then child index; items with no frame sort
    /// last.
    public let items: [DiscoveredItem]
    public let visibleControlItem: DiscoveredItem?
    public let hiddenDivider: DividerReading?
    public let alwaysHiddenDivider: DividerReading?
    public let ownRead: OwnReadStatus
    /// `MenuBarAgent`'s children, frames only (D4: never listed as items).
    public let systemElements: [BarRect]
    public let dropped: [DroppedItem]
    /// Fresh `ProcessInfoRecord`s for every pid whose Accessibility read
    /// failed this pass, taken from `RawRead.process` -- populated by the
    /// caller's process enumeration regardless of whether the AX walk
    /// itself succeeded or even ran (plan section 4.1.1: `RawRead.process`
    /// is independent of `extrasError`/`childrenError`). `ItemCatalog.
    /// carryOver` needs this: a wholly failed read produces no fresh
    /// `DiscoveredItem` for that pid, so without a side channel to the
    /// fresh identity, a pid reused by a different process while *both*
    /// processes happen to fail their reads could never be told apart from
    /// one process failing twice in a row. This field is not part of the
    /// task's literal field list; see the implementation report for why it
    /// was added.
    public let staleProcesses: [Int32: ProcessInfoRecord]
    public let completeness: Completeness

    /// The third-party items, then Ice's own icon when this set has it --
    /// parked ones included, so not a filter for what a view may list.
    public var listedItems: [DiscoveredItem] {
        items + (visibleControlItem.map { [$0] } ?? [])
    }

    public init(
        items: [DiscoveredItem],
        visibleControlItem: DiscoveredItem?,
        hiddenDivider: DividerReading?,
        alwaysHiddenDivider: DividerReading?,
        ownRead: OwnReadStatus,
        systemElements: [BarRect],
        dropped: [DroppedItem],
        staleProcesses: [Int32: ProcessInfoRecord] = [:],
        completeness: Completeness
    ) {
        self.items = items
        self.visibleControlItem = visibleControlItem
        self.hiddenDivider = hiddenDivider
        self.alwaysHiddenDivider = alwaysHiddenDivider
        self.ownRead = ownRead
        self.systemElements = systemElements
        self.dropped = dropped
        self.staleProcesses = staleProcesses
        self.completeness = completeness
    }
}

/// Builds one pass's `DiscoveredItemSet` from raw reads, and bridges a failed
/// pid's items across passes (plan section 4.1.5).
public enum ItemCatalog {
    // MARK: - build

    public static func build(
        reads: [RawRead],
        agentPID: Int32?,
        bounds: BarBounds,
        isTrusted: Bool,
        ownIdentifiers: OwnIdentifiers,
        now: Double,
        timeout: Double = ReadClassifier.defaultTimeout
    ) -> DiscoveredItemSet {
        guard isTrusted else {
            return DiscoveredItemSet(
                items: [], visibleControlItem: nil, hiddenDivider: nil, alwaysHiddenDivider: nil,
                ownRead: .notRead, systemElements: [], dropped: [], completeness: .permissionDenied
            )
        }

        var systemElements = [BarRect]()
        var dropped = [DroppedItem]()
        var failedPIDs = [Int32]()
        var staleProcesses = [Int32: ProcessInfoRecord]()
        var ownRead = OwnReadStatus.notRead
        var ownVisibleKeyed: KeyedRecord?
        var ownProcess: ProcessInfoRecord?
        var hiddenDivider: DividerReading?
        var alwaysHiddenDivider: DividerReading?
        var thirdPartyByProcess = [(process: ProcessInfoRecord, records: [ExtrasRecord])]()

        for raw in reads {
            let outcome = ReadClassifier.outcome(raw, timeout: timeout)

            if case .failed = outcome {
                failedPIDs.append(raw.process.pid)
                staleProcesses[raw.process.pid] = raw.process
                if raw.process.isSelf { ownRead = .failed }
                continue
            }

            if let agentPID, raw.process.pid == agentPID {
                if case .items(let records) = outcome {
                    systemElements.append(contentsOf: records.compactMap(\.frame.value))
                }
                continue
            }

            let records: [ExtrasRecord] = { if case .items(let r) = outcome { return r }; return [] }()

            if raw.process.isSelf {
                ownProcess = raw.process
                let own = classifyOwn(records: records, process: raw.process, ownIdentifiers: ownIdentifiers, bounds: bounds)
                ownVisibleKeyed = own.visibleKeyed
                hiddenDivider = own.hiddenDivider
                alwaysHiddenDivider = own.alwaysHiddenDivider
                dropped.append(contentsOf: own.dropped)
                ownRead = own.hiddenDivider != nil ? .ok : .identifiersMissing
                continue
            }

            var eligible = [ExtrasRecord]()
            for record in records {
                let role = record.role.value ?? ""
                if role == "AXMenuBarItem" {
                    eligible.append(record)
                } else {
                    dropped.append(DroppedItem(key: nil, pid: raw.process.pid, reason: .unrecognizedRole(role)))
                }
            }
            if !eligible.isEmpty {
                thirdPartyByProcess.append((raw.process, eligible))
            }
        }

        var thirdPartyKeyed = [(process: ProcessInfoRecord, keyed: KeyedRecord)]()
        for (process, records) in thirdPartyByProcess {
            for keyed in ItemKeying.assign(process: process, records: records) {
                thirdPartyKeyed.append((process, keyed))
            }
        }

        let positions = positionsFor(thirdPartyKeyed: thirdPartyKeyed, ownVisibleFrame: ownVisibleKeyed?.record.frame.value, systemElements: systemElements, bounds: bounds)

        var provisionalItems = thirdPartyKeyed.enumerated().map { index, entry in
            discoveredItem(from: entry.keyed, process: entry.process, position: positions.thirdParty[index], now: now)
        }

        var provisionalVisible: DiscoveredItem?
        if let ownVisibleKeyed, let ownProcess {
            provisionalVisible = discoveredItem(from: ownVisibleKeyed, process: ownProcess, position: positions.ownVisible, now: now)
        }

        let pool = provisionalItems + (provisionalVisible.map { [$0] } ?? [])
        let (kept, collided) = TagCollision.split(pool, by: \.tagKey)
        for item in collided {
            dropped.append(DroppedItem(key: item.key, pid: item.key.pid, reason: .identityCollision))
        }
        let keptKeys = Set(kept.map(\.key))

        provisionalItems = sortedByFrame(provisionalItems.filter { keptKeys.contains($0.key) })
        if let visible = provisionalVisible, !keptKeys.contains(visible.key) {
            provisionalVisible = nil
        }

        let completeness: Completeness = failedPIDs.isEmpty ? .complete : .incomplete(failedPIDs: failedPIDs)

        return DiscoveredItemSet(
            items: provisionalItems,
            visibleControlItem: provisionalVisible,
            hiddenDivider: hiddenDivider,
            alwaysHiddenDivider: alwaysHiddenDivider,
            ownRead: ownRead,
            systemElements: systemElements,
            dropped: dropped,
            staleProcesses: staleProcesses,
            completeness: completeness
        )
    }

    // MARK: - carryOver

    /// Carries a failed pid's previous items forward, bounded by
    /// `freshness` seconds since each item's `lastConfirmedAt` rather than
    /// by a pass count (contract amendments, adopted 2026-09-23,
    /// superseding plan section 4.1.5's original "≤ 3 passes": round 1
    /// removed the pass cap outright, round 2 replaced it with this time
    /// bound so a process that keeps failing forever cannot leave ghost
    /// items on screen forever). A previous item is carried while (a) its
    /// process was not conclusively read this pass (its pid is in
    /// `failedPIDs` -- any `.failed` outcome, including a discoverer
    /// deadline reported as `extrasError == "notAttempted"`), (b) its
    /// `bundleID` and `launchTime` are unchanged, and (c) `now -
    /// lastConfirmedAt <= freshness`. `carriedPasses` is kept as a
    /// diagnostic counter only; `lastConfirmedAt` itself is never advanced
    /// by carrying. A pid read *successfully* this pass is not in
    /// `failedPIDs` at all, so its previous item is never reconsidered here
    /// -- whatever `current.items` already says about that pid stands.
    public static func carryOver(previous: DiscoveredItemSet?, current: DiscoveredItemSet, now: Double, freshness: Double = 30) -> DiscoveredItemSet {
        guard let previous else { return current }
        guard case .incomplete(let failedPIDs) = current.completeness else { return current }

        var carriedItems = [DiscoveredItem]()
        var dropped = current.dropped

        for pid in failedPIDs {
            let candidates = previous.items.filter { $0.key.pid == pid && !$0.process.isSelf }
            for item in candidates {
                if let fresh = current.staleProcesses[pid] {
                    guard fresh.bundleID == item.process.bundleID, fresh.launchTime == item.process.launchTime else {
                        continue
                    }
                }
                guard now - item.lastConfirmedAt <= freshness else {
                    dropped.append(DroppedItem(key: item.key, pid: pid, reason: .stale))
                    continue
                }
                carriedItems.append(DiscoveredItem(
                    key: item.key, basis: item.basis, process: item.process, frame: item.frame, position: item.position,
                    title: item.title, description: item.description, help: item.help,
                    carriedPasses: item.carriedPasses + 1, lastConfirmedAt: item.lastConfirmedAt
                ))
            }
        }

        let pool = current.items + carriedItems
        let (kept, collided) = TagCollision.split(pool, by: \.tagKey)
        for item in collided {
            dropped.append(DroppedItem(key: item.key, pid: item.key.pid, reason: .identityCollision))
        }

        return DiscoveredItemSet(
            items: sortedByFrame(kept),
            visibleControlItem: current.visibleControlItem,
            hiddenDivider: current.hiddenDivider,
            alwaysHiddenDivider: current.alwaysHiddenDivider,
            ownRead: current.ownRead,
            systemElements: current.systemElements,
            dropped: dropped,
            staleProcesses: current.staleProcesses,
            completeness: current.completeness
        )
    }

    // MARK: - Own-process classification

    private struct OwnClassification {
        var visibleKeyed: KeyedRecord?
        var hiddenDivider: DividerReading?
        var alwaysHiddenDivider: DividerReading?
        var dropped: [DroppedItem]
    }

    /// Routes each of the own process's records to its role by exact,
    /// trimmed identifier match against `ownIdentifiers` (D9). Anything else
    /// is `dropped(.ownUnrecognized)` -- own items are never keyed
    /// positionally, so there is no `.positional` path for them.
    private static func classifyOwn(records: [ExtrasRecord], process: ProcessInfoRecord, ownIdentifiers: OwnIdentifiers, bounds: BarBounds) -> OwnClassification {
        var result = OwnClassification(visibleKeyed: nil, hiddenDivider: nil, alwaysHiddenDivider: nil, dropped: [])
        let namespace = ItemNamespace.resolve(process)

        for record in records {
            let identifier = IdentifierText.trimmed(record.identifier.value ?? "")
            switch identifier {
            case ownIdentifiers.visible:
                let key = ItemKey(namespace: namespace, identifier: identifier, pid: process.pid, childIndex: nil)
                result.visibleKeyed = KeyedRecord(record: record, key: key, basis: .declared)
            case ownIdentifiers.hidden:
                result.hiddenDivider = DividerReading.make(frame: record.frame.value, in: bounds)
            case ownIdentifiers.alwaysHidden:
                result.alwaysHiddenDivider = DividerReading.make(frame: record.frame.value, in: bounds)
            default:
                result.dropped.append(DroppedItem(key: nil, pid: process.pid, reason: .ownUnrecognized))
            }
        }
        return result
    }

    // MARK: - Position

    private struct Positions {
        let thirdParty: [ItemPosition]
        let ownVisible: ItemPosition
    }

    /// Computes each item's position with `PositionRule`, using every
    /// *other* on-bar, framed third-party extra and every system element as
    /// obstacles -- never an own item (T3's `PositionRule` contract).
    /// "On the bar" for obstacle-eligibility purposes is judged with an
    /// empty obstacle set first (parked-ness depends only on an item's own
    /// frame, never on its neighbours), which is what breaks the circularity
    /// of "an obstacle's own position depends on its obstacles".
    private static func positionsFor(
        thirdPartyKeyed: [(process: ProcessInfoRecord, keyed: KeyedRecord)],
        ownVisibleFrame: BarRect?,
        systemElements: [BarRect],
        bounds: BarBounds
    ) -> Positions {
        let frames = thirdPartyKeyed.map(\.keyed.record.frame.value)
        let eligibleAsObstacle = frames.map { frame -> Bool in
            guard let frame else { return false }
            return PositionRule.position(of: frame, in: bounds, obstacles: []) != .parked
        }

        func obstacles(excluding index: Int?) -> [BarRect] {
            var result = systemElements
            for i in frames.indices where i != index && eligibleAsObstacle[i] {
                if let frame = frames[i] { result.append(frame) }
            }
            return result
        }

        let thirdPartyPositions = frames.indices.map { i in
            PositionRule.position(of: frames[i], in: bounds, obstacles: obstacles(excluding: i))
        }
        let ownPosition = PositionRule.position(of: ownVisibleFrame, in: bounds, obstacles: obstacles(excluding: nil))

        return Positions(thirdParty: thirdPartyPositions, ownVisible: ownPosition)
    }

    // MARK: - Shared helpers

    private static func discoveredItem(from keyed: KeyedRecord, process: ProcessInfoRecord, position: ItemPosition, now: Double) -> DiscoveredItem {
        DiscoveredItem(
            key: keyed.key,
            basis: keyed.basis,
            process: process,
            frame: keyed.record.frame.value,
            position: position,
            title: keyed.record.title.value,
            description: keyed.record.description.value,
            help: keyed.record.help.value,
            carriedPasses: 0,
            lastConfirmedAt: now
        )
    }

    /// By frame `minX`, then pid, then child index; items with no frame sort
    /// last (plan section 4.1.5).
    static func sortedByFrame(_ items: [DiscoveredItem]) -> [DiscoveredItem] {
        items.enumerated().sorted { lhs, rhs in
            let (li, l) = lhs
            let (ri, r) = rhs
            switch (l.frame, r.frame) {
            case (nil, nil): break
            case (nil, _): return false
            case (_, nil): return true
            case let (lf?, rf?):
                if lf.minX != rf.minX { return lf.minX < rf.minX }
            }
            if l.key.pid != r.key.pid { return l.key.pid < r.key.pid }
            let lc = l.key.childIndex ?? Int.min
            let rc = r.key.childIndex ?? Int.min
            if lc != rc { return lc < rc }
            return li < ri
        }.map(\.1)
    }
}
