// The first run's watch model (plan 2026-09-24-ice-first-run.md, section 5):
// what one 0.2 s tick of Accessibility reads looks like, in display-local
// points. Foundation-free on purpose; the executable fills it from
// MenuBarDiscovery's reader.

/// An Accessibility frame, top-left origin.
public struct WatchFrame: Equatable, Hashable, Sendable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    public var maxX: Double { minX + width }
    public var midX: Double { minX + width / 2 }
}

/// The menu bar's horizontal extent and height on the one display the run
/// uses. A frame is on the bar when its top is inside the bar and its left
/// edge inside `[minX, maxX)` -- the same test as IceCore's parked rule.
public struct BarLine: Equatable, Sendable {
    public let minX: Double
    public let maxX: Double
    public let height: Double

    public init(minX: Double, maxX: Double, height: Double) {
        self.minX = minX
        self.maxX = maxX
        self.height = height
    }

    public func contains(_ frame: WatchFrame) -> Bool {
        frame.minY >= 0 && frame.minY < height && frame.minX >= minX && frame.minX < maxX
    }
}

/// The horizontal overlap of two frames as a fraction of the narrower one
/// (the measure the recorded overflow and stacking rules use).
public func overlapFraction(_ a: WatchFrame, _ b: WatchFrame) -> Double {
    let overlap = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
    let narrower = min(a.width, b.width)
    return narrower > 0 ? overlap / narrower : 0
}

/// One status item: its owner's pid and its index among that process's
/// `AXExtrasMenuBar` children.
public struct ItemID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let pid: Int32
    public let child: Int

    public init(pid: Int32, child: Int) {
        self.pid = pid
        self.child = child
    }

    public static func < (lhs: ItemID, rhs: ItemID) -> Bool {
        (lhs.pid, lhs.child) < (rhs.pid, rhs.child)
    }

    public var description: String { "\(pid)/\(child)" }
}

public struct WatchItem: Equatable, Sendable {
    public let id: ItemID
    public let identifier: String
    public let frame: WatchFrame?
    /// One of Ice's own control items (never the "item" side of a trip).
    public let isIce: Bool

    public init(id: ItemID, identifier: String, frame: WatchFrame?, isIce: Bool) {
        self.id = id
        self.identifier = identifier
        self.frame = frame
        self.isIce = isIce
    }
}

/// `failed` is an error or a timeout: it says nothing about the items.
public enum ReadState: Equatable, Sendable {
    case ok
    case failed
}

public struct ProcessRead: Equatable, Sendable {
    public let pid: Int32
    public let state: ReadState
    public let items: [WatchItem]

    public init(pid: Int32, state: ReadState, items: [WatchItem]) {
        self.pid = pid
        self.state = state
        self.items = items
    }
}

public struct Tick: Equatable, Sendable {
    /// Seconds the tick's reads took; slow ticks are not evaluated.
    public let duration: Double
    public let agentFrames: [WatchFrame]
    public let agentState: ReadState
    public let processes: [ProcessRead]

    public init(duration: Double, agentFrames: [WatchFrame], agentState: ReadState, processes: [ProcessRead]) {
        self.duration = duration
        self.agentFrames = agentFrames
        self.agentState = agentState
        self.processes = processes
    }

    /// Items of processes read ok, on the bar, not Ice's.
    func userItemsOnBar(_ bar: BarLine) -> [(id: ItemID, frame: WatchFrame)] {
        processes.filter { $0.state == .ok }.flatMap(\.items).compactMap { item in
            guard !item.isIce, let frame = item.frame, bar.contains(frame) else { return nil }
            return (item.id, frame)
        }
    }

    var failedPIDs: Set<Int32> {
        Set(processes.filter { $0.state == .failed }.map(\.pid))
    }
}
