import Foundation
import IceCore
import MenuBarDetectorFeed
import MenuBarDiscovery
import Testing
@testable import C1Live

/// Item 8: "same bound for the keyed discovery reads used by the
/// untemplated watch and preflight." A discovery pass slower than
/// `TimedDiscoverer.boundSeconds` reads as `nil` -- a failure, exactly
/// like `TimedAXReader`'s bound for a single AX read.
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

    @Test("a fast discovery pass is passed through unchanged")
    func fastDiscoveryPassesThrough() async {
        let fixture = fixtureResult()
        let slow = SlowDiscoverer(delay: 0, result: fixture)
        let timed = TimedDiscoverer(wrapping: slow, bound: 0.2)
        let result = await timed.discover(previous: nil)
        #expect(result?.nextCursor == fixture.nextCursor)
    }

    @Test("a discovery pass slower than the bound reads as nil")
    func slowDiscoveryReadsAsNil() async {
        let slow = SlowDiscoverer(delay: 0.3, result: fixtureResult())
        let timed = TimedDiscoverer(wrapping: slow, bound: 0.05)
        let result = await timed.discover(previous: nil)
        #expect(result == nil)
    }

    @Test("the wrapped discoverer's own nil (a real failure) still reads as nil")
    func wrappedNilStillNil() async {
        let slow = SlowDiscoverer(delay: 0, result: nil)
        let timed = TimedDiscoverer(wrapping: slow, bound: 0.2)
        let result = await timed.discover(previous: nil)
        #expect(result == nil)
    }

    @Test("boundSeconds defaults to 1.0 s when not overridden")
    func defaultBoundIsOneSecond() {
        #expect(TimedDiscoverer.boundSeconds == 1.0)
    }
}
