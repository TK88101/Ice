// Rework #5, step A: the seams `StageC1*.swift` needs so a test target can
// drive the real orchestration (I7) with fakes. Every field here replaces a
// concrete live/AppKit/Accessibility call the old `Sources/vizprobe`
// versions of these files made directly -- this target imports neither
// AppKit nor ApplicationServices; `vizprobe` builds the one real
// `C1StageEnvironment` (see `Sources/vizprobe/StageC1Live.swift`) and hands
// it to `StageC1.init(environment:apps:dry:)`.
import C1Live
import Darwin
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

/// One running helper process's control surface -- everything `StageC1*`
/// needs from a launched vzhelper, without depending on `Foundation.Process`
/// or vzhelper's own stdin/stdout plumbing (`Sources/vizprobe/HelperControl.swift`,
/// unmoved: this is a protocol in front of it, per the brief).
public protocol C1HelperControlling: AnyObject, Sendable {
    var pid: pid_t { get }
    var isRunning: Bool { get }
    /// The next reply line whose first word is `kind`, parsed as JSON, or
    /// `nil` after `timeout` seconds.
    func awaitReply(_ kind: String, timeout: Double) -> [String: Any]?
    /// Sends one control line (`length <pt>`, `rest`, `hide`, `show`) if the
    /// helper is still running; otherwise a no-op.
    func send(_ line: String)
    /// Closes the helper's stdin (its own quit signal) and waits up to
    /// `timeout` before forcing the issue.
    func quit(timeout: Double)
    /// G5 (Amendment v7): closes the helper's stdin (the same EOF quit
    /// signal `quit(timeout:)` sends) and returns immediately, without
    /// waiting or forcing the issue -- the only quit request safe to issue
    /// off the main thread, where a thread-safe rest and a *non-blocking*
    /// quit request are the only cleanup this stage may do (`perform(_:)`,
    /// `StageC1.swift`). The main-thread teardown's own confirmed reap
    /// (`confirmNonProtectedReap()`/`confirmProtectedReap()`) always
    /// re-issues the real, discovery-confirmed quit afterward regardless.
    func requestQuit()
}

extension C1HelperControlling {
    func quit() { quit(timeout: 2) }
}

/// Launches and validates the three C1 helpers (step0Bundles/step2Launch),
/// and answers "is a helper under this bundle id already running" -- the
/// one AppKit-touching check (`NSWorkspace.shared.runningApplications`) step0
/// makes today.
public protocol C1HelperLaunching: Sendable {
    /// Whether `url` is a bundle carrying `expectedBundleID` with an
    /// executable `Contents/MacOS/vzhelper` inside it.
    func validateBundle(at url: URL, expectedBundleID: String) -> Bool
    /// Bundle ids, among `candidates`, that currently have at least one
    /// running process.
    func runningBundleIDs(among candidates: [String]) -> [String]
    /// `nil` on any launch failure (no executable, spawn failed).
    func launch(appURL: URL, bundleID: String, role: String, arguments: [String], controllerPID: pid_t) -> (any C1HelperControlling)?
}

/// A helper's macOS preference domain (`defaults delete`/`defaults export`,
/// `Sources/vizprobe/HelperControl.swift`'s `HelperDefaults` enum, unmoved).
public protocol C1HelperDefaultsProviding: Sendable {
    @discardableResult
    func forget(_ bundleID: String) -> Bool
    /// `nil` when the domain could not be read at all (teardown then fails
    /// closed, per Amendment v4 P1).
    func keys(_ bundleID: String) -> [String]?
}

/// `caffeinate -d[ -w <pid>]` for the run's duration (section 2 / item 7).
public protocol C1CaffeinateLaunching: Sendable {
    /// Starts the process. `nil` on success; an error description to
    /// record as `caffeinate.failed` otherwise -- a launch failure here is
    /// recorded and the run continues (section 2 never made `caffeinate`
    /// itself a setup precondition).
    func start() -> String?
    /// Stops the process if one is running; a no-op otherwise. Idempotent --
    /// both `runCleanup()` and a watchdog backstop may call this.
    func stop()
}

/// Durable evidence for one run (`Sources/vizprobe/LiveEvidence.swift`,
/// unmoved) -- a sink `StageC1*` writes records and captures to.
public protocol C1EvidenceRecording: AnyObject, Sendable {
    func record(_ kind: String, _ fields: [String: Any])
    @discardableResult
    func keep(_ image: StripImage, label: String) -> String?
    func close()
}

/// Builds the one `C1EvidenceRecording` sink for a run -- deferred behind a
/// factory (rather than an already-built instance) because the real
/// `LiveEvidence` init can fail (its directory could not be created) and
/// needs the run's binary hashes/arguments/geometry/parameters, all only
/// known once `step1Setup` runs.
public protocol C1EvidenceFactory: Sendable {
    func makeEvidence(binaryURLs: [String: URL], arguments: [String], geometry: BarGeometry?, parameters: DetectorParameters, suffix: String) throws -> any C1EvidenceRecording
}

