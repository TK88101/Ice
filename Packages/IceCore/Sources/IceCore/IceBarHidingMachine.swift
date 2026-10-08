/// When Ice hides the chosen items on macOS 27 in IceBar mode, at which
/// length, and what it can honestly say of them (plan
/// 2026-10-07-icebar-preference-hiding, S3 and its T3b design; the length walk
/// is plan 2026-10-03-icebar-build's D1). Pure: Ice feeds events and executes
/// the commands; nothing here touches the bar. The state it reports is
/// `PreferenceHidingStateRule`'s, from the roster and preconditions Ice
/// samples, and from the checks of the length the machine applied.

/// The machine's constants. INFERRED, to be judged in the lab (S4).
public struct IceBarHidingParameters: Equatable, Sendable {
    /// How long a layout must stay unchanged before a calibration, and
    /// before a re-check after a soft layout change.
    public let quietPeriod: Double
    /// The least time between two calibration starts.
    public let minInterval: Double
    /// Cycles a member seen drawn at rest may start before Ice stops trying,
    /// for one roster and display.
    public let maxFailures: Int
    /// How long the bar stays at standard length between two trials.
    public let restDwell: Double
    public let calibration: HiddenLengthParameters

    public init(
        quietPeriod: Double,
        minInterval: Double,
        maxFailures: Int,
        restDwell: Double,
        calibration: HiddenLengthParameters
    ) {
        self.quietPeriod = quietPeriod
        self.minInterval = minInterval
        self.maxFailures = maxFailures
        self.restDwell = restDwell
        self.calibration = calibration
    }

    public static let standard = IceBarHidingParameters(
        quietPeriod: 3,
        minInterval: 30,
        maxFailures: 3,
        restDwell: 1,
        calibration: .standard
    )
}

/// What Ice reads once a tick.
public struct IceBarHidingSample: Equatable, Sendable {
    /// The roster's tags as `hidden`, the cache's other sections, and what
    /// the bar is shown with.
    public let signature: LayoutSignature
    public let preconditions: PreferenceHidingPreconditionResult
    public let membership: PreferenceHidingMembership
    /// The mouse is in the menu bar, or the IceBar is presented.
    public let isInteracting: Bool
    /// A Command-drag of a menu bar item is under way.
    public let isDragging: Bool
    /// The hidden divider decided the sections in a cache pass since the
    /// length last became standard: the roster reflects the bar as it is.
    public let boundaryUsable: Bool

    public init(
        signature: LayoutSignature,
        preconditions: PreferenceHidingPreconditionResult,
        membership: PreferenceHidingMembership,
        isInteracting: Bool,
        isDragging: Bool,
        boundaryUsable: Bool
    ) {
        self.signature = signature
        self.preconditions = preconditions
        self.membership = membership
        self.isInteracting = isInteracting
        self.isDragging = isDragging
        self.boundaryUsable = boundaryUsable
    }
}

public enum IceBarHidingEvent: Equatable, Sendable {
    case mode(isIceBar: Bool)
    case sample(IceBarHidingSample)
    /// The answer to `takeBaseline(token:)`: whether every ready member has a
    /// shown baseline it can be checked against.
    case baseline(token: Int, ok: Bool)
    /// The answer to `observe(token:length:)`: each member's check at that
    /// length, and whether `MenuBarAgent` listed a `«` (recorded only, D-b).
    case observed(token: Int, checks: [ItemKey: SectionItemCheck], chevronListed: Bool?)
}

public enum IceBarHidingCommand: Equatable, Sendable {
    /// The hidden control item's length; `nil` is the standard length.
    case setLength(Double?)
    /// Take a baseline of the roster with the section shown.
    case takeBaseline(token: Int)
    /// Check the members at the length the bar is now at.
    case observe(token: Int, length: Double)
    case report(IceBarHidingStatus)
}

public struct IceBarHidingMachine: Equatable, Sendable {
    /// A length being observed, and the request it answers to.
    public struct Trial: Equatable, Sendable {
        public let token: Int
        public let length: Double
    }

