import C1Core
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery
@testable import C1Live

/// A capturer that returns a fixed, scripted sequence of results, one per
/// call -- the same shape as `MenuBarCaptureTests`' own fake (not
/// importable here: a sibling package's frozen test target), copied rather
/// than shared.
final class FakeStripCapturer: StripCapturing, @unchecked Sendable {
    private var results: [StripImage?]
    private let lock = NSLock()

    init(results: [StripImage?]) {
        self.results = results
    }

    func capture() -> StripImage? {
        lock.withLock {
            guard !results.isEmpty else { return nil }
            return results.removeFirst()
        }
    }
}

/// A `Discovering` fake driven by a scripted sequence of results, one per
/// call.
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

/// Records every command sent to it, in order -- I3/I5's shared testable
/// seam: "a channel protocol so a test can record them."
final class FakeC1HelperChannel: C1HelperChannel, @unchecked Sendable {
    enum Command: Equatable {
        case length(Double)
        case rest
        case quitAll
        case quitProtected
    }

    private let lock = NSLock()
    private var recorded = [Command]()

    var commands: [Command] { lock.withLock { recorded } }

    func sendLength(_ pt: Double) {
        lock.withLock { recorded.append(.length(pt)) }
    }

    func sendRest() {
        lock.withLock { recorded.append(.rest) }
    }

    func quitAll() {
        lock.withLock { recorded.append(.quitAll) }
    }

    /// F2: never called by I3's own tests (the trip-response contract is
    /// unchanged) -- present only so this fake still conforms.
    func quitProtected() {
        lock.withLock { recorded.append(.quitProtected) }
    }
}

/// A thread-safe counting box for closures that only need to record how
/// many times they were called.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

/// A thread-safe mutable box, for a `@Sendable` closure that needs to
/// record a value a captured `var` cannot (Swift 6 concurrency checking).
final class Box<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
}

let fixtureBounds = BarBounds(minX: 0, maxX: 300, minY: 0, barHeight: 12)

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

func fixtureSet(items: [DiscoveredItem], hiddenDivider: DividerReading? = nil, ownRead: OwnReadStatus = .ok) -> DiscoveredItemSet {
    DiscoveredItemSet(
        items: items, visibleControlItem: nil, hiddenDivider: hiddenDivider, alwaysHiddenDivider: nil,
        ownRead: ownRead, systemElements: [], dropped: [], completeness: .complete
    )
}

func fixtureDiscovery(set: DiscoveredItemSet, origin: DiscoveryOrigin = DiscoveryOrigin(x: 0, y: 0)) -> DiscoveryResult {
    DiscoveryResult(set: set, duration: 0, origin: origin, bounds: fixtureBounds, nextCursor: 0, quarantined: [], enumeratedPIDs: Set(set.listedItems.map(\.process.pid)))
}
