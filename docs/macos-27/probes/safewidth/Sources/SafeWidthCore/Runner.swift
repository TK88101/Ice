// Runner: sequences one probe of an experiment that expands a spacer, captures
// repeatedly, lets a safety guard veto, and decides when the layout has settled.
// The real world (screen capture, accessibility, the spacer itself) sits behind
// the `World` protocol so this module can be driven, in tests, by a scripted fake.

/// One capture, fully assessed: its raw signature, the safety guard's verdict on
/// it, the settled sample it would contribute, and the void checks the runner
/// applies before anything else.
public struct Assessment: Equatable, Sendable {
    public var time: Double
    public var decision: GuardDecision
    public var signature: Signature
    public var sample: LegSample
    public var frontmostOK: Bool
    public var helpersAlive: Bool
    public var pillAXPresent: Bool?

    public init(
        time: Double,
        decision: GuardDecision,
        signature: Signature,
        sample: LegSample,
        frontmostOK: Bool,
        helpersAlive: Bool,
        pillAXPresent: Bool?
    ) {
        self.time = time
        self.decision = decision
        self.signature = signature
        self.sample = sample
        self.frontmostOK = frontmostOK
        self.helpersAlive = helpersAlive
        self.pillAXPresent = pillAXPresent
    }
}

/// The real world's surface, as `Runner` needs it: a clock, a way to move the
/// spacer, one capture-and-assess step, and a way to wait. Production code backs
/// this with screen capture and accessibility; tests back it with a scripted fake.
public protocol World: AnyObject {
    func now() -> Double
    /// Sets the spacer's length. `nil` means rest (no expansion).
    func setSpacer(_ length: Double?)
    /// One capture, plus AX and guard evaluation, for the spacer at `length`.
    /// `nil` means the capture failed or timed out.
    func assess(length: Double?) -> Assessment?
    func pause(_ seconds: Double)
}

/// Tuning for one `Runner`. All durations are seconds.
public struct RunnerConfig: Equatable, Sendable {
    /// How long to wait between captures.
    public var captureInterval: Double
    /// How long a run of matching captures must span to count as settled.
    public var settleSpan: Double
    /// How close two captures must be to count as matching.
    public var settleTolerance: Double
    /// How long to wait for settling before giving up.
    public var settleTimeout: Double
    /// How long to wait, after resting the spacer on harm, for a clean capture.
    public var restoreTimeout: Double
    /// How many consecutive failed captures end the probe.
    public var maxCaptureFailures: Int

    public init(
        captureInterval: Double,
        settleSpan: Double,
        settleTolerance: Double,
        settleTimeout: Double,
        restoreTimeout: Double,
        maxCaptureFailures: Int
    ) {
        self.captureInterval = captureInterval
        self.settleSpan = settleSpan
        self.settleTolerance = settleTolerance
        self.settleTimeout = settleTimeout
        self.restoreTimeout = restoreTimeout
        self.maxCaptureFailures = maxCaptureFailures
    }
}

/// Why a probe was voided: something changed that has nothing to do with the
/// spacer itself, so the capture it happened on tells us nothing.
public enum VoidReason: Equatable, Sendable {
    case focusLost
    case helperDied
    case pillToggled
}

/// What one probe of one spacer length concluded.
public enum ProbeOutcome: Equatable, Sendable {
    /// The layout settled. `sample` is the first settled capture's sample;
    /// `holds` has one entry per requested hold time, in ascending time order
    /// (not necessarily the order `holds` was passed to `probe` in).
    case settled(sample: LegSample, holds: [LegSample])
    /// The guard saw harm and the spacer was put back to rest. `restored` says
    /// whether a clean capture confirmed the rest within `restoreTimeout`.
    case harm(length: Double?, reasons: [GuardFinding], restored: Bool)
    /// The guard saw something unverifiable and ended the campaign.
    case stop(reasons: [GuardFinding])
    /// Something outside the spacer experiment changed; the capture is unusable.
    case void(VoidReason)
    /// The settle timeout elapsed before the layout ever settled.
    case unsettled(sample: LegSample?)
    /// Too many consecutive captures failed.
    case captureFailure
}