    /// What a settle is for when its observation is not clean.
    public enum SettleKind: Equatable, Sendable {
        /// The last verified length: not clean, the walk starts from it.
        case lastGood
        /// Rest whatever was seen.
        case final
    }

    /// A soft layout change the rest has not been re-checked after (D-e).
    public struct PendingChange: Equatable, Sendable {
        public let change: PreferenceHidingLayoutChange
        public let since: Double
    }

    /// A length Ice keeps applied, and what it last saw there.
    public struct Rest: Equatable, Sendable {
        public let length: Double
        public var checks: [ItemKey: SectionItemCheck]
        public var chevronListed: Bool?
        public var pending: PendingChange?
        /// The token of the re-check under way.
        public var recheck: Int?
    }

    public enum Phase: Equatable, Sendable {
        /// Not IceBar mode.
        case off
        /// A precondition failed (D-c); standard length.
        case blocked
        /// Standard length, waiting for the layout to hold still.
        case quiet(since: Double)
        /// Standard length, the baseline under way.
        case baselining(token: Int)
        /// `pending` is the trial under way; without one the bar is at
        /// standard length since `restedAt`.
        case calibrating(observations: [HiddenLengthObservation], pending: Trial?, restedAt: Double)
        /// The one observation at a length Ice means to rest at.
        case settling(Trial, SettleKind)
        case resting(Rest)
    }

    public let parameters: IceBarHidingParameters
    public private(set) var phase = Phase.off

    /// The last sample: the roster and preconditions the status speaks of.
    private var sample: IceBarHidingSample?
    /// The latest length whose settle saw every ready member absent.
    private var lastGood: Double?
    /// Where the calibration under way anchors its grid.
    private var anchor: Double?
    /// Cycles started because a member was seen drawn at rest, since the
    /// roster or display last changed or a length last verified.
    private var failures = 0
    private var lastStart: Double?
    private var lastToken = 0
    private var reported = IceBarHidingStatus.off

    public init(parameters: IceBarHidingParameters = .standard) {
        self.parameters = parameters
    }

    /// A length other than the standard one is set: what `blocked` and
    /// `quiet` must retire first.
    public var lengthSet: Bool {
        switch phase {
        case .calibrating(_, let pending, _): pending != nil
        case .settling, .resting: true
        case .off, .blocked, .quiet, .baselining: false
        }
    }

    /// A length is applied in the rule's sense: Ice rests at it. The IceBar
    /// is offered exactly then (not during a trial or a settle: a presented
    /// IceBar would end that observation).
    public var lengthApplied: Bool {
        if case .resting = phase { true } else { false }
    }

    /// The `«` reading of the rest's last observation; recorded, never acted on.
    public var chevronListed: Bool? {
        if case .resting(let rest) = phase { rest.chevronListed } else { nil }
    }

    public var status: IceBarHidingStatus {
        if phase == .off { return .off }
        guard let sample else { return .state(.requestedNotVerified(reasons: [.lengthNotApplied])) }
        var rest: Rest?
        if case .resting(let value) = phase { rest = value }
        return .state(PreferenceHidingStateRule.evaluate(
            preconditions: sample.preconditions,
            membership: sample.membership,
            lengthApplied: rest != nil,
            checks: rest?.checks ?? [:],
            pendingLayoutChange: rest?.pending?.change
        ))
    }

    /// The machine after `event`, and what Ice must do, in order. A changed
    /// status is reported last, after any length it speaks of was set.
    public func step(
        _ event: IceBarHidingEvent,
        now: Double
    ) -> (machine: IceBarHidingMachine, commands: [IceBarHidingCommand]) {
        var next = self
        var commands = next.apply(event, now: now)
        let status = next.status
        if status != next.reported {
            next.reported = status
            commands.append(.report(status))
        }
        return (next, commands)
    }

    private mutating func apply(_ event: IceBarHidingEvent, now: Double) -> [IceBarHidingCommand] {
        switch event {
        case .mode(let isIceBar):
            return setMode(isIceBar, now: now)
        case .sample(let sample):
            return phase == .off ? [] : handle(sample, now: now)
        case .baseline(let token, let ok):
            return baselineTaken(token: token, ok: ok, now: now)
        case .observed(let token, let checks, let chevronListed):
            return observed(token: token, checks: checks, chevronListed: chevronListed, now: now)
        }
    }

