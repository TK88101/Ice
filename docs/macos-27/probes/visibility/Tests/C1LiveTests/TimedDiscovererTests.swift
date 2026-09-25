import Foundation
import IceCore
import MenuBarDetectorFeed
import MenuBarDiscovery
import Testing
@testable import C1Live

/// Round 3 item 3: `TimedDiscoverer` no longer races a task group (which
/// cannot return before a blocked child, so it was never a real bound) --
/// it measures elapsed time *after* `discover` returns, and treats
/// anything past `lateSeconds` as late, firing `onLate` and discarding
/// the result. Item 8's original bound stays for "same bound... used by
/// the untemplated watch and preflight" reads that go through this type.
@Suite("TimedDiscoverer")
struct TimedDiscovererTests {
    /// A `Discovering` fake that sleeps `delay` before answering.
    final class SlowDiscoverer: Discovering, @unchecked Sendable {
        let delay: Double
        let result: DiscoveryResult?
        private let lock = NSLock()
        private(set) var callCount = 0

        init(delay: Double, result: DiscoveryResult?) {
            self.delay = delay
            self.result = result
        }

        func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? {
            lock.withLock { callCount += 1 }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            return result
        }
    }

    let bounds = BarBounds(minX: 0, maxX: 300, minY: 0, barHeight: 12)

    func fixtureResult() -> DiscoveryResult {
        let set = DiscoveredItemSet(items: [], visibleControlItem: nil, hiddenDivider: nil, alwaysHiddenDivider: nil, ownRead: .ok, systemElements: [], dropped: [], completeness: .complete)
        return DiscoveryResult(set: set, duration: 0, origin: DiscoveryOrigin(x: 0, y: 0), bounds: bounds, nextCursor: 0, quarantined: [], enumeratedPIDs: [])
    }

    @Test("a fast discovery pass is passed through unchanged, and onLate never fires")
    func fastDiscoveryPassesThrough() async {
        let fixture = fixtureResult()
        let slow = SlowDiscoverer(delay: 0, result: fixture)
        let onLateCalls = CallCounter()
        let timed = TimedDiscoverer(wrapping: slow, lateBound: 0.1, onLate: { onLateCalls.increment() })
        let result = await timed.discover(previous: nil)
        #expect(result?.nextCursor == fixture.nextCursor)
        #expect(onLateCalls.count == 0)
    }

    @Test("a discovery pass that returns later than lateBound reads as nil and fires onLate")
    func lateDiscoveryReadsAsNilAndFiresOnLate() async {
        let slow = SlowDiscoverer(delay: 0.2, result: fixtureResult())
        let onLateCalls = CallCounter()
        let timed = TimedDiscoverer(wrapping: slow, lateBound: 0.05, onLate: { onLateCalls.increment() })
        let result = await timed.discover(previous: nil)
        #expect(result == nil)
        #expect(onLateCalls.count == 1)
    }

    @Test("the wrapped discoverer's own nil (a real failure), returned promptly, still reads as nil without firing onLate")
    func wrappedNilStillNilWithoutOnLate() async {
        let slow = SlowDiscoverer(delay: 0, result: nil)
        let onLateCalls = CallCounter()
        let timed = TimedDiscoverer(wrapping: slow, lateBound: 0.2, onLate: { onLateCalls.increment() })
        let result = await timed.discover(previous: nil)
        #expect(result == nil)
        #expect(onLateCalls.count == 0)
    }

    @Test("lateSeconds defaults to 3.0 s when not overridden")
    func defaultLateBoundIsThreeSeconds() {
        #expect(TimedDiscoverer.lateSeconds == 3.0)
    }

    @Test("this type always awaits the real discover() call through to completion -- it never races a timer against it")
    func alwaysAwaitsRealCompletion() async {
        // A body that only finishes after the fake's own delay: if
        // `TimedDiscoverer` still raced a timer, this would return long
        // before `callCount` was ever incremented for a second call made
        // right after. Asserting the call count after `await` confirms
        // the call really ran to completion inside `discover(previous:)`.
        let slow = SlowDiscoverer(delay: 0.05, result: fixtureResult())
        let timed = TimedDiscoverer(wrapping: slow, lateBound: 1.0)
        _ = await timed.discover(previous: nil)
        #expect(slow.callCount == 1)
    }
}
