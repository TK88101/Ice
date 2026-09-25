import Foundation
import IceCore
import MenuBarCapture
import Testing
@testable import C1Live

/// Round 3 item 2: one stage-wide serial AX executor, not a per-instance
/// timed reader. A read that does not finish within the bound marks the
/// executor permanently stuck and fires `onStuck` synchronously; every
/// later read then fails at once, without even attempting the real read;
/// and because the executor's own queue is serial, no two reads through
/// it ever run at the same time.
@Suite("C1AXExecutor")
struct C1AXExecutorTests {
    @Test("a read well within the bound returns its value")
    func fastReadReturnsValue() {
        let executor = C1AXExecutor(bound: 0.2)
        let result = executor.run { 42 }
        #expect(result == 42)
    }

    @Test("a read slower than the bound returns nil")
    func slowReadReturnsNil() {
        let executor = C1AXExecutor(bound: 0.05)
        let result: Int? = executor.run {
            Thread.sleep(forTimeInterval: 0.3)
            return 42
        }
        #expect(result == nil)
    }

    @Test("a stuck read fires onStuck exactly once, synchronously with the caller observing nil")
    func stuckReadFiresOnStuckOnce() {
        let onStuckCalls = CallCounter()
        let executor = C1AXExecutor(bound: 0.05, onStuck: { onStuckCalls.increment() })
        _ = executor.run { Thread.sleep(forTimeInterval: 0.3); return 1 }
        #expect(onStuckCalls.count == 1)
    }

    @Test("once stuck, a later read fails at once, without even running its body")
    func laterReadFailsAtOnceOnceStuck() {
        let executor = C1AXExecutor(bound: 0.05, onStuck: nil)
        _ = executor.run { Thread.sleep(forTimeInterval: 0.3); return 1 }
        let bodyRan = CallCounter()
        let start = DispatchTime.now()
        let result: Int? = executor.run {
            bodyRan.increment()
            return 2
        }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        #expect(result == nil)
        #expect(bodyRan.count == 0)
        #expect(elapsedMs < 50) // fails immediately, not after another bound-length wait
    }

    @Test("onStuck fires only once even if more reads are attempted after the executor is stuck")
    func onStuckFiresOnlyOnce() {
        let onStuckCalls = CallCounter()
        let executor = C1AXExecutor(bound: 0.05, onStuck: { onStuckCalls.increment() })
        _ = executor.run { Thread.sleep(forTimeInterval: 0.3); return 1 }
        let result: Int? = executor.run { 2 }
        #expect(result == nil)
        #expect(onStuckCalls.count == 1)
    }

    @Test("boundSeconds defaults to 1.0 s when not overridden")
    func defaultBoundIsOneSecond() {
        #expect(C1AXExecutor.boundSeconds == 1.0)
    }

    @Test("two reads through the same executor never run at the same time -- the second only starts once the first's slot is free")
    func readsNeverOverlap() {
        let executor = C1AXExecutor(bound: 1.0)
        let overlap = ConcurrencyTracker()
        let group = DispatchGroup()
        for _ in 0..<5 {
            group.enter()
            DispatchQueue.global().async {
                _ = executor.run {
                    overlap.enter()
                    Thread.sleep(forTimeInterval: 0.02)
                    overlap.leave()
                    return 1
                }
                group.leave()
            }
        }
        group.wait()
        #expect(overlap.peak == 1)
    }
}

/// Records how many bodies are in flight at once, so a test can assert
/// peak concurrency stayed at 1 (serialized).
final class ConcurrencyTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private(set) var peak = 0

    func enter() {
        lock.withLock {
            current += 1
            peak = max(peak, current)
        }
    }

    func leave() {
        lock.withLock { current -= 1 }
    }
}
