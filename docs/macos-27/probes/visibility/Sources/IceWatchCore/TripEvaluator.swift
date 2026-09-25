/// The watchdog's trips (plan 2026-09-24-ice-first-run.md, section 5).
public enum Trip: Equatable, Sendable {
    /// A `«`-width agent frame on the bar overlapped by an item by more than
    /// the overflow fraction: the recorded overflow signature. First tick.
    case foldWithOverlap(ItemID)
    /// A `«`-width agent frame on the bar for two evaluated ticks running.
    case foldPersisting
    /// Two items overlapping by more than the fraction, two ticks running.
    case stack(ItemID, ItemID)
}

public struct TripParameters: Equatable, Sendable {
    /// IceCore's `DetectorParameters.preRegistered` chevron width and
    /// tolerance (every recorded `«` reading is 17.5 pt).
    public var chevronWidth = 17.5
    public var chevronTolerance = 0.5
    /// IceCore's `.stacked` threshold (ItemPosition, plan 4.1.4).
    public var overlapFraction = 0.25
    /// A tick whose reads took longer is recorded but not evaluated.
    public var maxTickDuration = 0.5

    public init() {}
}

/// Evaluates ticks in order. Never acts; the supervisor does. A failed read
/// (of `MenuBarAgent` or of a process) neither trips nor clears anything
/// pending that depends on it; a slow tick is skipped entirely.
public struct TripEvaluator {
    private struct Pair: Hashable, Comparable {
        let a: ItemID
        let b: ItemID

        init(_ x: ItemID, _ y: ItemID) {
            (a, b) = x < y ? (x, y) : (y, x)
        }

        static func < (lhs: Pair, rhs: Pair) -> Bool {
            (lhs.a, lhs.b) < (rhs.a, rhs.b)
        }
    }

    public let bar: BarLine
    public let parameters: TripParameters
    private var pendingFold = false
    private var pendingPairs: Set<Pair> = []

    public init(bar: BarLine, parameters: TripParameters = TripParameters()) {
        self.bar = bar
        self.parameters = parameters
    }

    public mutating func evaluate(_ tick: Tick) -> [Trip] {
        guard tick.duration <= parameters.maxTickDuration else {
            return []
        }
        let items = tick.userItemsOnBar(bar)
        var trips = evaluateFold(tick, items: items)
        trips += evaluateStacks(items, failedPIDs: tick.failedPIDs)
        return trips
    }

    private mutating func evaluateFold(_ tick: Tick, items: [(id: ItemID, frame: WatchFrame)]) -> [Trip] {
        guard tick.agentState == .ok else {
            return []
        }
        let chevrons = tick.agentFrames.filter {
            bar.contains($0) && abs($0.width - parameters.chevronWidth) <= parameters.chevronTolerance
        }
        guard !chevrons.isEmpty else {
            pendingFold = false
            return []
        }
        let overlapping = items.first { item in
            chevrons.contains { overlapFraction(item.frame, $0) > parameters.overlapFraction }
        }
        if let overlapping {
            pendingFold = true
            return [.foldWithOverlap(overlapping.id)]
        }
        if pendingFold {
            return [.foldPersisting]
        }
        pendingFold = true
        return []
    }

    private mutating func evaluateStacks(_ items: [(id: ItemID, frame: WatchFrame)], failedPIDs: Set<Int32>) -> [Trip] {
        var current: Set<Pair> = []
        for (index, first) in items.enumerated() {
            for second in items[(index + 1)...] where overlapFraction(first.frame, second.frame) > parameters.overlapFraction {
                current.insert(Pair(first.id, second.id))
            }
        }
        let trips = current.intersection(pendingPairs).sorted().map { Trip.stack($0.a, $0.b) }
        let unknown = pendingPairs.filter { failedPIDs.contains($0.a.pid) || failedPIDs.contains($0.b.pid) }
        pendingPairs = current.union(unknown)
        return trips
    }
}
