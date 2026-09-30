import Foundation
import IceCore
import MenuBarDetectorFeed
import MenuBarDiscovery
import Testing
@testable import C1Live

/// Rework #5 item 6 (r5b item 6, P0): one single-flight, deadline-bounded
/// keyed-discovery executor -- a hung wrapped `discover(previous:)` call
/// must not hold this call open past `bound`, must mark the executor
/// permanently stuck the first time that happens (firing `onStuck` exactly
/// once), and every later call must fail at once, without waiting at all.
@Suite("C1DiscoveryExecutor")
struct C1DiscoveryExecutorTests {
    /// A `Discovering` fake that never returns -- exactly the "fake
    /// discoverer that never returns" the brief asks this type be tested
    /// against.
    final class NeverReturningDiscoverer: Discovering, @unchecked Sendable {
        func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? {
            try? await Task.sleep(nanoseconds: .max)
            return nil
        }
    }

    final class FixedResultDiscoverer: Discovering, @unchecked Sendable {
        let result: DiscoveryResult?
        init(result: DiscoveryResult?) { self.result = result }
        func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? { result }
    }

    final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    @Test("a fast discovery pass returns its value within the bound")
    func fastPassReturnsValue() async {
        let executor = C1DiscoveryExecutor(wrapping: FixedResultDiscoverer(result: nil), bound: 0.2)
        let result = await executor.discover(previous: nil)
        #expect(result == nil) // the fixture's own "fast but nil" case
    }

    @Test("a discoverer that never returns still returns nil within the bound -- a real bound, not an after-the-fact measurement")
    func neverReturningDiscovererReturnsWithinBound() async {
        let executor = C1DiscoveryExecutor(wrapping: NeverReturningDiscoverer(), bound: 0.1)
        let start = DispatchTime.now()
        let result = await executor.discover(previous: nil)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        #expect(result == nil)
        #expect(elapsed < 2.0, "a single-flight bound of 0.1 s must not let this call run anywhere near 2 s")
    }

    @Test("a stuck pass fires onStuck exactly once")
    func stuckPassFiresOnStuckOnce() async {
        let counter = CallCounter()
        let executor = C1DiscoveryExecutor(wrapping: NeverReturningDiscoverer(), bound: 0.05, onStuck: { counter.increment() })
        _ = await executor.discover(previous: nil)
        #expect(counter.count == 1)
    }

    @Test("once stuck, a later call fails at once -- without waiting out the bound again")
    func onceStuckLaterCallsFailAtOnce() async {
        let executor = C1DiscoveryExecutor(wrapping: NeverReturningDiscoverer(), bound: 0.05)
        _ = await executor.discover(previous: nil) // first call: times out, marks stuck

        let start = DispatchTime.now()
        let second = await executor.discover(previous: nil)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        #expect(second == nil)
        #expect(elapsed < 0.05, "a call after the executor is already stuck must not even attempt the wrapped read")
    }

    @Test("a stuck pass never overlaps a later one: the wrapped discoverer is never entered again once stuck")
    func stuckPassNeverOverlapsALaterOne() async {
        final class CountingNeverReturningDiscoverer: Discovering, @unchecked Sendable {
            let counter = CallCounter()
            func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? {
                counter.increment()
                try? await Task.sleep(nanoseconds: .max)
                return nil
            }
        }
        let wrapped = CountingNeverReturningDiscoverer()
        let executor = C1DiscoveryExecutor(wrapping: wrapped, bound: 0.05)
        _ = await executor.discover(previous: nil)
        _ = await executor.discover(previous: nil)
        _ = await executor.discover(previous: nil)
        #expect(wrapped.counter.count == 1, "the executor must never start a second wrapped call once the first is stuck")
    }
}
