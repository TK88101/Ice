// I7: the fake `C1StageEnvironment` built from a `FakeBarWorld` -- every
// protocol `C1StageEnvironment.swift` declares, backed by the same world so
// the stage's real orchestration code can be driven end to end with no
// screen, no Accessibility, no real process and no real waiting.
import C1Stage
import Darwin
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

/// One launched (fake) helper: records every command sent to it and
/// answers `awaitReply("up", ...)` immediately -- no real process, no real
/// stdin/stdout.
final class FakeHelperControl: C1HelperControlling, @unchecked Sendable {
    let role: String
    let world: FakeBarWorld
    let pid: pid_t
    private let lock = NSLock()
    private var running = true

    init(role: String, pid: pid_t, world: FakeBarWorld) {
        self.role = role
        self.pid = pid
        self.world = world
    }

    var isRunning: Bool { lock.withLock { running } }

    func awaitReply(_ kind: String, timeout: Double) -> [String: Any]? {
        kind == "up" ? [:] : nil
    }

    func send(_ line: String) {
        guard isRunning else { return }
        world.handleCommand(line, role: role)
    }

    func quit(timeout: Double) {
        lock.withLock { running = false }
        world.setDown(role)
    }
}

/// Every bundle validates and nothing is ever "already running" -- I7 never
/// touches a real bundle or `NSWorkspace`.
struct FakeHelperLauncher: C1HelperLaunching {
    let world: FakeBarWorld

    func validateBundle(at url: URL, expectedBundleID: String) -> Bool { true }
    func runningBundleIDs(among candidates: [String]) -> [String] { [] }

    func launch(appURL: URL, bundleID: String, role: String, arguments: [String], controllerPID: pid_t) -> (any C1HelperControlling)? {
        let pid: pid_t
        switch role {
        case "reference": pid = FakeBarWorld.protectedPID
        case "spacer": pid = FakeBarWorld.spacerPID
        case "target": pid = FakeBarWorld.targetPID
        default: return nil
        }
        // vzhelper's own role names ("reference") differ from the world's
        // internal role names ("protected") only for Protected/spacer;
        // `worldRole` is what `FakeBarWorld.setUp`/`setDown` key on.
        let worldRole = role == "reference" ? "protected" : role
        world.setUp(worldRole)
        return FakeHelperControl(role: worldRole, pid: pid, world: world)
    }
}

/// Every helper domain reads back empty -- I7 never touches `defaults`.
struct FakeHelperDefaults: C1HelperDefaultsProviding {
    func forget(_ bundleID: String) -> Bool { true }
    func keys(_ bundleID: String) -> [String]? { [] }
}

struct FakeStripCapturer: StripCapturing {
    let world: FakeBarWorld
    func capture() -> StripImage? { world.image() }
}

struct FakeAXReader: MenuBarAXReading {
    let world: FakeBarWorld
    func read(items: [String: pid_t]) -> MenuBarAXSnapshot? { world.axSnapshot(items: items) }
}

struct FakeDiscoverer: Discovering {
    let world: FakeBarWorld
    func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? { world.discoveryResult() }
}

/// A shared virtual clock (`now()` advances by exactly 1 s every call,
/// matching `MenuBarDetectorFeedTests/Scenario.swift`'s own `FakeClock` --
/// enough to satisfy `DetectorParameters.preRegistered`'s
/// `baselineMinSamples`/`baselineMinSpan`/`minSampleSpacing` in the fewest
/// samples) and a no-op `sleep`/`run` -- nothing in I7 ever waits in real
/// time. `blocking` bridges into `Discovering`'s `async` calls with a plain
/// semaphore, never `RunLoop.main` (no test here runs on the main thread
/// with a run loop to pump).
final class FakePump: C1Pump, @unchecked Sendable {
    private let lock = NSLock()
    private var t: Double = 1000

    func run(_ seconds: Double) {}

    func sleep(_ seconds: Double) {}

    func now() -> Double {
        lock.withLock {
            defer { t += 1 }
            return t
        }
    }

    func blocking<T>(_ body: @escaping @Sendable () async -> T) -> T {
        let box = FakePumpResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await body()
            semaphore.signal()
        }
        semaphore.wait()
        return box.value!
    }
}

private final class FakePumpResultBox<T>: @unchecked Sendable {
    var value: T?
}

/// Records start/stop -- I7 never launches a real `caffeinate`.
final class FakeCaffeinate: C1CaffeinateLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() -> String? {
        lock.withLock { startCount += 1 }
        return nil
    }

    func stop() {
        lock.withLock { stopCount += 1 }
    }
}

/// An in-memory `C1EvidenceRecording` sink -- I7 asserts against `records`
/// instead of reading files under `~/IceReverse-evidence`.
final class FakeEvidence: C1EvidenceRecording, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var records: [(kind: String, fields: [String: Any])] = []
    private(set) var closed = false

    func record(_ kind: String, _ fields: [String: Any]) {
        lock.withLock { records.append((kind, fields)) }
    }

    @discardableResult
    func keep(_ image: StripImage, label: String) -> String? { nil }

    func close() {
        lock.withLock { closed = true }
    }

    /// The last `run.verdict` record's own `verdict` field -- I7's read of
    /// the actual `Verdict` the stage decided (`stage.run()`'s exit code
    /// alone cannot tell `.safetyStop` apart from
    /// `.safetyStopNeedingAttention`; both exit `3`).
    func lastVerdict() -> String? {
        lock.withLock { records.last(where: { $0.kind == "run.verdict" })?.fields["verdict"] as? String }
    }

    func allRecords() -> [(kind: String, fields: [String: Any])] {
        lock.withLock { records }
    }

    func terminalReasons() -> [String] {
        lock.withLock { records.filter { $0.kind == "terminal" }.compactMap { $0.fields["reason"] as? String } }
    }
}

struct FakeEvidenceFactory: C1EvidenceFactory {
    let evidence: FakeEvidence
    func makeEvidence(binaryURLs: [String: URL], arguments: [String], geometry: BarGeometry?, parameters: DetectorParameters, suffix: String) throws -> any C1EvidenceRecording {
        evidence
    }
}

enum FakeC1EnvironmentFactory {
    /// One real `C1StageEnvironment`, entirely backed by `world` and a
    /// fresh `FakePump`/`FakeCaffeinate`/`FakeEvidence` -- everything I7
    /// needs to drive the real `StageC1` orchestration with no live seam
    /// left unfaked.
    static func make(world: FakeBarWorld, evidence: FakeEvidence, caffeinate: FakeCaffeinate = FakeCaffeinate()) -> C1StageEnvironment {
        C1StageEnvironment(
            capturer: FakeStripCapturer(world: world),
            discoverer: FakeDiscoverer(world: world),
            ownerAXReaderFactory: { _ in FakeAXReader(world: world) },
            verificationAXReaderFactory: { _ in FakeAXReader(world: world) },
            geometryProvider: { FakeBarWorld.geometry },
            extrasScanner: {
                [C1ExtrasItem(bundleID: "com.apple.MenuBarAgent", minX: FakeBarWorld.indicatorX, minY: 0, width: FakeBarWorld.indicatorWidth, height: Double(FakeBarWorld.heightPt))]
            },
            helperLauncher: FakeHelperLauncher(world: world),
            helperDefaults: FakeHelperDefaults(),
            pump: FakePump(),
            caffeinate: caffeinate,
            evidenceFactory: FakeEvidenceFactory(evidence: evidence),
            isTrusted: { true }
        )
    }
}
