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
    /// for one roster and display; and, counted apart, the baselines Ice
    /// takes again after one that did not cover the members.
    public let maxFailures: Int
    /// How long the bar stays at standard length between two trials.
    public let restDwell: Double
    public let calibration: HiddenLengthParameters
    /// The longest a burst's first session may run, from the burst's start to
    /// its last capture, and still prove a rest: the capture indicator
    /// answers sessions of 4.2 s, not of 1.5 s (plan
    /// 2026-10-19-verify-in-a-clean-burst, D1).
    public let cleanBurstAge: Double

    public init(
        quietPeriod: Double,
        minInterval: Double,
        maxFailures: Int,
        restDwell: Double,
        calibration: HiddenLengthParameters,
        cleanBurstAge: Double = CaptureBurstParameters.standard.observationNeed
    ) {
        self.quietPeriod = quietPeriod
        self.minInterval = minInterval
        self.maxFailures = maxFailures
        self.restDwell = restDwell
        self.calibration = calibration
        self.cleanBurstAge = cleanBurstAge
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
    /// `PreferenceHidingRoster.signature`: every item read, the roster's
    /// tags, and what the bar is shown with.
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
    /// The answer to `observe(token:length:closesBurst:)`: each member's check
    /// at that length, whether `MenuBarAgent` listed a `«` (recorded only,
    /// D-b), and the burst it was read in (`nil`: not known).
    case observed(token: Int, checks: [ItemKey: SectionItemCheck], chevronListed: Bool?, burst: ObservationBurst?)
}

