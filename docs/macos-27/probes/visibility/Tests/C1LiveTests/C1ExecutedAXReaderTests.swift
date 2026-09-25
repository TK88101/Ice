import Foundation
import IceCore
import MenuBarCapture
import Testing
@testable import C1Live

/// `C1ExecutedAXReader`: the `MenuBarAXReading` adapter that routes one
/// reader's calls through a shared `C1AXExecutor`, so several readers
/// (the owner observer's, `HidingVerification`'s own) can still be
/// serialized on one stage-wide executor.
@Suite("C1ExecutedAXReader")
struct C1ExecutedAXReaderTests {
    final class RecordingReader: MenuBarAXReading, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var calls: [[String: pid_t]] = []
        let result: MenuBarAXSnapshot?
        let delay: Double

        init(result: MenuBarAXSnapshot?, delay: Double = 0) {
            self.result = result
            self.delay = delay
        }

        func read(items: [String: pid_t]) -> MenuBarAXSnapshot? {
            lock.withLock { calls.append(items) }
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            return result
        }
    }

    @Test("a fast read is forwarded to the wrapped reader and its result returned")
    func fastReadForwarded() {
        let snapshot = MenuBarAXSnapshot(itemFrames: [:], agentFrames: [])
        let recorder = RecordingReader(result: snapshot)
        let executor = C1AXExecutor(bound: 0.2)
        let reader = C1ExecutedAXReader(executor: executor, wrapping: recorder)
        #expect(reader.read(items: ["a": 1]) == snapshot)
        #expect(recorder.calls == [["a": 1]])
    }

    @Test("a slow read reads as nil and marks the shared executor stuck for a second reader too")
    func slowReadStucksTheSharedExecutor() {
        let slow = RecordingReader(result: MenuBarAXSnapshot(itemFrames: [:], agentFrames: []), delay: 0.3)
        let fast = RecordingReader(result: MenuBarAXSnapshot(itemFrames: [:], agentFrames: []))
        let onStuckCalls = CallCounter()
        let executor = C1AXExecutor(bound: 0.05, onStuck: { onStuckCalls.increment() })
        let slowReader = C1ExecutedAXReader(executor: executor, wrapping: slow)
        let fastReader = C1ExecutedAXReader(executor: executor, wrapping: fast)

        #expect(slowReader.read(items: [:]) == nil)
        #expect(onStuckCalls.count == 1)
        // A different reader sharing the same executor is stuck too.
        #expect(fastReader.read(items: [:]) == nil)
        #expect(fast.calls.isEmpty)
    }
}
