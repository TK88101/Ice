import Darwin
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDiscovery
@testable import MenuBarDetectorFeed

// MARK: - Copied from MenuBarCapture's test target
//
// `FakeStripCapturer`, `FakeMenuBarAXReader`, and `FakeClock` below are
// copied, unchanged, from
// `Packages/MenuBarCapture/Tests/MenuBarCaptureTests/Fakes.swift` -- a
// frozen package's test target, not importable from a sibling package's
// tests (plan section 4.3, "Test support").

/// A capturer that returns a fixed, scripted sequence of results, one per
/// call. Running out of scripted results reads as a failure (`nil`), never a
/// crash, so a test can under-supply results on purpose.
final class FakeStripCapturer: StripCapturing, @unchecked Sendable {
    private var results: [StripImage?]
    private let lock = NSLock()
    private(set) var callCount = 0
    private(set) var mainThreadCalls: [Bool] = []
    /// Called with the 1-based call index, outside the results lock, before
    /// a result is returned -- a test's hook for pausing a specific call
    /// (cancellation timing) or tracking concurrency (peak in-flight calls).
    private let onCall: (@Sendable (Int) -> Void)?
    private let tracker: ConcurrencyTracker?

    init(results: [StripImage?], onCall: (@Sendable (Int) -> Void)? = nil, tracker: ConcurrencyTracker? = nil) {
        self.results = results
        self.onCall = onCall
        self.tracker = tracker
    }

    func capture() -> StripImage? {
        tracker?.enter()
        defer { tracker?.leave() }
        let index: Int = lock.withLock {
            callCount += 1
            mainThreadCalls.append(Thread.isMainThread)
            return callCount
        }
        onCall?(index)
        return lock.withLock {
            guard !results.isEmpty else { return nil }
            return results.removeFirst()
        }
    }
}

/// An AX reader that returns a fixed, scripted sequence of results, and
/// records the `items` it was asked to read on each call.
final class FakeMenuBarAXReader: MenuBarAXReading, @unchecked Sendable {
    private var results: [MenuBarAXSnapshot?]
    private let lock = NSLock()
    private(set) var callCount = 0
    private(set) var requestedItems: [[String: pid_t]] = []
    private(set) var mainThreadCalls: [Bool] = []

    init(results: [MenuBarAXSnapshot?]) {
        self.results = results
    }

    func read(items: [String: pid_t]) -> MenuBarAXSnapshot? {
        lock.withLock {
            callCount += 1
            requestedItems.append(items)
            mainThreadCalls.append(Thread.isMainThread)
            guard !results.isEmpty else { return nil }
            return results.removeFirst()
        }
    }
}

/// A deterministic clock: each read advances by `step`, so a test can predict
/// exactly how many samples span how much time without a real sleep.
final class FakeClock: @unchecked Sendable {
    private var t = 0.0
    private let step: Double
    private let lock = NSLock()

    init(step: Double) {
        self.step = step
    }

    func now() -> Double {
        lock.withLock {
            defer { t += step }
            return t
        }
    }
}

// MARK: - New fakes for T7

/// A `Discovering` fake driven by a scripted sequence of results, one per
/// call -- the async twin of `FakeStripCapturer`/`FakeMenuBarAXReader`.
final class FakeDiscoverer: Discovering, @unchecked Sendable {
    private var results: [DiscoveryResult?]
    private let lock = NSLock()
    private(set) var callCount = 0

    init(results: [DiscoveryResult?]) {
        self.results = results
    }

    func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? {
        lock.withLock {
            callCount += 1
            guard !results.isEmpty else { return nil }
            return results.removeFirst()
        }
    }
}

/// Records how many capturer/reader calls are in flight at once, so a test
/// can assert peak concurrency (T7's "one session at a time").
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

/// A thread-safe counting box for `sleep`/other closures that only need to
/// record how many times they were called.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

/// `DispatchSemaphore.wait()` is unavailable from a direct call inside an
/// `async` function body (Swift flags it `noasync` to discourage blocking the
/// cooperative pool); wrapping it in an ordinary synchronous function is the
/// standard way to still use one deliberately, for a bounded test wait.
func blockingWait(_ semaphore: DispatchSemaphore) {
    semaphore.wait()
}

/// A thread-safe mutable box, used to let a test change what a `@Sendable`
/// seam closure (e.g. `HidingVerification`'s `geometry`) returns partway
/// through, without redeclaring the whole `HidingVerification`.
final class Box<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.withLock { value }
    }

    func set(_ newValue: Value) {
        lock.withLock { value = newValue }
    }
}

// MARK: - Shared item/set builders

let fixtureBounds = BarBounds(minX: 0, maxX: 300, minY: 0, barHeight: 12)

func fixtureDivider(minX: Double = 1, width: Double = 2) -> DividerReading {
    DividerReading.make(frame: BarRect(minX: minX, minY: 0, width: width, height: 12), in: fixtureBounds)
}

