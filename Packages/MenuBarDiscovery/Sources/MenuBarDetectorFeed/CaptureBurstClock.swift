import Foundation
import IceCore
import MenuBarCapture

/// `CaptureBurstRule` shared between the capturer that takes the captures and
/// the observer that decides when a session may start (plan
/// 2026-10-09-lab-first-run-followup, S3 design D2).
public final class CaptureBurstClock: @unchecked Sendable {
    /// The process's one clock: every live capturer reports to it, so the
    /// hiding check's captures and a new display's observer are not unknown
    /// to each other (Codex review, S3 round 2).
    public static let shared = CaptureBurstClock()

    private var rule: CaptureBurstRule
    private let lock = NSLock()

    public init(parameters: CaptureBurstParameters = .standard) {
        rule = CaptureBurstRule(parameters: parameters)
    }

    public func noteCapture(at now: Double) {
        lock.withLock { rule.noteCapture(at: now) }
    }

    public func closeBurst() {
        lock.withLock { rule.closeBurst() }
    }

    public func decision(for session: CaptureSession, now: Double) -> CaptureBurstDecision {
        lock.withLock { rule.decision(for: session, now: now) }
    }

    public var snapshot: CaptureBurstRule {
        lock.withLock { rule }
    }
}

/// A capturer that tells the clock of every capture it takes -- a preflight's
/// and a failed one's included: the system reacts to the attempt.
public struct BurstRecordingCapturer: StripCapturing {
    private let inner: any StripCapturing
    private let burst: CaptureBurstClock
    private let now: @Sendable () -> Double

    public init(
        wrapping inner: any StripCapturing,
        burst: CaptureBurstClock,
        now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.inner = inner
        self.burst = burst
        self.now = now
    }

    public func capture() -> StripImage? {
        burst.noteCapture(at: now())
        return inner.capture()
    }
}
