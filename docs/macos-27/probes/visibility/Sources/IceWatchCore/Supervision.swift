/// What the supervisor knows about its child when it asks the stop machine
/// what to do. `identityMatches` is false once the PID's image path or start
/// time is no longer the spawned one: such a PID is never signalled.
public enum ChildStatus: Equatable, Sendable {
    case notStarted
    case alive(identityMatches: Bool)
    case gone
}

public enum StopAction: Equatable, Sendable {
    case sendTerm
    case sendKill
    case beginPostWatch
    case restore
    case finish
}

/// The stop sequence of plan section 5: TERM, KILL after `killAfter`
/// seconds, a post-exit watch of `postWatch` seconds, then the restore.
public struct StopMachine {
    public enum Phase: Equatable, Sendable {
        case running
        case terminating(since: Double)
        case killing(since: Double)
        case postWatch(until: Double)
        case restoring
        case done
    }

    /// Wall-clock values are sums of doubles; compare with a small slack.
    private static let slack = 1e-6

    public let killAfter: Double
    public let postWatch: Double
    public private(set) var phase: Phase = .running

    public init(killAfter: Double = 1, postWatch: Double = 30) {
        self.killAfter = killAfter
        self.postWatch = postWatch
    }

    public var isStopping: Bool { phase != .running }

    public mutating func requestStop(now: Double, child: ChildStatus) -> [StopAction] {
        guard phase == .running else {
            return []
        }
        switch child {
        case .notStarted:
            phase = .restoring
            return [.restore]
        case .alive(identityMatches: true):
            phase = .terminating(since: now)
            return [.sendTerm]
        case .alive(identityMatches: false), .gone:
            return enterPostWatch(now)
        }
    }

    public mutating func step(now: Double, child: ChildStatus) -> [StopAction] {
        switch phase {
        case .running, .restoring, .done:
            return []
        case .terminating(let since):
            guard child == .alive(identityMatches: true) else {
                return enterPostWatch(now)
            }
            guard now - since + Self.slack >= killAfter else {
                return []
            }
            phase = .killing(since: now)
            return [.sendKill]
        case .killing:
            return child == .alive(identityMatches: true) ? [] : enterPostWatch(now)
        case .postWatch(let until):
            guard now + Self.slack >= until else {
                return []
            }
            phase = .restoring
            return [.restore]
        }
    }

    public mutating func restoreFinished() -> [StopAction] {
        guard phase == .restoring else {
            return []
        }
        phase = .done
        return [.finish]
    }

    private mutating func enterPostWatch(_ now: Double) -> [StopAction] {
        phase = .postWatch(until: now + postWatch)
        return [.beginPostWatch]
    }
}

/// 30 min, 15 more per extension, never past 60 min from the start.
public struct Deadman: Equatable, Sendable {
    public let start: Double
    public let step: Double
    public let cap: Double
    public private(set) var deadline: Double

    public init(start: Double, base: Double = 1800, step: Double = 900, cap: Double = 3600) {
        self.start = start
        self.step = step
        self.cap = cap
        self.deadline = start + base
    }

    public mutating func extend() {
        deadline = min(deadline + step, start + cap)
    }

    public func isExpired(now: Double) -> Bool {
        now >= deadline
    }
}