/// The sleep/clock/run-loop-pump seam (`Sources/vizprobe/Pump.swift`,
/// unmoved): every wait and every bridge from this stage's synchronous code
/// to `Discovering`'s `async` calls goes through here, never `Thread.sleep`
/// or `RunLoop.main` directly, so a test can make both instantaneous.
///
/// `sleep`/`now` are the same pair `VisibilityObserver`/`HidingVerification`
/// already accept as constructor parameters -- the original
/// `Sources/vizprobe/StageC1*.swift` never overrode either (both defaulted
/// to real `Thread.sleep`/`ProcessInfo...systemUptime` there), so `LivePump`
/// wires them to exactly the same real implementations, unchanged; a test
/// environment gives them a virtual clock instead, which is what actually
/// makes I7's whole suite finish in seconds.
public protocol C1Pump: Sendable {
    func run(_ seconds: Double)
    func blocking<T>(_ body: @escaping @Sendable () async -> T) -> T
    func sleep(_ seconds: Double)
    func now() -> Double
}

/// One extras-menu-bar item as a live Accessibility scan
/// (`Sources/vizprobe/BarScan.swift`, unmoved) reports it -- only the fields
/// `detectIndicatorFrame()` needs.
public struct C1ExtrasItem: Equatable, Sendable {
    public let bundleID: String
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public init(bundleID: String, minX: Double, minY: Double, width: Double, height: Double) {
        self.bundleID = bundleID
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }
}

/// Every live/AppKit/Accessibility seam `StageC1*.swift` needs, gathered in
/// one place. `vizprobe` builds exactly one real value of this type
/// (`StageC1Live.swift`); a test builds a fake one against a synthesized
/// bar (I7).
public struct C1StageEnvironment: Sendable {
    /// The one real screen capturer (warm-up, and the base `LatchingCapturer`
    /// wraps). Never read directly for a post-channel capture -- see
    /// `StageC1.latchingCapturer`.
    public var capturer: any StripCapturing
    /// The base discovery pass (launch confirmation, baseline, reset check,
    /// teardown). Wrapped by `C1Discoverer` once the three helpers exist,
    /// and by `TimedDiscoverer`/the single-flight executor (item 6) for the
    /// keyed reads.
    public var discoverer: any Discovering
    /// The owner observer's own AX reader (`LiveMenuBarAXReader` live) --
    /// wrapped by `C1ExecutedAXReader` around the stage's one `C1AXExecutor`.
    public var ownerAXReaderFactory: @Sendable (DiscoveryOrigin) -> any MenuBarAXReading
    /// `HidingVerification`'s own reader factory and the preflight closure's
    /// reader (`DiscoveredFrameReader` live) -- a different concrete adapter
    /// than the owner's, as it always has been; also wrapped by
    /// `C1ExecutedAXReader`.
    public var verificationAXReaderFactory: @Sendable (DiscoveryOrigin) -> any MenuBarAXReading
    /// The bar's geometry (`NSScreen.main`-derived live); `nil` when there is
    /// none (setup aborts).
    public var geometryProvider: @Sendable () -> BarGeometry?
    /// A live Accessibility scan of every extras-menu-bar item on the bar
    /// right now (`BarScan.items()`), for `detectIndicatorFrame()`.
    public var extrasScanner: @Sendable () -> [C1ExtrasItem]
    public var helperLauncher: any C1HelperLaunching
    public var helperDefaults: any C1HelperDefaultsProviding
    public var pump: any C1Pump
    public var caffeinate: any C1CaffeinateLaunching
    public var evidenceFactory: any C1EvidenceFactory
    /// The trust check `Preflight.run`'s own `isTrusted` parameter needs
    /// (item 10 / round 5b's ruling): threaded through explicitly rather
    /// than left to that function's `{ AXIsProcessTrusted() }` default, so a
    /// test never depends on this process's real Accessibility permission.
    public var isTrusted: @Sendable () -> Bool
    /// G7 (Amendment v7): `C1DiscoveryExecutor`'s own bound
    /// (`timedDiscoverer`, `StageC1.swift`), injectable so a test can use a
    /// genuinely short one instead of paying real wall-clock time past the
    /// live default's 3.0 s to exercise a discovery timeout. The live
    /// default is unchanged (`C1DiscoveryExecutor.boundSeconds`).
    public var discoveryExecutorBoundSeconds: Double

    public init(
        capturer: any StripCapturing,
        discoverer: any Discovering,
        ownerAXReaderFactory: @escaping @Sendable (DiscoveryOrigin) -> any MenuBarAXReading,
        verificationAXReaderFactory: @escaping @Sendable (DiscoveryOrigin) -> any MenuBarAXReading,
        geometryProvider: @escaping @Sendable () -> BarGeometry?,
        extrasScanner: @escaping @Sendable () -> [C1ExtrasItem],
        helperLauncher: any C1HelperLaunching,
        helperDefaults: any C1HelperDefaultsProviding,
        pump: any C1Pump,
        caffeinate: any C1CaffeinateLaunching,
        evidenceFactory: any C1EvidenceFactory,
        isTrusted: @escaping @Sendable () -> Bool,
        discoveryExecutorBoundSeconds: Double = C1DiscoveryExecutor.boundSeconds
    ) {
        self.capturer = capturer
        self.discoverer = discoverer
        self.ownerAXReaderFactory = ownerAXReaderFactory
        self.verificationAXReaderFactory = verificationAXReaderFactory
        self.geometryProvider = geometryProvider
        self.extrasScanner = extrasScanner
        self.helperLauncher = helperLauncher
        self.helperDefaults = helperDefaults
        self.pump = pump
        self.caffeinate = caffeinate
        self.evidenceFactory = evidenceFactory
        self.isTrusted = isTrusted
        self.discoveryExecutorBoundSeconds = discoveryExecutorBoundSeconds
    }
}
