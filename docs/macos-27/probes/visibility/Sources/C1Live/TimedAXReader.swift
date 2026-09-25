import Foundation
import MenuBarCapture

/// Item 8 (Codex round 2): "AX reads have no lateness bound. The sampler
/// blocks synchronously in `axReader.read`; a hung/late AX call cannot
/// feed the latch, rest the spacer, or terminate until the 15-minute
/// watchdog." Wraps another `MenuBarAXReading` and answers `nil` -- a
/// capture failure, which the stage feeds to the latch as an immediate
/// abort -- for any read that takes longer than `boundSeconds`.
public final class TimedAXReader: MenuBarAXReading, @unchecked Sendable {
    /// Generously above every measured per-element Accessibility timeout
    /// already in this probe (0.25 s, `StageRun`/`RawAX`/
    /// `LiveMenuBarAXReader`, several elements per read) while still far
    /// short of anything a live cycle can tolerate waiting on.
    public static let boundSeconds = 1.0

    private let wrapped: any MenuBarAXReading
    private let bound: Double
    private let queue = DispatchQueue(label: "com.icereverse.C1Live.TimedAXReader", qos: .userInitiated)

    public init(wrapping reader: any MenuBarAXReading, bound: Double = TimedAXReader.boundSeconds) {
        self.wrapped = reader
        self.bound = bound
    }

    /// Runs the real read on a background queue and waits at most `bound`
    /// for it. A read that never finishes leaves that one queue thread
    /// behind (no cancellation support to hand it), which is the same
    /// trade-off `Sampler`'s own bracket already accepts for a capture
    /// that hangs -- an AX call carries its own per-element messaging
    /// timeout, so this is a backstop, not a substitute for that.
    public func read(items: [String: pid_t]) -> MenuBarAXSnapshot? {
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        queue.async {
            box.value = self.wrapped.read(items: items)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + bound) == .success else {
            return nil
        }
        return box.value
    }

    private final class ResultBox: @unchecked Sendable {
        var value: MenuBarAXSnapshot?
    }
}