    // MARK: - Mode and samples

    private mutating func setMode(_ isIceBar: Bool, now: Double) -> [IceBarHidingCommand] {
        switch (phase == .off, isIceBar) {
        case (true, true):
            phase = .quiet(since: now)
            return []
        case (false, false):
            // Tokens never restart: a late answer must not match a new request.
            let (token, reported) = (lastToken, reported)
            self = IceBarHidingMachine(parameters: parameters)
            (lastToken, self.reported) = (token, reported)
            return [.setLength(nil)]
        default:
            return []
        }
    }

    private mutating func handle(_ sample: IceBarHidingSample, now: Double) -> [IceBarHidingCommand] {
        let previous = self.sample?.signature
        self.sample = sample
        // The owner is arranging items: they need the real divider.
        if sample.isDragging { return enterQuiet(now) }
        if !sample.preconditions.isOk { return enterBlocked() }
        if let previous, let change = PreferenceHidingLayoutChange.between(previous, sample.signature) {
            if change.isStructural {
                failures = 0
                return enterQuiet(now)
            }
            if case .resting(var rest) = phase {
                // D-e: the length stays; the checks are owed again.
                rest.pending = PendingChange(change: change, since: now)
                rest.recheck = nil
                phase = .resting(rest)
            } else if phase != .blocked {
                return restartQuiet(now)
            }
        }
        return advance(sample, now: now)
    }

    private mutating func advance(_ sample: IceBarHidingSample, now: Double) -> [IceBarHidingCommand] {
        switch phase {
        case .off:
            return []
        case .blocked:
            // The preconditions hold again.
            return enterQuiet(now)
        case .quiet(let since):
            guard now - since >= parameters.quietPeriod else { return [] }
            return start(sample, now: now)
        case .baselining, .settling:
            return sample.isInteracting ? enterQuiet(now) : []
        case .calibrating(let observations, let pending, let restedAt):
            if sample.isInteracting { return enterQuiet(now) }
            guard pending == nil, now - restedAt >= parameters.restDwell else { return [] }
            return propose(after: observations, now: now)
        case .resting(var rest):
            guard
                let pending = rest.pending, rest.recheck == nil, !sample.isInteracting,
                now - pending.since >= parameters.quietPeriod
            else {
                return []
            }
            let token = takeToken()
            rest.recheck = token
            phase = .resting(rest)
            return [.observe(token: token, length: rest.length)]
        }
    }

    // MARK: - Calibration

    private mutating func start(_ sample: IceBarHidingSample, now: Double) -> [IceBarHidingCommand] {
        guard !sample.isInteracting, sample.boundaryUsable, !sample.membership.members.isEmpty else { return [] }
        if let lastStart, now - lastStart < parameters.minInterval { return [] }
        lastStart = now
        let token = takeToken()
        phase = .baselining(token: token)
        return [.takeBaseline(token: token)]
    }

    private mutating func baselineTaken(token: Int, ok: Bool, now: Double) -> [IceBarHidingCommand] {
        guard phase == .baselining(token: token) else { return [] }
        anchor = lastGood
        // Without a baseline nothing can be walked towards: hide best effort (O1).
        guard ok else { return settle(at: bestEffortLength(after: []), kind: .final) }
        if let lastGood { return settle(at: lastGood, kind: .lastGood) }
        phase = .calibrating(observations: [], pending: nil, restedAt: now)
        return []
    }

