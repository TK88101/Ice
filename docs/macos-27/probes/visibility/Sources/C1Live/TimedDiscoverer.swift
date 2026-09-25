import Foundation
import IceCore
import MenuBarDetectorFeed
import MenuBarDiscovery

/// Round 3 item 3: item 8's original `TimedDiscoverer` raced a task group
/// against a timer, but a `TaskGroup` cannot return until every child
/// task finishes -- if the wrapped discovery ignored cancellation while
/// blocked in AX, the timer "winning" `group.next()` never actually let
/// this function return early, so it was never a real bound at all.
///
/// This version never races anything: it always awaits the real
/// `discover(previous:)` call through to completion, then measures how
/// long that took. A pass slower than `lateSeconds` is treated as late --
/// its result is discarded and `onLate` fires -- exactly like a stuck AX
/// read (`C1AXExecutor`), just detected after the fact instead of by a
/// timeout racing the call itself.
public final class TimedDiscoverer: Discovering, @unchecked Sendable {
    /// `MenuBarDiscoverer` (T5) bounds one pass to its own ~2 s deadline
    /// internally, plus room for one AX call already in flight when that
    /// deadline lands (plan section 4.1, "a deadline truncation"; D19).
    /// 3.0 s is comfortably past both, so anything slower means the pass
    /// itself -- or something it called -- did not honor that contract.
    public static let lateSeconds = 3.0

    private let wrapped: any Discovering
    private let lateBound: Double
    private let onLate: (@Sendable () -> Void)?

    public init(wrapping discoverer: any Discovering, lateBound: Double = TimedDiscoverer.lateSeconds, onLate: (@Sendable () -> Void)? = nil) {
        self.wrapped = discoverer
        self.lateBound = lateBound
        self.onLate = onLate
    }

    public func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? {
        let start = DispatchTime.now()
        let result = await wrapped.discover(previous: previous)
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        guard elapsedSeconds <= lateBound else {
            onLate?()
            return nil
        }
        return result
    }
}
