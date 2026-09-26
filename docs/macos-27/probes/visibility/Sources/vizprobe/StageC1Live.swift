// Rework #5, step A: the one real `C1StageEnvironment` -- every
// AppKit/Accessibility/live-process seam `C1Stage`'s `StageC1*.swift` files
// used to reach directly before this rework. `vizprobe c1` (`main.swift`)
// builds this once and hands it to `StageC1.init(environment:apps:dry:)`;
// nothing else in this file runs the protocol itself.
import AppKit
import ApplicationServices
import C1Stage
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

extension HelperControl: C1HelperControlling {}

/// Wraps `HelperControl`'s own launch, plus the two AppKit-only checks
/// `step0Bundles` makes (a bundle's identity/executable, and whether any
/// process under a given bundle id is already running).
struct LiveHelperLauncher: C1HelperLaunching {
    func validateBundle(at url: URL, expectedBundleID: String) -> Bool {
        guard Bundle(url: url)?.bundleIdentifier == expectedBundleID else { return false }
        let executable = url.appendingPathComponent("Contents/MacOS/vzhelper").resolvingSymlinksInPath().path
        return executable.hasPrefix(url.resolvingSymlinksInPath().path + "/") && FileManager.default.isExecutableFile(atPath: executable)
    }

    func runningBundleIDs(among candidates: [String]) -> [String] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return candidates.filter { running.contains($0) }
    }

    func launch(appURL: URL, bundleID: String, role: String, arguments: [String], controllerPID: pid_t) -> (any C1HelperControlling)? {
        try? HelperControl(appURL: appURL, bundleID: bundleID, role: role, arguments: arguments, controllerPID: controllerPID)
    }
}

/// Wraps the static `HelperDefaults` enum (`HelperControl.swift`).
struct LiveHelperDefaults: C1HelperDefaultsProviding {
    func forget(_ bundleID: String) -> Bool { HelperDefaults.forget(bundleID) }
    func keys(_ bundleID: String) -> [String]? { HelperDefaults.keys(bundleID) }
}

/// Wraps `Pump.run`/`Pump.blocking` (`Pump.swift`) -- the main-run-loop pump
/// every live wait and every bridge into `Discovering`'s `async` calls goes
/// through.
struct LivePump: C1Pump {
    func run(_ seconds: Double) { Pump.run(seconds) }
    func blocking<T>(_ body: @escaping @Sendable () async -> T) -> T { Pump.blocking(body) }
    /// Matches `VisibilityObserver`/`HidingVerification`'s own real
    /// defaults exactly (neither was overridden before this rework).
    func sleep(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }
    func now() -> Double { ProcessInfo.processInfo.systemUptime }
}

/// Rework #5 item 7 (r5b item 7, P1): `caffeinate -d -w <this process's own
/// pid>` -- `-w` makes the system kill `caffeinate` itself the moment this
/// process exits for any reason (a crash included), so the display can
/// never be held awake by an orphaned child past this run's own life,
/// on top of the explicit `stop()` teardown/backstop already call. One
/// instance per run.
final class LiveCaffeinate: C1CaffeinateLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func start() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-d", "-w", "\(getpid())"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            lock.withLock { self.process = process }
            return nil
        } catch {
            return "\(error)"
        }
    }

    func stop() {
        let running: Process? = lock.withLock {
            defer { process = nil }
            return process
        }
        running?.terminate()
    }
}

extension LiveEvidence: C1EvidenceRecording {}

/// Wraps `LiveEvidence`'s own throwing initializer.
struct LiveEvidenceFactory: C1EvidenceFactory {
    func makeEvidence(binaryURLs: [String: URL], arguments: [String], geometry: BarGeometry?, parameters: DetectorParameters, suffix: String) throws -> any C1EvidenceRecording {
        try LiveEvidence(binaryURLs: binaryURLs, arguments: arguments, geometry: geometry, parameters: parameters, suffix: suffix)
    }
}

enum C1LiveWiring {
    /// One real `C1StageEnvironment`, built fresh for each `vizprobe c1`
    /// invocation -- exactly the concrete types
    /// `Sources/vizprobe/StageC1*.swift` used to construct directly.
    static func make() -> C1StageEnvironment {
        C1StageEnvironment(
            capturer: CGWindowListStripCapturer(),
            discoverer: MenuBarDiscoverer(
                apps: HarnessProcesses(base: LiveRunningApps()),
                reader: LiveExtrasReader(),
                display: LiveDisplay(),
                isTrusted: { AXIsProcessTrusted() },
                ownIdentifiers: StageRun.ownIdentifiers,
                now: { ProcessInfo.processInfo.systemUptime }
            ),
            ownerAXReaderFactory: { origin in
                LiveMenuBarAXReader(origin: CGPoint(x: origin.x, y: origin.y))
            },
            verificationAXReaderFactory: { origin in
                DiscoveredFrameReader(extras: LiveExtrasReader(), apps: LiveRunningApps(), origin: origin)
            },
            geometryProvider: {
                NSScreen.main.flatMap { BarGeometry(screen: $0) }
            },
            extrasScanner: {
                BarScan.items().map { C1ExtrasItem(bundleID: $0.bundleID, minX: $0.minX, minY: $0.minY, width: $0.width, height: $0.height) }
            },
            helperLauncher: LiveHelperLauncher(),
            helperDefaults: LiveHelperDefaults(),
            pump: LivePump(),
            caffeinate: LiveCaffeinate(),
            evidenceFactory: LiveEvidenceFactory(),
            isTrusted: { AXIsProcessTrusted() }
        )
    }
}