/// Runs one probe at a time against a `World`: expand (or rest) the spacer,
/// capture on an interval, let the guard veto, and report how it went.
public final class Runner {
    private let world: World
    private let config: RunnerConfig

    public init(world: World, config: RunnerConfig) {
        self.world = world
        self.config = config
    }

    /// Runs one probe at `length` (`nil` means rest). `holds` are seconds after
    /// the probe's start at which to also record the current sample; each is
    /// recorded as soon as that much time has elapsed, whether or not the
    /// layout has settled yet. They may be given in any order but are
    /// processed, and returned in `ProbeOutcome.settled`, in ascending order.
    /// `pillAtStart`, when non-nil, voids the probe the moment AX's pill
    /// presence stops matching it.
    public func probe(length: Double?, holds: [Double] = [], pillAtStart: Bool?) -> ProbeOutcome {
        for hold in holds {
            precondition(hold.isFinite && hold >= 0, "probe(holds:) must be finite and non-negative")
        }

        world.setSpacer(length)
        let t0 = world.now()
        var detector = SettleDetector(
            span: config.settleSpan,
            tolerance: config.settleTolerance,
            timeout: config.settleTimeout,
            start: t0
        )

        let sortedHolds = holds.sorted()
        var nextHoldIndex = 0
        var holdSamples: [LegSample] = []
        var settledSample: LegSample?
        var failureCount = 0

        func restIfNeeded() {
            guard length != nil else { return }
            world.setSpacer(nil)
        }

        while true {
            guard let a = world.assess(length: length) else {
                failureCount += 1
                if failureCount >= config.maxCaptureFailures {
                    restIfNeeded()
                    return .captureFailure
                }
                world.pause(config.captureInterval)
                continue
            }
            failureCount = 0

            // The guard's verdict is read before the void checks: a capture that
            // shows both a lost user item and a lost focus is a harm event, and
            // reporting it as a plain void would lose the one that matters.
            switch a.decision {
            case .restore(let reasons):
                restIfNeeded()
                let restored = waitRestored()
                return .harm(length: length, reasons: reasons, restored: restored)
            case .stop(let reasons):
                restIfNeeded()
                return .stop(reasons: reasons)
            case .suspect, .clean:
                break
            }

            if !a.frontmostOK {
                restIfNeeded()
                return .void(.focusLost)
            }
            if !a.helpersAlive {
                restIfNeeded()
                return .void(.helperDied)
            }
            if let pillAtStart, a.pillAXPresent != pillAtStart {
                restIfNeeded()
                return .void(.pillToggled)
            }

            let state = detector.add(a.signature, at: a.time)
            if settledSample == nil, state == .settled {
                settledSample = a.sample
            }

            while nextHoldIndex < sortedHolds.count, a.time - t0 >= sortedHolds[nextHoldIndex] {
                holdSamples.append(a.sample)
                nextHoldIndex += 1
            }

            if let settledSample, nextHoldIndex >= sortedHolds.count {
                return .settled(sample: settledSample, holds: holdSamples)
            }

            if settledSample == nil, state == .timedOut {
                restIfNeeded()
                return .unsettled(sample: a.sample)
            }

            world.pause(config.captureInterval)
        }
    }

    /// Rests the spacer: exactly `probe(length: nil, holds: [], pillAtStart:)`.
    public func rest(pillAtStart: Bool?) -> ProbeOutcome {
        probe(length: nil, holds: [], pillAtStart: pillAtStart)
    }

    /// Waits, polling at rest, for a clean capture to confirm the spacer
    /// actually rested. Returns false if `restoreTimeout` elapses first.
    private func waitRestored() -> Bool {
        let tRestore = world.now()
        while world.now() - tRestore < config.restoreTimeout {
            if let a = world.assess(length: nil), case .clean = a.decision {
                return true
            }
            world.pause(config.captureInterval)
        }
        return false
    }
}
