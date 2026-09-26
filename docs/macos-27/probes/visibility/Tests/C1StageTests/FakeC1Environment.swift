// I7: the fake `C1StageEnvironment` built from a `FakeBarWorld` -- every
// protocol `C1StageEnvironment.swift` declares, backed by the same world so
// the stage's real orchestration code can be driven end to end with no
// screen, no Accessibility, no real process and no real waiting.
import C1Live
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

    /// G5: the fake's own non-blocking form -- marks the helper down and
    /// logs it distinctly (`"\(role).quitRequested"`, not `"\(role).quit"`)
    /// so an I7 test can tell which quit path the stage actually took,
    /// without needing a real process to observe blocking on.
    func requestQuit() {
        lock.withLock { running = false }
        world.setDownNonBlocking(role)
    }
}

/// Every bundle validates and nothing is ever "already running" -- I7 never
/// touches a real bundle or `NSWorkspace`.
///
/// `onLaunch`, when supplied, fires synchronously right before this launch
/// does its own work -- scenario 6's own seam for "a signal during setup":
/// the closure calls the stage's own `signalReceived()` mid-launch, with no
/// change to any file outside this test target.
struct FakeHelperLauncher: C1HelperLaunching {
    let world: FakeBarWorld
    var onLaunch: (@Sendable (String) -> Void)?

    func validateBundle(at url: URL, expectedBundleID: String) -> Bool { true }
    func runningBundleIDs(among candidates: [String]) -> [String] { [] }

