// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q19): what S1 runs
// next. Each step is one `vizprobe icebar-step` process: a batch of a profile's
// band scan (one cycle per length) or five cycles at its band's midpoint. The
// band rules are C2Core's (route C: "coarse scan and refinement as C2 section
// 4"); the capacity search is route C's S1 row. Pure.
import C2Core

public struct S1Profile: Hashable, Sendable {
    public let k: Int
    public let menu: C2MenuWidth

    public init(k: Int, menu: C2MenuWidth) {
        self.k = k
        self.menu = menu
    }

    public var id: String { "k\(k)-\(menu.rawValue)" }
}

public enum S1Purpose: Equatable, Sendable {
    case bracket
    /// Five cycles at the midpoint; `replicate`: the one re-run of a rate failure.
    case confirm(replicate: Bool)
}

public enum S1Verdict: Equatable, Sendable {
    case capacity(Int)
    /// Route C: "capacity below 4: the sitting ends and the owner decides before S2".
    case capacityBelowFour(Int)
    case noGo(String)
    case safetyStop(String)
}

public enum S1Step: Equatable, Sendable {
    case run(S1Profile, purpose: S1Purpose, lengths: [Double])
    case finished(S1Verdict)
}

public enum S1StepResult: Equatable, Sendable {
    /// Settled readings (the step retries an inconclusive cycle itself, `C2Retry`).
    case bracket(points: [C2Point], completed: Bool)
    case confirm(cycles: [CycleRecord], completed: Bool)
    /// The step judged a NO-GO outside its cycles' records (a control or baseline capture).
    case noGo(String)
    case safetyStop(String)
}

public struct S1Sequencer: Equatable, Sendable {
    public static let doubling = [1, 2, 4, 8, 12, 16]
    public static let menus = [C2MenuWidth.short, .mid]
    public static let maxLengthsPerStep = C2PendingList.maxPerProcess
    public static let minCapacity = 4
    /// k = 3 gates S2-S5 and is skipped by the doubling.
    public static let confirmedAfter = 3

    private enum Search: Equatable, Sendable { case doubling, integers, three }
    private enum Phase: Equatable, Sendable {
        case bracket
        case confirm(length: Double, inconclusive: Int, replicate: Bool)
    }

    private var verdict: S1Verdict?
    private var passed = [Int: Bool]()
    private var search = Search.doubling
    private var queue = [Int]()
    private var k = S1Sequencer.doubling[0]
    private var menuIndex = 0
    private var phase = Phase.bracket
    private var points = [C2Point]()
    private var pending = C2PendingList(C2BracketSequencer.coarse)

    public init() {}

    private var profile: S1Profile { S1Profile(k: k, menu: Self.menus[menuIndex]) }

    public func next() -> S1Step {
        if let verdict { return .finished(verdict) }
        switch phase {
        case .bracket: return .run(profile, purpose: .bracket, lengths: pending.batch)
        case .confirm(let length, _, let replicate): return .run(profile, purpose: .confirm(replicate: replicate), lengths: [length])
        }
    }

    public mutating func record(_ result: S1StepResult) {
        guard verdict == nil else { return }
        switch (result, phase) {
        case (.safetyStop(let why), _):
            verdict = .safetyStop(why)
        case (.noGo(let why), _):
            verdict = .noGo("\(profile.id): \(why)")
        case (.bracket(let measured, let completed), .bracket):
            absorb(measured, completed: completed)
        case (.confirm(let cycles, let completed), .confirm(let length, let inconclusive, let replicate)):
            settle(FallbackTally.tally(cycles).verdict, completed: completed, length: length, inconclusive: inconclusive, replicate: replicate)
        default:
            // A result of the wrong kind proves nothing about this step.
            profileEnded(passed: false)
        }
    }

    // MARK: - One profile

    /// As C2's sitting A: a short batch is re-run without its measured lengths, three short batches end the list.
    private mutating func absorb(_ measured: [C2Point], completed: Bool) {
        let given = Set(pending.batch)
        points += measured.filter { given.contains($0.length) }
        if pending.absorb(measured, completed: completed) {
            advance()
        } else if pending.exhausted {
            profileEnded(passed: false)
        }
    }

    private mutating func advance() {
        let more = C2Band.nextExpansion(points) ?? C2Band.refinementPoints(points)
        if !more.isEmpty {
            pending = C2PendingList(more)
        } else if let band = C2Band.band(points) {
            phase = .confirm(length: ((band.lo + band.hi) / 2).rounded(), inconclusive: 0, replicate: false)
        } else if k == Self.doubling[0] {
            verdict = .noGo("no band at k = \(k) (\(profile.menu.rawValue))")
        } else {
            profileEnded(passed: false)
        }
    }

    private mutating func settle(_ tally: LengthVerdict, completed: Bool, length: Double, inconclusive: Int, replicate: Bool) {
        switch (tally, completed) {
        case (.noGo, _):
            verdict = .noGo("\(profile.id) at \(Int(length)) pt")
        case (.pass, true):
            profileEnded(passed: true)
        case (.fail, true):
            // A failure is replicated once, in a new step, before it counts.
            if replicate { profileEnded(passed: false) } else { phase = .confirm(length: length, inconclusive: 0, replicate: true) }
        default:
            // Inconclusive, or a step that ended short: re-run at most twice.
            if inconclusive + 1 >= Repeats.maxInconclusiveInARow {
                profileEnded(passed: false)
            } else {
                phase = .confirm(length: length, inconclusive: inconclusive + 1, replicate: replicate)
            }
        }
    }

    private mutating func profileEnded(passed profilePassed: Bool) {
        let lastMenu = menuIndex == Self.menus.count - 1
        if profilePassed, !lastMenu {
            menuIndex += 1
            startProfile()
        } else {
            passed[k] = profilePassed
            chooseNextK()
        }
    }

    private mutating func startProfile() {
        phase = .bracket
        points = []
        pending = C2PendingList(C2BracketSequencer.coarse)
    }

    // MARK: - The capacity search

    /// The largest k such that it and every tested smaller k passed.
    private var capacity: Int {
        var best = 0
        for tested in passed.keys.sorted() {
            guard passed[tested] == true else { break }
            best = tested
        }
        return best
    }

    private mutating func chooseNextK() {
        let didPass = passed[k] == true
        switch search {
        case .doubling:
            if didPass, let index = Self.doubling.firstIndex(of: k), index + 1 < Self.doubling.count {
                return start(Self.doubling[index + 1])
            }
            if !didPass {
                // Every integer between the last pass and the failure (no bisection).
                queue = Array((capacity + 1)..<max(capacity + 1, k))
                search = .integers
                if !queue.isEmpty { return start(queue.removeFirst()) }
            }
        case .integers:
            if didPass, !queue.isEmpty { return start(queue.removeFirst()) }
        case .three:
            break
        }
        if search != .three, capacity >= Self.minCapacity, passed[Self.confirmedAfter] == nil {
            search = .three
            return start(Self.confirmedAfter)
        }
        verdict = capacity >= Self.minCapacity ? .capacity(capacity) : .capacityBelowFour(capacity)
    }

    private mutating func start(_ next: Int) {
        k = next
        menuIndex = 0
        startProfile()
    }
}
