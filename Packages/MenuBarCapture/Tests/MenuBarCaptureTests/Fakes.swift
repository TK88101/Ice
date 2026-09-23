import Darwin
@testable import MenuBarCapture
import IceCore

/// Records the order capture and AX-read calls happen in, across both fakes
/// below, so a test can assert the bracket's shape (capture, read, capture)
/// and not just its outcome. Test-only, single-threaded use.
final class OrderLog: @unchecked Sendable {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

/// A capturer that returns a fixed, scripted sequence of results, one per
/// call. Running out of scripted results reads as a failure (`nil`), never a
/// crash, so a test can under-supply results on purpose.
final class FakeStripCapturer: StripCapturing, @unchecked Sendable {
    private var results: [StripImage?]
    private let log: OrderLog?
    private(set) var callCount = 0

    init(results: [StripImage?], log: OrderLog? = nil) {
        self.results = results
        self.log = log
    }

    func capture() -> StripImage? {
        callCount += 1
        log?.record("capture")
        guard !results.isEmpty else { return nil }
        return results.removeFirst()
    }
}

/// An AX reader that returns a fixed, scripted sequence of results, and
/// records the `items` it was asked to read on each call.
final class FakeMenuBarAXReader: MenuBarAXReading, @unchecked Sendable {
    private var results: [MenuBarAXSnapshot?]
    private let log: OrderLog?
    private(set) var callCount = 0
    private(set) var requestedItems: [[String: pid_t]] = []

    init(results: [MenuBarAXSnapshot?], log: OrderLog? = nil) {
        self.results = results
        self.log = log
    }

    func read(items: [String: pid_t]) -> MenuBarAXSnapshot? {
        callCount += 1
        requestedItems.append(items)
        log?.record("read")
        guard !results.isEmpty else { return nil }
        return results.removeFirst()
    }
}

/// A deterministic clock: each read advances by `step`, so a test can predict
/// exactly how many samples span how much time without a real sleep.
final class FakeClock: @unchecked Sendable {
    private var t = 0.0
    private let step: Double

    init(step: Double) {
        self.step = step
    }

    func now() -> Double {
        defer { t += step }
        return t
    }
}
