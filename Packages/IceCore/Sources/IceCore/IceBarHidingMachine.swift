/// D1's "when" (plan 2026-10-03-icebar-build, section 9.2): on macOS 27 in
/// IceBar mode, when Ice calibrates the hidden length, when it rests at one,
/// and every way it puts the section back on the bar instead. Pure: Ice feeds
/// events and executes the commands; nothing here touches the bar.

/// The machine's constants. INFERRED, to be judged in T7; none is a measurement
/// except the rest margin's basis (the capture indicator is about 20 pt).
public struct IceBarHidingParameters: Equatable, Sendable {
    /// How long a layout signature must stay unchanged before a calibration.
    public let quietPeriod: Double
    /// The least time between two calibration starts.
    public let minInterval: Double
    /// Failed calibrations for one signature before Ice stops trying.
    public let maxFailures: Int
    /// How far inside the clean band a rest length must lie, either side:
    /// observations are taken with the capture indicator up, the rest is not.
    public let restMargin: Double
    /// How long the bar stays at standard length between two trials.
    public let restDwell: Double
    /// How many signatures' lengths are remembered.
    public let maxCachedLengths: Int
    public let calibration: HiddenLengthParameters

    public init(
        quietPeriod: Double,
        minInterval: Double,
        maxFailures: Int,
        restMargin: Double,
        restDwell: Double,
        maxCachedLengths: Int,
        calibration: HiddenLengthParameters
    ) {
        self.quietPeriod = quietPeriod
        self.minInterval = minInterval
        self.maxFailures = maxFailures
        self.restMargin = restMargin
        self.restDwell = restDwell
        self.maxCachedLengths = maxCachedLengths
        self.calibration = calibration
    }

    public static let standard = IceBarHidingParameters(
        quietPeriod: 3,
        minInterval: 30,
        maxFailures: 3,
        restMargin: 32,
        restDwell: 1,
        maxCachedLengths: 64,
        calibration: .standard
    )
}

/// Why the hidden section is on the bar although IceBar mode is on.
public enum IceBarShownReason: Equatable, Sendable {
    /// The frontmost app's menus cross the notch.
    case longMenu
    /// The menu frame or the notch could not be read.
    case menuUnreadable
    /// The hidden section is empty.
    case noMembers
    /// A member, the baseline or a read could not be assessed.
    case cannotAssess
    /// The calibration ended without a length to rest at.
    case noCleanLength(HiddenLengthProposal.Reason)
    /// Too many failed calibrations for this layout.
    case unstableLayout
}

/// What the layout pane says (D4).
public enum IceBarHidingStatus: Equatable, Sendable {
    case off
    /// Waiting for a quiet bar, or calibrating.
    case checking
    /// The hidden section is hidden and the IceBar lists it.
    case active
    case shown(IceBarShownReason)

    /// The known limits, said with every line.
    static let limits = "Ice Bar on macOS 27 shows app icons, opens items with a left click, "
        + "and is not offered while the frontmost app's menus reach the notch."

    public var message: String? {
        let line: String
        switch self {
        case .off: return nil
        case .checking: line = "Ice Bar: checking whether the hidden items can be hidden cleanly"
        case .active: line = "Ice Bar active"
        case .shown(.longMenu): line = "Items shown: the frontmost app's menus reach the notch"
        case .shown(.menuUnreadable): line = "Items shown: the menus or the notch could not be read"
        case .shown(.noMembers): line = "Ice Bar: the hidden section is empty"
        case .shown(.cannotAssess): line = "Items shown: an item could not be assessed"
        case .shown(.noCleanLength): line = "Items shown: no clean hiding length found"
        case .shown(.unstableLayout): line = "Items shown: hiding kept failing for this layout"
        }
        return "\(line). \(Self.limits)"
    }
}

/// What Ice reads once a tick.
public struct IceBarHidingSample: Equatable, Sendable {
    public let signature: LayoutSignature
    public let menuVerdict: MenuWidthVerdict
    /// The mouse is in the menu bar, or the IceBar is presented.
    public let isInteracting: Bool
    /// A Command-drag of a menu bar item is under way.
    public let isDragging: Bool
    /// The hidden divider decided the sections in a cache pass since the
    /// length last became standard.
    public let boundaryUsable: Bool
    public let memberCount: Int

    public init(
        signature: LayoutSignature,
        menuVerdict: MenuWidthVerdict,
        isInteracting: Bool,
        isDragging: Bool,
        boundaryUsable: Bool,
        memberCount: Int
    ) {
        self.signature = signature
        self.menuVerdict = menuVerdict
        self.isInteracting = isInteracting
        self.isDragging = isDragging
        self.boundaryUsable = boundaryUsable
        self.memberCount = memberCount
    }
}

