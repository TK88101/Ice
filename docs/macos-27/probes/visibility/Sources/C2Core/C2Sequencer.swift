// T4 (docs/plans/2026-09-28-c2-protocol.md sections 3-5, 6.1 item 5): what
// the sequencer (`vizprobe c2-run`) runs next. Each step is one
// `vizprobe c2-config` process measuring one length list for one
// configuration; the process's settled points come back here. Pure.

public struct C2Configuration: Equatable, Sendable {
    public let hiddenCount: Int
    public let width: C2MenuWidth

    public init(hiddenCount: Int, width: C2MenuWidth) {
        self.hiddenCount = hiddenCount
        self.width = width
    }

    public var id: String { "k\(hiddenCount)-\(width.rawValue)" }

    /// The 12 configurations, long menus first (6.1 item 4: their likely
    /// not-shown outcome is known within minutes), then mid, then short.
    public static let all: [C2Configuration] = [C2MenuWidth.long, .mid, .short].flatMap { width in
        (1...4).map { C2Configuration(hiddenCount: $0, width: width) }
    }
}

/// One finished `c2-config` process, as its final manifest reports it.
public struct C2ProcessResult: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case completed
        case inconclusive(String)
        case safetyStop
    }

    public let status: Status
    public let points: [C2Point]

    public init(status: Status, points: [C2Point]) {
        self.status = status
        self.points = points
    }
}

public enum C2Step: Equatable, Sendable {
    case run(C2Configuration, lengths: [Double])
    case finished(C2Verdict)
}

/// Shared by both sittings: the pending length list of the current
/// configuration, handed out at most `maxPerProcess` lengths per process (so
/// every process fits the 20 min watchdog at a real 40 s per cycle -- Codex
/// review of the instrument, round 1), re-run without its already-measured
/// lengths when a process falls short; `C2Retry.maxAttempts` short
/// processes per list, and a process that measured its whole batch never
/// counts as one. Public: route C's S1 batches its band scans the same way.
public struct C2PendingList: Equatable, Sendable {
    public static let maxPerProcess = 14

    public private(set) var lengths: [Double]
    public private(set) var failures = 0

    public init(_ lengths: [Double]) {
        self.lengths = lengths
    }

    public var batch: [Double] { Array(lengths.prefix(Self.maxPerProcess)) }

    /// Removes what `points` measured; `true` when nothing is left.
    public mutating func absorb(_ points: [C2Point], completed: Bool) -> Bool {
        let given = batch.count
        var remaining = lengths
        var measured = 0
        for point in points {
            guard let index = remaining.firstIndex(of: point.length) else { continue }
            remaining.remove(at: index)
            measured += 1
        }
        if !completed || measured < given { failures += 1 }
        lengths = remaining
        return lengths.isEmpty
    }

    public var exhausted: Bool { failures >= C2Retry.maxAttempts }
}

/// Sitting A: bracket every configuration (coarse, expansion, refinement).
public struct C2BracketSequencer: Equatable, Sendable {
    public static let coarse = Array(stride(from: 520.0, through: 960.0, by: C2Band.coarseStepPt))

    private let configurations: [C2Configuration]
    private var index = 0
    private var points: [C2Point] = []
    private var pending: C2PendingList
    private var results: [C2ConfigurationResult<C2BracketOutcome>] = []
    private var verdict: C2Verdict?

    public init(configurations: [C2Configuration] = C2Configuration.all) {
        self.configurations = configurations
        self.pending = C2PendingList(Self.coarse)
        if configurations.isEmpty { verdict = C2Accounting.sittingA([]) }
    }

    public func next() -> C2Step {
        if let verdict { return .finished(verdict) }
        return .run(configurations[index], lengths: pending.batch)
    }

    public mutating func record(_ result: C2ProcessResult) {
        guard verdict == nil else { return }
        points += result.points
        let listDone = pending.absorb(result.points, completed: result.status == .completed)
        switch result.status {
        case .safetyStop:
            conclude(.safetyStop)
        case .inconclusive(let why) where !listDone:
            if pending.exhausted { conclude(.notShown(why)) }
        case .completed, .inconclusive:
            if listDone {
                advanceWithinConfiguration()
            } else if pending.exhausted {
                conclude(.notShown("lengths left unmeasured"))
            }
        }
    }

    private mutating func advanceWithinConfiguration() {
        if let chunk = C2Band.nextExpansion(points) {
            pending = C2PendingList(chunk)
            return
        }
        let refine = C2Band.refinementPoints(points)
        if !refine.isEmpty {
            pending = C2PendingList(refine)
            return
        }
        conclude(C2Band.band(points).map { .bracketed($0) } ?? .noBand)
    }

    private mutating func conclude(_ outcome: C2BracketOutcome) {
        results.append(C2ConfigurationResult(configuration: configurations[index].id, outcome: outcome))
        index += 1
        points = []
        pending = C2PendingList(Self.coarse)
        if !C2Accounting.shouldContinue(afterA: outcome) || index == configurations.count {
            verdict = C2Accounting.sittingA(results)
        }
    }
}

/// Sitting B: at `length`, every configuration's collar then N = 5 baseline
/// cycles, as one list.
public struct C2ConfirmSequencer: Equatable, Sendable {
    private let configurations: [C2Configuration]
    private let list: [Double]
    private var index = 0
    private var settled: [C2Settled] = []
    private var pending: C2PendingList
    private var results: [C2ConfigurationResult<C2ConfirmOutcome>] = []
    private var verdict: C2Verdict?

    public init(length: Double, configurations: [C2Configuration] = C2Configuration.all) {
        self.configurations = configurations
        self.list = C2Band.collar(length) + Array(repeating: length, count: C2Accounting.baselineCycles)
        self.pending = C2PendingList(list)
        if configurations.isEmpty { verdict = C2Accounting.sittingB([]) }
    }

    public func next() -> C2Step {
        if let verdict { return .finished(verdict) }
        return .run(configurations[index], lengths: pending.batch)
    }

    public mutating func record(_ result: C2ProcessResult) {
        guard verdict == nil else { return }
        settled += result.points.map { C2Settled(reading: $0.reading) }
        let listDone = pending.absorb(result.points, completed: result.status == .completed)
        if result.status == .safetyStop {
            conclude(.safetyStop)
        } else if listDone || pending.exhausted {
            conclude(.completed(settled))
        }
    }

    private mutating func conclude(_ outcome: C2ConfirmOutcome) {
        results.append(C2ConfigurationResult(configuration: configurations[index].id, outcome: outcome))
        index += 1
        settled = []
        pending = C2PendingList(list)
        if !C2Accounting.shouldContinue(afterB: outcome) || index == configurations.count {
            verdict = C2Accounting.sittingB(results)
        }
    }
}