public enum IceBarHidingCommand: Equatable, Sendable {
    /// The hidden control item's length; `nil` is the standard length.
    case setLength(Double?)
    /// Take a baseline of the roster with the section shown: the members'
    /// tags, and the ready members' keys it must cover.
    case takeBaseline(token: Int, members: [TagKey], ready: [ItemKey])
    /// Check the members at the length the bar is now at. `closesBurst`: no
    /// later session may join the burst this one is read in (a settle, a
    /// confirmation, a re-check; plan 2026-10-19-verify-in-a-clean-burst, D4).
    case observe(token: Int, length: Double, closesBurst: Bool)
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
        /// As `final`, with no baseline to check against: one is owed.
        case unbaselined
    }

    /// A soft layout change the rest has not been re-checked after (D-e).
    public struct PendingChange: Equatable, Sendable {
        public let change: PreferenceHidingLayoutChange
        public let since: Double
        /// The token of the re-check under way.
        public var recheck: Int?
        public var confirm = ConfirmState()
    }

    /// Where a length that was seen to hide every ready member without
    /// proving it stands (plan 2026-10-19-verify-in-a-clean-burst, D2).
    public struct ConfirmState: Equatable, Sendable {
        /// The burst the last such reading was in: a confirmation in it proves nothing.
        public var candidateBurst: Int?
        /// Confirmations asked so far.
        public var tries = 0
    }

    /// A settle's length being confirmed.
    public struct Confirmation: Equatable, Sendable {
        public let trial: Trial
        public let kind: SettleKind
        public let confirm: ConfirmState
    }

    /// A length Ice keeps applied, and what it last saw there.
    public struct Rest: Equatable, Sendable {
        public let length: Double
        public var checks: [ItemKey: SectionItemCheck]
        public var chevronListed: Bool?
        public var pending: PendingChange?
        /// The baseline did not cover the members: this is a best-effort
        /// length (O1), and a new cycle is owed.
        public var baselineOwed = false
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
        /// The length stays; one more observation, in a burst of its own.
        case confirming(Confirmation)
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
    /// Cycles started because a baseline did not cover the members, since
    /// the roster or display last changed or a baseline last covered them.
    private var baselineRetries = 0
    private var lastStart: Double?
    private var lastToken = 0
    private var reported = IceBarHidingStatus.off

    public init(parameters: IceBarHidingParameters = .standard) {
        self.parameters = parameters
    }

    /// A length other than the standard one is set: what `blocked` and
    /// `quiet` must retire first.
    var lengthSet: Bool {
        switch phase {
        case .calibrating(_, let pending, _): pending != nil
        case .settling, .confirming, .resting: true
        case .off, .blocked, .quiet, .baselining: false
        }
    }

    /// A length is applied in the rule's sense: Ice rests at it. The IceBar
    /// is offered exactly then (not during a trial or a settle: a presented
    /// IceBar would end that observation).
    public var lengthApplied: Bool {
        length == .applied
    }

    /// A baseline or an observation the machine asked for is still wanted.
    /// When not, whatever work is under way answers nobody and must not go
    /// on capturing (plan 2026-10-09-lab-first-run-followup, S3 design D2).
    public var awaitsAnswer: Bool {
        switch phase {
        case .baselining, .settling, .confirming: true
        case .calibrating(_, let pending, _): pending != nil
        case .resting(let rest): rest.pending?.recheck != nil
        case .off, .blocked, .quiet: false
        }
    }

    /// The `«` reading of the rest's last observation; recorded, never acted on.
    public var chevronListed: Bool? {
        rest?.chevronListed
    }

    /// What the rule is told of the length: one Ice rests at, one being
    /// confirmed, or none.
    private var length: PreferenceHidingLength {
        switch phase {
        case .resting: .applied
        case .confirming: .confirming
        default: .notApplied
        }
    }

    private var rest: Rest? {
        if case .resting(let rest) = phase { rest } else { nil }
    }

    public var status: IceBarHidingStatus {
        if phase == .off { return .off }
        guard let sample else { return .state(.requestedNotVerified(reasons: [.lengthNotApplied])) }
        return .state(PreferenceHidingStateRule.evaluate(
            preconditions: sample.preconditions,
            membership: sample.membership,
            length: length,
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
        case .observed(let token, let checks, let chevronListed, let burst):
            return observed(token: token, checks: checks, chevronListed: chevronListed, burst: burst, now: now)
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
                baselineRetries = 0
                return enterQuiet(now)
            }
            guard case .resting(var rest) = phase else { return enterQuiet(now) }
            // D-e: the length stays; the checks are owed again.
            rest.pending = PendingChange(change: change, since: now)
            phase = .resting(rest)
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
        case .baselining, .settling, .confirming:
            return sample.isInteracting ? enterQuiet(now) : []
        case .calibrating(let observations, let pending, let restedAt):
            if sample.isInteracting { return enterQuiet(now) }
            guard pending == nil, now - restedAt >= parameters.restDwell else { return [] }
            return propose(after: observations, now: now)
        case .resting(var rest):
            if rest.baselineOwed, let retry = retryBaseline(now: now) { return retry }
            guard
                let pending = rest.pending, pending.recheck == nil, !sample.isInteracting,
                now - pending.since >= parameters.quietPeriod
            else {
                return []
            }
            let token = takeToken()
            rest.pending?.recheck = token
            phase = .resting(rest)
            return [.observe(token: token, length: rest.length, closesBurst: true)]
        }
    }

    // MARK: - Calibration

    private mutating func start(_ sample: IceBarHidingSample, now: Double) -> [IceBarHidingCommand] {
        guard !sample.isInteracting, sample.boundaryUsable, !sample.membership.members.isEmpty, !throttled(now) else { return [] }
        lastStart = now
        let token = takeToken()
        phase = .baselining(token: token)
        return [.takeBaseline(token: token, members: sample.membership.members.map(\.tag), ready: sample.membership.readyKeys)]
    }

    private mutating func baselineTaken(token: Int, ok: Bool, now: Double) -> [IceBarHidingCommand] {
        guard phase == .baselining(token: token) else { return [] }
        anchor = lastGood
        // Without a baseline nothing can be walked towards: hide best effort (O1).
        guard ok else { return settle(at: bestEffortLength(after: []), kind: .unbaselined) }
        baselineRetries = 0
        if let lastGood { return settle(at: lastGood, kind: .lastGood) }
        phase = .calibrating(observations: [], pending: nil, restedAt: now)
        return []
    }

    private mutating func observed(
        token: Int,
        checks: [ItemKey: SectionItemCheck],
        chevronListed: Bool?,
        burst: ObservationBurst?,
        now: Double
    ) -> [IceBarHidingCommand] {
        switch phase {
        case .settling(let trial, let kind) where trial.token == token:
            return settled(trial, kind, confirm: ConfirmState(), checks: checks, chevronListed: chevronListed, burst: burst, now: now)
        case .confirming(let confirmation) where confirmation.trial.token == token:
            return settled(
                confirmation.trial, confirmation.kind, confirm: confirmation.confirm,
                checks: checks, chevronListed: chevronListed, burst: burst, now: now
            )
        case .calibrating(let observations, let trial?, _) where trial.token == token:
            let observation = HiddenLengthObservation(length: trial.length, outcome: outcome(of: checks))
            phase = .calibrating(observations: observations + [observation], pending: nil, restedAt: now)
            // Back to rest, so the next trial is again a jump from rest (T0).
            return [.setLength(nil)]
        case .resting(var rest) where rest.pending?.recheck == token:
            if var pending = rest.pending, unproven(outcome(of: checks), burst: burst, besides: pending.confirm.candidateBurst) {
                guard let next = nextConfirmation(after: pending.confirm, burst: burst) else {
                    rest.checks = [:]
                    rest.chevronListed = chevronListed
                    rest.pending = nil
                    phase = .resting(rest)
                    return []
                }
                let recheck = takeToken()
                pending.recheck = recheck
                pending.confirm = next
                rest.pending = pending
                phase = .resting(rest)
                return [.observe(token: recheck, length: rest.length, closesBurst: true)]
            }
            rest.checks = checks
            rest.chevronListed = chevronListed
            rest.pending = nil
            phase = .resting(rest)
            return recycleIfDrawn(now: now)
        default:
            return []
        }
    }

    /// A settle's (or a confirmation's) observation. Every ready member
    /// absent rests only on a reading that proves it (D1); otherwise the
    /// length stays and is confirmed in a burst of its own, a bounded number
    /// of times, after which it rests unchecked (D2).
    private mutating func settled(
        _ trial: Trial,
        _ kind: SettleKind,
        confirm: ConfirmState,
        checks: [ItemKey: SectionItemCheck],
        chevronListed: Bool?,
        burst: ObservationBurst?,
        now: Double
    ) -> [IceBarHidingCommand] {
        let outcome = outcome(of: checks)
        if unproven(outcome, burst: burst, besides: confirm.candidateBurst) {
            guard let next = nextConfirmation(after: confirm, burst: burst) else {
                phase = .resting(Rest(
                    length: trial.length, checks: [:], chevronListed: chevronListed, pending: nil,
                    baselineOwed: kind == .unbaselined
                ))
                return []
            }
            let confirmation = Confirmation(trial: Trial(token: takeToken(), length: trial.length), kind: kind, confirm: next)
            phase = .confirming(confirmation)
            return [.observe(token: confirmation.trial.token, length: trial.length, closesBurst: true)]
        }
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
        phase = .resting(Rest(
            length: trial.length, checks: checks, chevronListed: chevronListed, pending: nil,
            baselineOwed: kind == .unbaselined
        ))
        return []
    }

    /// Every ready member seen absent by a reading that does not prove it
    /// (D1): the length is to be confirmed, not rested on.
    private func unproven(_ outcome: HiddenLengthOutcome, burst: ObservationBurst?, besides candidate: Int?) -> Bool {
        outcome == .hiddenClean && !proves(burst, besides: candidate)
    }

    /// One more confirmation after `state`, or `nil` once `maxFailures`
    /// have been asked: the rest then stands unchecked (D2).
    private func nextConfirmation(after state: ConfirmState, burst: ObservationBurst?) -> ConfirmState? {
        guard state.tries < parameters.maxFailures else { return nil }
        return ConfirmState(candidateBurst: burst?.burstID, tries: state.tries + 1)
    }

    /// Whether a reading proves what it saw: read as the first session of a
    /// burst other than `candidate`, within `cleanBurstAge` of its start (D1).
    private func proves(_ burst: ObservationBurst?, besides candidate: Int?) -> Bool {
        guard let burst, burst.ordinal == 1, burst.age <= parameters.cleanBurstAge else { return false }
        return burst.burstID != candidate
    }

    /// A member seen drawn at rest starts one new cycle, a bounded number of
    /// times; otherwise the rest stays and the state says `visibleFailed`.
    private mutating func recycleIfDrawn(now: Double) -> [IceBarHidingCommand] {
        guard case .state(.visibleFailed) = status, failures < parameters.maxFailures, !throttled(now) else { return [] }
        failures += 1
        return enterQuiet(now)
    }

    /// A baseline that covered nothing may have been cut on a bar another
    /// process had just captured (run 20261011-122641: an Ice started 20 s
    /// after the last capture of the one before it). The best-effort length
    /// stays until a new cycle may start; a bounded number of times.
    /// `nil` while no new cycle may start.
    private mutating func retryBaseline(now: Double) -> [IceBarHidingCommand]? {
        guard sample?.isInteracting == false, baselineRetries < parameters.maxFailures, !throttled(now) else { return nil }
        baselineRetries += 1
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
            return [.setLength(length), .observe(token: trial.token, length: length, closesBurst: false)]
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
        return [.setLength(length), .observe(token: trial.token, length: length, closesBurst: true)]
    }

    /// The walk's outcome over the ready members: stale and stacked ones
    /// cap the state through the rule, they do not stop the walk.
    private func outcome(of checks: [ItemKey: SectionItemCheck]) -> HiddenLengthOutcome {
        let ready = sample?.membership.readyKeys ?? []
        return HiddenLengthOutcomeRule.outcome(checks: ready.compactMap { checks[$0] }, memberCount: ready.count)
    }

    // MARK: - Transitions

    /// Quiet from now: a drag or a layout change while already quiet starts
    /// the period again (Codex review, T3b round 1).
    private mutating func enterQuiet(_ now: Double) -> [IceBarHidingCommand] {
        move(to: .quiet(since: now))
    }

    private mutating func enterBlocked() -> [IceBarHidingCommand] {
        move(to: .blocked)
    }

    /// Into a standard-length phase, retiring any length first.
    private mutating func move(to standardPhase: Phase) -> [IceBarHidingCommand] {
        let retire = lengthSet
        phase = standardPhase
        return retire ? [.setLength(nil)] : []
    }

    private func throttled(_ now: Double) -> Bool {
        lastStart.map { now - $0 < parameters.minInterval } ?? false
    }

    private mutating func takeToken() -> Int {
        lastToken += 1
        return lastToken
    }
}
