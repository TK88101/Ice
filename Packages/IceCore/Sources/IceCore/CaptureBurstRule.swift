/// When Ice may capture the bar so that the system's capture indicator is not
/// in what it reads (plan 2026-10-09-lab-first-run-followup, S3 design D1).
///
/// Capturing summons a block into the bar, right of the third-party items,
/// which moves every item left of it 48 pt: about ten seconds after a
/// session's first capture, gone some twenty after its last
/// (docs/macos-27/FINDINGS.md, "The capture indicator, timed"). A baseline
/// cut before it and an observation read after it disagree about every
/// reference. So captures are taken in *bursts* that end before it can
/// arrive, and no burst begins until the last one's block has gone.

/// The policy's numbers: conservative on the two measured runs, not
/// measurements themselves.
public struct CaptureBurstParameters: Equatable, Sendable {
    /// Without a capture for this long, the bar is clear and the next capture
    /// begins a burst. Measured: block and clock shift gone within 20.5 s.
    public let clearAfter: Double
    /// How long after its first capture a burst may still be capturing.
    /// Measured: the block never sooner than 10.2 s.
    public let budget: Double
    /// What an observation must have left of the burst to start in it.
    public let observationNeed: Double

    public init(clearAfter: Double, budget: Double, observationNeed: Double) {
        self.clearAfter = clearAfter
        self.budget = budget
        self.observationNeed = observationNeed
    }

    public static let standard = CaptureBurstParameters(clearAfter: 22, budget: 8, observationNeed: 2.5)
}

public enum CaptureSession: Equatable, Sendable {
    case baseline
    case observation
    /// An observation a verdict may rest on: no later session joins its
    /// burst, closed as it is let start (plan
    /// 2026-10-19-verify-in-a-clean-burst, D4).
    case verdict
}

public enum CaptureBurstDecision: Equatable, Sendable {
    case go
    /// Not before this time: the bar is clear of the last capture then.
    case wait(until: Double)
}

/// A session's place in its burst, fixed when it was let start (plan
/// 2026-10-19-verify-in-a-clean-burst, D5).
public struct BurstSession: Equatable, Sendable {
    public let burstID: Int
    /// 1 for the burst's first session.
    public let ordinal: Int

    public init(burstID: Int, ordinal: Int) {
        self.burstID = burstID
        self.ordinal = ordinal
    }
}

/// The burst an observation was read in, fixed when its session ended: what
/// a verified rest stands on (D1).
public struct ObservationBurst: Equatable, Sendable {
    public let burstID: Int
    public let ordinal: Int
    public let burstStartedAt: Double
    /// The burst's last capture when the session ended.
    public let capturedAt: Double

    public init(burstID: Int, ordinal: Int, burstStartedAt: Double, capturedAt: Double) {
        self.burstID = burstID
        self.ordinal = ordinal
        self.burstStartedAt = burstStartedAt
        self.capturedAt = capturedAt
    }

    public var age: Double {
        capturedAt - burstStartedAt
    }
}

public enum CaptureBurstReservation: Equatable, Sendable {
    case go(BurstSession)
    case wait(until: Double)
}

public struct CaptureBurstRule: Equatable, Sendable {
    public let parameters: CaptureBurstParameters
    /// The first capture of the burst the last capture belongs to.
    public private(set) var burstStart: Double?
    public private(set) var lastCapture: Double?
    /// The burst takes no further session: a baseline was taken in it.
    public private(set) var isClosed = false
    /// Counts the bursts begun; the current one's number.
    public private(set) var burstID = 0
    /// The sessions the current burst has had, one opened by a capture
    /// outside any session included.
    public private(set) var sessions = 0

    public init(parameters: CaptureBurstParameters = .standard) {
        self.parameters = parameters
    }

    /// From the burst's first capture to the last capture taken.
    public var burstAge: Double? {
        guard let burstStart, let lastCapture else { return nil }
        return lastCapture - burstStart
    }

    /// Every capture actually taken, whoever asked for it.
    public mutating func noteCapture(at now: Double) {
        if isClear(at: now) {
            openBurst(at: now)
        }
        lastCapture = now
    }

    /// Lets `session` start if `decision` would, and reserves its place in
    /// the burst in the same step: on a clear bar it opens a burst at once,
    /// so its own first capture does not count as another session.
    public mutating func begin(_ session: CaptureSession, now: Double) -> CaptureBurstReservation {
        if case .wait(let until) = decision(for: session, now: now) {
            return .wait(until: until)
        }
        if isClear(at: now) {
            openBurst(at: now)
            lastCapture = now
        } else {
            sessions += 1
        }
        if session == .verdict {
            isClosed = true
        }
        return .go(BurstSession(burstID: burstID, ordinal: sessions))
    }

    /// The burst `session` was read in, as of now; `nil` once another burst
    /// has begun since.
    public func finish(_ session: BurstSession) -> ObservationBurst? {
        guard session.burstID == burstID, let burstStart, let lastCapture else { return nil }
        return ObservationBurst(
            burstID: session.burstID, ordinal: session.ordinal,
            burstStartedAt: burstStart, capturedAt: lastCapture
        )
    }

    private func isClear(at now: Double) -> Bool {
        lastCapture.map { now - $0 >= parameters.clearAfter } ?? true
    }

    private mutating func openBurst(at now: Double) {
        burstStart = now
        isClosed = false
        burstID += 1
        sessions = 1
    }

    /// A baseline has its burst to itself: called once its session is over.
    public mutating func closeBurst() {
        isClosed = true
    }

    /// A baseline starts only on a clear bar: what it does before its first
    /// capture (a discovery, a preflight) has no bound to fit a burst by.
    public func decision(for session: CaptureSession, now: Double) -> CaptureBurstDecision {
        guard let burstStart, let lastCapture else { return .go }
        let clearAt = lastCapture + parameters.clearAfter
        if now >= clearAt { return .go }
        let fits = session != .baseline && !isClosed && now + parameters.observationNeed <= burstStart + parameters.budget
        return fits ? .go : .wait(until: clearAt)
    }
}