    func launch(appURL: URL, bundleID: String, role: String, arguments: [String], controllerPID: pid_t) -> (any C1HelperControlling)? {
        onLaunch?(role)
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

/// A mutable, weak hand-back to the `StageC1` an environment drives --
/// built before the stage exists (the environment is one of the stage's own
/// constructor arguments), filled in right after, so `FakeHelperLauncher`'s
/// `onLaunch` hook can call back into it. Weak: the box never keeps the
/// stage alive past the test's own reference to it.
final class StageHandback: @unchecked Sendable {
    weak var stage: StageC1?
}

/// Every helper domain reads back empty -- I7 never touches `defaults`.
struct FakeHelperDefaults: C1HelperDefaultsProviding {
    func forget(_ bundleID: String) -> Bool { true }
    func keys(_ bundleID: String) -> [String]? { [] }
}

/// `caffeinate`, when supplied, records whether it was still "running" at
/// the moment of every capture this world's own capturer takes -- G5's own
/// audit ("the fake caffeinate is still running during every teardown
/// capture and stopped exactly once before exit"). `nil` for any test that
/// does not care (every existing scenario before rework #7a).
struct FakeStripCapturer: StripCapturing {
    let world: FakeBarWorld
    var caffeinate: FakeCaffeinate?
    func capture() -> StripImage? {
        caffeinate?.recordCapture()
        return world.image()
    }
}

struct FakeAXReader: MenuBarAXReading {
    let world: FakeBarWorld
    func read(items: [String: pid_t]) -> MenuBarAXSnapshot? { world.axSnapshot(items: items) }
}

/// Rework #6a: sleeps a real, wall-clock 3.5 s -- past `C1DiscoveryExecutor`'s
/// own hard-coded 3.0 s bound -- once the "discovery timeout" knob is armed
/// (`FakeBarWorld.shouldHangDiscovery()`), so the executor's own real timeout
/// actually fires (see the knob's own doc comment: no source seam exists to
/// inject a shorter one). `Task.sleep`, not `Thread.sleep`: this is an
/// `async` function, and blocking a cooperative-pool thread here would be
/// its own bug.
struct FakeDiscoverer: Discovering {
    let world: FakeBarWorld
    func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? {
        if world.shouldHangDiscovery() {
            // G7: `world.hangDurationSeconds` (default 3.5 s, past the
            // live default's real 3.0 s bound) -- a test pairs this with a
            // short injected `discoveryExecutorBoundSeconds` instead.
            try? await Task.sleep(nanoseconds: UInt64(max(0, world.hangDurationSeconds) * 1_000_000_000))
        }
        return world.discoveryResult()
    }
}

/// A shared virtual clock (rework #6a: `VirtualClock`, owned by the
/// `FakeBarWorld` this pump's environment is built with -- see
/// `FakeC1EnvironmentFactory.make`): `sleep`/`run` advance it by exactly the
/// seconds asked for, and the world's own `image()`/`axSnapshot()`/
/// `discoveryResult()` advance it by their own measured/estimated latencies
/// (`SimulatedLatency`) -- so a scenario's simulated duration
/// (`clock.now()` before and after `stage.run()`) reflects the real number
/// of sleeps, captures, AX reads and discovery passes the stage actually
/// made, not a guess. `now()` itself never advances the clock (the old
/// per-call `+= 1` hack is gone): every real caller already sleeps between
/// samples (`Sampler`/`VisibilityObserver`, `IceReverse`'s own
/// `minSampleSpacing`), so nothing here needs it to. `blocking` bridges
/// into `Discovering`'s `async` calls with a plain semaphore, never
/// `RunLoop.main` (no test here runs on the main thread with a run loop to
/// pump).
final class FakePump: C1Pump, @unchecked Sendable {
    let clock: VirtualClock

    init(clock: VirtualClock) {
        self.clock = clock
    }

    func run(_ seconds: Double) { clock.advance(seconds) }

    func sleep(_ seconds: Double) { clock.advance(seconds) }

    func now() -> Double { clock.now() }

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
///
/// Rework #7a (G5 audit): also tracks whether it is currently "running,"
/// and (via `FakeStripCapturer.capture()`, when wired to it) logs that
/// state at the moment of every capture the stage takes -- amendment v7's
/// own requirement that `caffeinate` stop only "after every
/// verdict-deciding read... never by cleanup."
final class FakeCaffeinate: C1CaffeinateLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var running = false
    /// One entry per capture this world's `FakeStripCapturer` took (only
    /// when built with a reference to this instance), in order: `true`
    /// when `start()` had run and `stop()` had not, at that moment.
    private(set) var captureRunningLog: [Bool] = []

    func start() -> String? {
        lock.withLock { startCount += 1; running = true }
        return nil
    }

    func stop() {
        lock.withLock { stopCount += 1; running = false }
    }

    func recordCapture() {
        lock.withLock { captureRunningLog.append(running) }
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
    /// left unfaked. `onHelperLaunch`, when supplied, is scenario 6's own
    /// hook (`FakeHelperLauncher.onLaunch`).
    static func make(
        world: FakeBarWorld,
        evidence: FakeEvidence,
        caffeinate: FakeCaffeinate = FakeCaffeinate(),
        onHelperLaunch: (@Sendable (String) -> Void)? = nil,
        discoveryExecutorBoundSeconds: Double = C1DiscoveryExecutor.boundSeconds
    ) -> C1StageEnvironment {
        C1StageEnvironment(
            capturer: FakeStripCapturer(world: world, caffeinate: caffeinate),
            discoverer: FakeDiscoverer(world: world),
            ownerAXReaderFactory: { _ in FakeAXReader(world: world) },
            verificationAXReaderFactory: { _ in FakeAXReader(world: world) },
            geometryProvider: { FakeBarWorld.geometry },
            extrasScanner: {
                [C1ExtrasItem(bundleID: "com.apple.MenuBarAgent", minX: FakeBarWorld.indicatorX, minY: 0, width: FakeBarWorld.indicatorWidth, height: Double(FakeBarWorld.heightPt))]
            },
            helperLauncher: FakeHelperLauncher(world: world, onLaunch: onHelperLaunch),
            helperDefaults: FakeHelperDefaults(),
            pump: FakePump(clock: world.clock),
            caffeinate: caffeinate,
            evidenceFactory: FakeEvidenceFactory(evidence: evidence),
            isTrusted: { true },
            discoveryExecutorBoundSeconds: discoveryExecutorBoundSeconds
        )
    }
}