public enum IceBarHidingEvent: Equatable, Sendable {
    case mode(isIceBar: Bool)
    case sample(IceBarHidingSample)
    /// The answer to `takeBaseline(token:)`: whether every member has a shown
    /// baseline.
    case baseline(token: Int, ok: Bool)
    /// The answer to `observe(token:length:)`.
    case observed(token: Int, outcome: HiddenLengthOutcome)
    /// `MenuBarAgent` lists a `«` while resting.
    case chevronSeenAtRest
}

public enum IceBarHidingCommand: Equatable, Sendable {
    /// The hidden control item's length; `nil` is the standard length.
    case setLength(Double?)
    case takeBaseline(token: Int)
    /// Read the outcome of the length the bar is now at.
    case observe(token: Int, length: Double)
    case report(IceBarHidingStatus)
}

public struct IceBarHidingMachine: Equatable, Sendable {
    /// A length being observed, and the request it answers to.
    public struct Trial: Equatable, Sendable {
        public let token: Int
        public let length: Double
    }

    public enum Phase: Equatable, Sendable {
        /// Not IceBar mode.
        case off
        case shown(IceBarShownReason)
        /// Standard length, waiting for the layout to hold still.
        case quiet(since: Double)
        case baselining(token: Int)
        /// `pending` is the trial under way; without one the bar is at
        /// standard length since `restedAt`.
        case calibrating(observations: [HiddenLengthObservation], pending: Trial?, restedAt: Double)
        /// One observation of a length remembered for this signature.
        case confirming(Trial)
        case resting(length: Double)
    }

    public private(set) var phase = Phase.off

    /// The signature the current phase was entered with.
    private var signature: LayoutSignature?
    /// The length each signature last rested at.
    private var cache = [LayoutSignature: Double]()
    /// The latest length rested at, for any signature.
    private var lastGood: Double?
    /// Where the calibration under way anchors its grid.
    private var anchor: Double?
    /// Failed calibrations for the current signature.
    private var failures = 0
    private var lastStart: Double?
    private var lastToken = 0

    public init() {}

    var cachedLengthCount: Int { cache.count }

    /// The machine after `event`, and what Ice must do, in order.
    public func step(
        _ event: IceBarHidingEvent,
        now: Double,
        parameters: IceBarHidingParameters = .standard
    ) -> (machine: IceBarHidingMachine, commands: [IceBarHidingCommand]) {
        var next = self
        let commands = next.apply(event, now: now, parameters: parameters)
        return (next, commands)
    }

    private mutating func apply(
        _ event: IceBarHidingEvent,
        now: Double,
        parameters: IceBarHidingParameters
    ) -> [IceBarHidingCommand] {
        switch event {
        case .mode(let isIceBar):
            return setMode(isIceBar, now: now)
        case .sample(let sample):
            return phase == .off ? [] : handle(sample, now: now, parameters: parameters)
        case .baseline(let token, let ok):
            return baselineTaken(token: token, ok: ok, now: now, parameters: parameters)
        case .observed(let token, let outcome):
            return observed(token: token, outcome: outcome, now: now)
        case .chevronSeenAtRest:
            guard case .resting = phase else { return [] }
            forgetCachedLength()
            return enterQuiet(now)
        }
    }

    // MARK: - Mode and samples

    private mutating func setMode(_ isIceBar: Bool, now: Double) -> [IceBarHidingCommand] {
        switch (phase == .off, isIceBar) {
        case (true, true):
            phase = .quiet(since: now)
            return [.report(.checking)]
        case (false, false):
            // Tokens never restart: a late answer must not match a new request.
            let token = lastToken
            self = IceBarHidingMachine()
            lastToken = token
            return [.setLength(nil), .report(.off)]
        default:
            return []
        }
    }

    private mutating func handle(
        _ sample: IceBarHidingSample,
        now: Double,
        parameters: IceBarHidingParameters
    ) -> [IceBarHidingCommand] {
        var commands = [IceBarHidingCommand]()
        if signature != sample.signature {
            signature = sample.signature
            failures = 0
            commands += enterQuiet(now)
        }
        // The owner is arranging items: they need the real divider.
        if sample.isDragging { return commands + enterQuiet(now) }
        if let reason = Self.blocker(in: sample) { return commands + enterShown(reason) }
        return commands + advance(sample, now: now, parameters: parameters)
    }

    /// What makes hiding pointless or unreadable whatever the length.
    private static func blocker(in sample: IceBarHidingSample) -> IceBarShownReason? {
        switch sample.menuVerdict {
        case .crossesNotch: return .longMenu
        case .unreadable: return .menuUnreadable
        case .fits: return sample.memberCount == 0 ? .noMembers : nil
        }
    }

