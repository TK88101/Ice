import Foundation
import IceCore
import MenuBarDetectorFeed
import MenuBarDiscovery

/// Rework #5 item 6 (r5b item 6, P0): one single-flight, deadline-bounded
/// keyed-discovery executor, replacing `TimedDiscoverer`'s after-the-fact
/// timing (it always awaited the real call to completion, then measured
/// how long that took -- never a real bound) and `blockingDiscover`'s
/// unbounded wait. Shaped after `C1AXExecutor` (item 2's stage-wide AX
/// executor): a hung wrapped call leaves this executor's own serial
/// queue permanently occupied, so no later call can ever start a second
/// wrapped read either -- structurally single-flight, not merely "bounded
/// on its own." The stage wires every keyed discovery read (the
/// untemplated watch, preflight's fresh pass, and the reap) through one
/// shared instance, exactly like `C1AXExecutor`.
public final class C1DiscoveryExecutor: Discovering, @unchecked Sendable {
    /// Comfortably above `MenuBarDiscoverer`'s own ~2 s per-pass deadline
    /// (plan section 4.1, "a deadline truncation"), matching
    /// `TimedDiscoverer.lateSeconds`.
    public static let boundSeconds = 3.0

    private let wrapped: any Discovering
    private let bound: Double
    private let onStuck: (@Sendable () -> Void)?
    private let queue = DispatchQueue(label: "com.icereverse.C1Live.C1DiscoveryExecutor", qos: .userInitiated)
    private let lock = NSLock()
    private var stuck = false

    public init(wrapping discoverer: any Discovering, bound: Double = C1DiscoveryExecutor.boundSeconds, onStuck: (@Sendable () -> Void)? = nil) {
        self.wrapped = discoverer
        self.bound = bound
        self.onStuck = onStuck
    }

    /// Fails at once, without submitting anything to the queue at all,
    /// once this executor is already stuck. Otherwise waits up to
    /// `bound`: a pass that does not finish in time marks the executor
    /// permanently stuck and fires `onStuck` -- once, the first time this
    /// happens -- before returning `nil`. The queue's own worker thread
    /// stays blocked on the hung pass forever in that case (the bridging
    /// semaphore below has no timeout of its own), which is exactly what
    /// keeps a second, later call from ever starting a second wrapped
    /// pass concurrently: `queue.async` cannot dequeue a new job while
    /// the stuck one still holds the only worker thread.
    public func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? {
        guard !(lock.withLock { stuck }) else { return nil }

        let box = C1DiscoveryResultBox()
        let outer = DispatchSemaphore(value: 0)
        queue.async { [wrapped] in
            let inner = DispatchSemaphore(value: 0)
            Task.detached {
                box.value = await wrapped.discover(previous: previous)
                inner.signal()
            }
            inner.wait()
            outer.signal()
        }
        guard Self.blockingWait(outer, timeout: .now() + bound) == .success else {
            let firstStuck = lock.withLock {
                let wasAlreadyStuck = stuck
                stuck = true
                return !wasAlreadyStuck
            }
            if firstStuck { onStuck?() }
            return nil
        }
        return box.value
    }

    /// `DispatchSemaphore.wait(timeout:)` is unavailable from a direct call
    /// inside an `async` function body (Swift flags it `noasync` to
    /// discourage blocking the cooperative pool); wrapping it in an
    /// ordinary synchronous function is the standard way to still use one
    /// deliberately, for this call's own bounded wait.
    private static func blockingWait(_ semaphore: DispatchSemaphore, timeout: DispatchTime) -> DispatchTimeoutResult {
        semaphore.wait(timeout: timeout)
    }
}

private final class C1DiscoveryResultBox: @unchecked Sendable {
    var value: DiscoveryResult?
}
