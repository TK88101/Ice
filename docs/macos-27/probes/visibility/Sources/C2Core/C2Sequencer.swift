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
/// configuration, re-run without its already-measured lengths when a process
/// ends inconclusive, at most `C2Retry.maxAttempts` processes per list.
struct C2PendingList: Equatable, Sendable {
    var lengths: [Double]
    var processes = 0

    init(_ lengths: [Double]) {
        self.lengths = lengths
    }

    /// Removes what `points` measured; `true` when nothing is left.
    mutating func absorb(_ points: [C2Point]) -> Bool {
        processes += 1
        var remaining = lengths
        for point in points {
            if let index = remaining.firstIndex(of: point.length) { remaining.remove(at: index) }
        }
        lengths = remaining
        return lengths.isEmpty
    }

    var exhausted: Bool { processes >= C2Retry.maxAttempts }
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
        return .run(configurations[index], lengths: pending.lengths)
    }

    public mutating func record(_ result: C2ProcessResult) {
        guard verdict == nil else { return }
        points += result.points
        let listDone = pending.absorb(result.points)
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
        return .run(configurations[index], lengths: pending.lengths)
    }

    public mutating func record(_ result: C2ProcessResult) {
        guard verdict == nil else { return }
        settled += result.points.map { C2Settled(reading: $0.reading) }
        let listDone = pending.absorb(result.points)
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
