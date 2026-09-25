/// Changes in which items are on the bar -- recorded, never a trip (an app
/// may hide its own item). Section 4 step 15 ends the cycles on any of them.
public enum TopologyEvent: Equatable, Sendable, CustomStringConvertible {
    case joined(ItemID)
    case missing(ItemID)
    case parked(ItemID)

    public var description: String {
        switch self {
        case .joined(let id): "joined \(id)"
        case .missing(let id): "missing \(id)"
        case .parked(let id): "parked \(id)"
        }
    }
}

public struct TopologyTracker {
    public let bar: BarLine
    private var known: Set<ItemID>?

    public init(bar: BarLine) {
        self.bar = bar
    }

    /// The first tick sets the baseline. A failed read records nothing and
    /// keeps that process's items as they were.
    public mutating func update(_ tick: Tick) -> [TopologyEvent] {
        let failed = tick.failedPIDs
        let onBar = Set(tick.userItemsOnBar(bar).map(\.id))
        let offBar = Set(tick.processes.filter { $0.state == .ok }.flatMap(\.items).compactMap { item -> ItemID? in
            guard !item.isIce, let frame = item.frame, !bar.contains(frame) else { return nil }
            return item.id
        })
        guard let previous = known else {
            known = onBar
            return []
        }
        var events = onBar.subtracting(previous).sorted().map(TopologyEvent.joined)
        var kept: Set<ItemID> = []
        for id in previous.subtracting(onBar).sorted() {
            if failed.contains(id.pid) {
                kept.insert(id)
            } else if offBar.contains(id) {
                events.append(.parked(id))
            } else {
                events.append(.missing(id))
            }
        }
        known = onBar.union(kept)
        return events
    }
}