    private mutating func advance(
        _ sample: IceBarHidingSample,
        now: Double,
        parameters: IceBarHidingParameters
    ) -> [IceBarHidingCommand] {
        switch phase {
        case .off, .resting, .shown(.unstableLayout):
            return []
        case .shown(.longMenu), .shown(.menuUnreadable), .shown(.noMembers):
            // The blocker is gone.
            return enterQuiet(now)
        case .shown(.cannotAssess), .shown(.noCleanLength):
            return start(sample, now: now, parameters: parameters)
        case .quiet(let since):
            guard now - since >= parameters.quietPeriod else { return [] }
            return start(sample, now: now, parameters: parameters)
        case .baselining, .confirming:
            return sample.isInteracting ? enterQuiet(now) : []
        case .calibrating(let observations, let pending, let restedAt):
            if sample.isInteracting { return enterQuiet(now) }
            guard pending == nil, now - restedAt >= parameters.restDwell else { return [] }
            return propose(after: observations, now: now, parameters: parameters)
        }
    }

    // MARK: - Calibration

    private mutating func start(
        _ sample: IceBarHidingSample,
        now: Double,
        parameters: IceBarHidingParameters
    ) -> [IceBarHidingCommand] {
        guard !sample.isInteracting, sample.boundaryUsable else { return [] }
        if let lastStart, now - lastStart < parameters.minInterval { return [] }
        let wasShown: Bool = if case .shown = phase { true } else { false }
        lastStart = now
        let token = takeToken()
        phase = .baselining(token: token)
        return (wasShown ? [.report(.checking)] : []) + [.takeBaseline(token: token)]
    }

    private mutating func baselineTaken(
        token: Int,
        ok: Bool,
        now: Double,
        parameters: IceBarHidingParameters
    ) -> [IceBarHidingCommand] {
        guard phase == .baselining(token: token) else { return [] }
        guard ok else { return fail(.cannotAssess, parameters: parameters) }
        if let cached = signature.flatMap({ cache[$0] }) {
            anchor = cached
            let trial = Trial(token: takeToken(), length: cached)
            phase = .confirming(trial)
            return [.setLength(cached), .observe(token: trial.token, length: cached)]
        }
        anchor = lastGood
        phase = .calibrating(observations: [], pending: nil, restedAt: now)
        return []
    }

    private mutating func observed(token: Int, outcome: HiddenLengthOutcome, now: Double) -> [IceBarHidingCommand] {
        switch phase {
        case .confirming(let trial) where trial.token == token:
            if outcome == .hiddenClean {
                phase = .resting(length: trial.length)
                failures = 0
                return [.report(.active)]
            }
            // The refused length is the walk's first observation.
            forgetCachedLength()
            let observation = HiddenLengthObservation(length: trial.length, outcome: outcome)
            phase = .calibrating(observations: [observation], pending: nil, restedAt: now)
            return [.setLength(nil)]
        case .calibrating(let observations, let trial?, _) where trial.token == token:
            let observation = HiddenLengthObservation(length: trial.length, outcome: outcome)
            phase = .calibrating(observations: observations + [observation], pending: nil, restedAt: now)
            // Back to rest, so the next trial is again a jump from rest (T0).
            return [.setLength(nil)]
        default:
            return []
        }
    }

    private mutating func propose(
        after observations: [HiddenLengthObservation],
        now: Double,
        parameters: IceBarHidingParameters
    ) -> [IceBarHidingCommand] {
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
            let clean = observations.filter { $0.outcome == .hiddenClean }.map(\.length)
            guard
                let lo = clean.min(), let hi = clean.max(),
                length - lo >= parameters.restMargin, hi - length >= parameters.restMargin
            else {
                return fail(.noCleanLength(.noBand), parameters: parameters)
            }
            remember(length, parameters: parameters)
            phase = .resting(length: length)
            return [.setLength(length), .report(.active)]
        case .giveUp(let reason):
            return fail(reason == .unknownOutcome ? .cannotAssess : .noCleanLength(reason), parameters: parameters)
        }
    }

    // MARK: - Transitions

    private mutating func enterQuiet(_ now: Double) -> [IceBarHidingCommand] {
        let wasQuiet: Bool = if case .quiet = phase { true } else { false }
        phase = .quiet(since: now)
        return wasQuiet ? [] : [.setLength(nil), .report(.checking)]
    }

    private mutating func enterShown(_ reason: IceBarShownReason) -> [IceBarHidingCommand] {
        guard phase != .shown(reason) else { return [] }
        phase = .shown(reason)
        return [.setLength(nil), .report(.shown(reason))]
    }

    private mutating func fail(_ reason: IceBarShownReason, parameters: IceBarHidingParameters) -> [IceBarHidingCommand] {
        failures += 1
        return enterShown(failures >= parameters.maxFailures ? .unstableLayout : reason)
    }

    private mutating func remember(_ length: Double, parameters: IceBarHidingParameters) {
        guard let signature else { return }
        if cache.count >= parameters.maxCachedLengths { cache.removeAll() }
        cache[signature] = length
        lastGood = length
        failures = 0
    }

    private mutating func forgetCachedLength() {
        guard let signature else { return }
        cache[signature] = nil
    }

    private mutating func takeToken() -> Int {
        lastToken += 1
        return lastToken
    }
}