    private mutating func observed(
        token: Int,
        checks: [ItemKey: SectionItemCheck],
        chevronListed: Bool?,
        now: Double
    ) -> [IceBarHidingCommand] {
        switch phase {
        case .settling(let trial, let kind) where trial.token == token:
            let outcome = outcome(of: checks)
            if kind == .lastGood, outcome != .hiddenClean {
                // No longer verified; the refused length is the walk's first observation.
                lastGood = nil
                let observation = HiddenLengthObservation(length: trial.length, outcome: outcome)
                phase = .calibrating(observations: [observation], pending: nil, restedAt: now)
                return [.setLength(nil)]
            }
            if outcome == .hiddenClean {
                lastGood = trial.length
                failures = 0
            }
            phase = .resting(Rest(length: trial.length, checks: checks, chevronListed: chevronListed, pending: nil, recheck: nil))
            return []
        case .calibrating(let observations, let trial?, _) where trial.token == token:
            let observation = HiddenLengthObservation(length: trial.length, outcome: outcome(of: checks))
            phase = .calibrating(observations: observations + [observation], pending: nil, restedAt: now)
            // Back to rest, so the next trial is again a jump from rest (T0).
            return [.setLength(nil)]
        case .resting(var rest) where rest.recheck == token:
            rest = Rest(length: rest.length, checks: checks, chevronListed: chevronListed, pending: nil, recheck: nil)
            phase = .resting(rest)
            return recycleIfDrawn(now: now)
        default:
            return []
        }
    }

    /// A member seen drawn at rest starts one new cycle, a bounded number of
    /// times; otherwise the rest stays and the state says `visibleFailed`.
    private mutating func recycleIfDrawn(now: Double) -> [IceBarHidingCommand] {
        guard case .state(.visibleFailed) = status, failures < parameters.maxFailures else { return [] }
        if let lastStart, now - lastStart < parameters.minInterval { return [] }
        failures += 1
        return enterQuiet(now)
    }

    private mutating func propose(after observations: [HiddenLengthObservation], now: Double) -> [IceBarHidingCommand] {
        let proposal = HiddenLengthCalibrator.next(
            observations: observations,
            lastGood: anchor,
            parameters: parameters.calibration
        )
        switch proposal {
        case .tryLength(let length):
            let trial = Trial(token: takeToken(), length: length)
            phase = .calibrating(observations: observations, pending: trial, restedAt: now)
            return [.setLength(length), .observe(token: trial.token, length: length)]
        case .rest(let length):
            return settle(at: length, kind: .final)
        case .giveUp:
            return settle(at: bestEffortLength(after: observations), kind: .final)
        }
    }

    /// The last verified length, else the midpoint of the lengths this walk
    /// saw every ready member absent at, else the calibration's first probe
    /// (O1: Ice applies some length when it cannot verify; D-d: that length
    /// is never a success unless its own observation verifies it).
    private func bestEffortLength(after observations: [HiddenLengthObservation]) -> Double {
        if let lastGood { return lastGood }
        let clean = observations.filter { $0.outcome == .hiddenClean }.map(\.length)
        if let lo = clean.min(), let hi = clean.max() { return (lo + hi) / 2 }
        return parameters.calibration.defaultStart
    }

    private mutating func settle(at length: Double, kind: SettleKind) -> [IceBarHidingCommand] {
        let trial = Trial(token: takeToken(), length: length)
        phase = .settling(trial, kind)
        return [.setLength(length), .observe(token: trial.token, length: length)]
    }

    /// The walk's outcome over the ready members: stale and stacked ones
    /// cap the state through the rule, they do not stop the walk.
    private func outcome(of checks: [ItemKey: SectionItemCheck]) -> HiddenLengthOutcome {
        let ready = (sample?.membership.members ?? []).filter { $0.condition == .ready }.compactMap(\.key)
        return HiddenLengthOutcomeRule.outcome(checks: ready.compactMap { checks[$0] }, memberCount: ready.count)
    }

    // MARK: - Transitions

    private mutating func enterQuiet(_ now: Double) -> [IceBarHidingCommand] {
        if case .quiet = phase { return [] }
        return restartQuiet(now)
    }

    private mutating func restartQuiet(_ now: Double) -> [IceBarHidingCommand] {
        let retire = lengthSet
        phase = .quiet(since: now)
        return retire ? [.setLength(nil)] : []
    }

    private mutating func enterBlocked() -> [IceBarHidingCommand] {
        let retire = lengthSet
        phase = .blocked
        return retire ? [.setLength(nil)] : []
    }

    private mutating func takeToken() -> Int {
        lastToken += 1
        return lastToken
    }
}
