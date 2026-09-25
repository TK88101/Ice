import Foundation
import IceCore
import MenuBarCapture
import Testing
@testable import C1Live

/// Item 8: an AX read slower than `TimedAXReader.boundSeconds` reads as a
/// failure (`nil`) -- a hung Accessibility call must not block the
/// `Sampler` (or anything downstream) indefinitely.
@Suite("TimedAXReader")
struct TimedAXReaderTests {
    /// A `MenuBarAXReading` fake that sleeps `delay` before answering.
    final class SlowAXReader: MenuBarAXReading, @unchecked Sendable {
        let delay: Double
        let result: MenuBarAXSnapshot?
        private(set) var callCount = 0
        private let lock = NSLock()

        init(delay: Double, result: MenuBarAXSnapshot? = MenuBarAXSnapshot(itemFrames: [:], agentFrames: [])) {
            self.delay = delay
            self.result = result
        }

        func read(items: [String: pid_t]) -> MenuBarAXSnapshot? {
            lock.withLock { callCount += 1 }
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            return result
        }
    }

    @Test("a read well within the bound is passed through unchanged")
    func fastReadPassesThrough() {
        let snapshot = MenuBarAXSnapshot(itemFrames: ["a": ItemFrame(id: "a", minX: 1, minY: 2, width: 3, height: 4)], agentFrames: [])
        let slow = SlowAXReader(delay: 0, result: snapshot)
        let timed = TimedAXReader(wrapping: slow, bound: 0.2)
        #expect(timed.read(items: [:]) == snapshot)
    }

    @Test("a read slower than the bound reads as nil")
    func slowReadReadsAsNil() {
        let slow = SlowAXReader(delay: 0.3)
        let timed = TimedAXReader(wrapping: slow, bound: 0.05)
        #expect(timed.read(items: [:]) == nil)
    }

    @Test("the wrapped reader's own nil (a real failure) still reads as nil")
    func wrappedNilStillNil() {
        let slow = SlowAXReader(delay: 0, result: nil)
        let timed = TimedAXReader(wrapping: slow, bound: 0.2)
        #expect(timed.read(items: [:]) == nil)
    }

    @Test("boundSeconds defaults to 1.0 s when not overridden")
    func defaultBoundIsOneSecond() {
        #expect(TimedAXReader.boundSeconds == 1.0)
    }

    @Test("items are forwarded to the wrapped reader unchanged")
    func itemsForwarded() {
        final class RecordingReader: MenuBarAXReading, @unchecked Sendable {
            let lock = NSLock()
            var seen: [String: pid_t]?
            func read(items: [String: pid_t]) -> MenuBarAXSnapshot? {
                lock.withLock { seen = items }
                return MenuBarAXSnapshot(itemFrames: [:], agentFrames: [])
            }
        }
        let recorder = RecordingReader()
        let timed = TimedAXReader(wrapping: recorder, bound: 0.2)
        _ = timed.read(items: ["vz-target": 123])
        #expect(recorder.seen == ["vz-target": 123])
    }
}
