import Foundation
import IceCore
@testable import MenuBarDiscovery

/// A manually-advanced clock, `Sendable` and lock-protected so a fake reader
/// running on `MenuBarDiscoverer`'s own queue can advance it as a side effect
/// of being called (T5's deadline test: "a fake reader that advances the fake
/// clock by 0.5 s per process").
final class ManualClock: @unchecked Sendable {
    private var value: Double
    private let lock = NSLock()

    init(_ value: Double = 0) {
        self.value = value
    }

    func now() -> Double {
        lock.withLock { value }
    }

    func advance(by delta: Double) {
        lock.withLock { value += delta }
    }
}

/// A thread-safe box, used by fakes and tests to record call order, thread
/// identity, and similar observations without touching `@Test` isolation.
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

    func mutate(_ body: (inout Value) -> Void) {
        lock.withLock { body(&value) }
    }
}

struct FakeRunningApps: RunningAppsProviding {
    let allProcesses: [ProcessInfoRecord]
    let agent: Int32?

    func processes() -> [ProcessInfoRecord] { allProcesses }
    func agentPID() -> Int32? { agent }
}

/// A fake `ExtrasReading` whose behaviour is entirely driven by a closure, so
/// individual tests can shape exactly what happens per call (advance a clock,
/// record the calling thread, return a canned `RawRead`) without a new type
/// per scenario.
final class FakeExtrasReader: ExtrasReading, @unchecked Sendable {
    private let handler: @Sendable (ProcessInfoRecord, Double) -> RawRead
    private let lock = NSLock()
    private var calls: [ProcessInfoRecord] = []
    private var callThreads: [Bool] = []

    init(handler: @escaping @Sendable (ProcessInfoRecord, Double) -> RawRead) {
        self.handler = handler
    }

    func read(_ process: ProcessInfoRecord, timeout: Double) -> RawRead {
        lock.withLock {
            calls.append(process)
            callThreads.append(Thread.isMainThread)
        }
        return handler(process, timeout)
    }

    var callCount: Int {
        lock.withLock { calls.count }
    }

    var recordedProcesses: [ProcessInfoRecord] {
        lock.withLock { calls }
    }

    /// `true` for every call made from the main thread -- T5's "never runs on
    /// the main thread" test expects this to be empty.
    var mainThreadCalls: [Bool] {
        lock.withLock { callThreads.filter { $0 } }
    }
}

struct FakeDisplay: DisplayProviding {
    let result: (bounds: BarBounds, origin: DiscoveryOrigin)?

    func bar() -> (bounds: BarBounds, origin: DiscoveryOrigin)? { result }
}

// MARK: - Shared fixtures

func testProcess(pid: Int32, bundleID: String? = nil, isSelf: Bool = false, launchTime: Double? = nil) -> ProcessInfoRecord {
    ProcessInfoRecord(pid: pid, bundleID: bundleID ?? "com.example.p\(pid)", localizedName: nil, executableName: nil, launchTime: launchTime, isSelf: isSelf)
}

func ok(_ value: String = "") -> AttributeRead<String> {
    AttributeRead(value: value, error: "success")
}

func okFrame(_ value: BarRect) -> AttributeRead<BarRect> {
    AttributeRead(value: value, error: "success")
}

func extrasRecord(childIndex: Int, identifier: String, minX: Double, role: String = "AXMenuBarItem") -> ExtrasRecord {
    ExtrasRecord(
        childIndex: childIndex,
        role: ok(role),
        identifier: ok(identifier),
        title: ok(),
        description: ok(),
        help: ok(),
        frame: okFrame(BarRect(minX: minX, minY: 4.5, width: 24, height: 24))
    )
}

func rawRead(process: ProcessInfoRecord, records: [ExtrasRecord] = []) -> RawRead {
    RawRead(process: process, extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: records)
}

let testBounds = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 24)
let testOwnIdentifiers = OwnIdentifiers(visible: "Ice.ControlItem.Visible", hidden: "Ice.ControlItem.Hidden", alwaysHidden: "Ice.ControlItem.AlwaysHidden")