func fixtureItem(identifier: String, pid: Int32, minX: Double, width: Double = 9, basis: IdentityBasis = .declared, position: ItemPosition = .onBar) -> DiscoveredItem {
    let namespace = "com.example.p\(pid)"
    let key = ItemKey(namespace: namespace, identifier: identifier, pid: pid, childIndex: basis == .positional ? 0 : nil)
    return DiscoveredItem(
        key: key, basis: basis,
        process: ProcessInfoRecord(pid: pid, bundleID: namespace, localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
        frame: BarRect(minX: minX, minY: 0, width: width, height: 12), position: position,
        title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
    )
}

func fixtureSet(items: [DiscoveredItem], hiddenDivider: DividerReading? = fixtureDivider(), ownRead: OwnReadStatus = .ok) -> DiscoveredItemSet {
    DiscoveredItemSet(
        items: items, visibleControlItem: nil, hiddenDivider: hiddenDivider, alwaysHiddenDivider: nil,
        ownRead: ownRead, systemElements: [], dropped: [], completeness: .complete
    )
}

func fixtureDiscovery(set: DiscoveredItemSet, origin: DiscoveryOrigin = DiscoveryOrigin(x: 0, y: 0)) -> DiscoveryResult {
    DiscoveryResult(set: set, duration: 0, origin: origin, bounds: fixtureBounds, nextCursor: 0, quarantined: [])
}

// MARK: - Fakes for `DiscoveredFrameReader` (its own seams: `ExtrasReading`,
// `RunningAppsProviding`)

struct FakeRunningApps: RunningAppsProviding {
    let allProcesses: [ProcessInfoRecord]
    let agent: Int32?

    func processes() -> [ProcessInfoRecord] { allProcesses }
    func agentPID() -> Int32? { agent }
}

/// An `ExtrasReading` fake whose behaviour is entirely driven by a closure,
/// so individual tests can shape exactly what one pid's read produces.
final class FakeExtrasReader: ExtrasReading, @unchecked Sendable {
    private let handler: @Sendable (ProcessInfoRecord, Double) -> RawRead
    private let lock = NSLock()
    private(set) var calls: [ProcessInfoRecord] = []
    private(set) var interrupts: [Bool] = []

    init(handler: @escaping @Sendable (ProcessInfoRecord, Double) -> RawRead) {
        self.handler = handler
    }

    func read(_ process: ProcessInfoRecord, timeout: Double, interrupt: () -> Bool) -> RawRead {
        let interrupted = interrupt()
        lock.withLock {
            calls.append(process)
            interrupts.append(interrupted)
        }
        return handler(process, timeout)
    }

    var callCount: Int { lock.withLock { calls.count } }
}

func readerTestProcess(pid: Int32, isSelf: Bool = false) -> ProcessInfoRecord {
    ProcessInfoRecord(pid: pid, bundleID: "com.example.p\(pid)", localizedName: nil, executableName: nil, launchTime: nil, isSelf: isSelf)
}

func readerOK(_ value: String = "") -> AttributeRead<String> {
    AttributeRead(value: value, error: "success")
}

func readerOKFrame(_ value: BarRect) -> AttributeRead<BarRect> {
    AttributeRead(value: value, error: "success")
}

func readerExtrasRecord(childIndex: Int, identifier: String, minX: Double, width: Double = 24, hasFrame: Bool = true, role: String = "AXMenuBarItem") -> ExtrasRecord {
    ExtrasRecord(
        childIndex: childIndex,
        role: readerOK(role),
        identifier: readerOK(identifier),
        title: readerOK(),
        description: readerOK(),
        help: readerOK(),
        frame: hasFrame ? readerOKFrame(BarRect(minX: minX, minY: 4.5, width: width, height: 24)) : AttributeRead(value: nil, error: "noValue")
    )
}

func readerRawRead(process: ProcessInfoRecord, records: [ExtrasRecord] = []) -> RawRead {
    RawRead(process: process, extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: records, walkInterrupted: false, childCount: records.count)
}

func readerFailedRawRead(process: ProcessInfoRecord) -> RawRead {
    RawRead(process: process, extrasError: "cannotComplete", extrasElapsed: 0.24, childrenError: nil, childrenElapsed: nil, records: [], walkInterrupted: false, childCount: 0)
}

/// An `ExtrasReading` fake that asks `interrupt` once before its handler runs
/// and once after, per call -- so a test whose handler moves a clock can see
/// what the reader's interrupt answered on each side of that move (H1, f4).
final class PollingExtrasReader: ExtrasReading, @unchecked Sendable {
    struct Poll: Equatable {
        let pid: Int32
        let before: Bool
        let after: Bool
    }

    private let handler: @Sendable (ProcessInfoRecord) -> RawRead
    private let lock = NSLock()
    private var recorded: [Poll] = []

    init(handler: @escaping @Sendable (ProcessInfoRecord) -> RawRead) {
        self.handler = handler
    }

    func read(_ process: ProcessInfoRecord, timeout: Double, interrupt: () -> Bool) -> RawRead {
        let before = interrupt()
        let raw = handler(process)
        let after = interrupt()
        lock.withLock { recorded.append(Poll(pid: process.pid, before: before, after: after)) }
        return raw
    }

    var polls: [Poll] { lock.withLock { recorded } }
}
