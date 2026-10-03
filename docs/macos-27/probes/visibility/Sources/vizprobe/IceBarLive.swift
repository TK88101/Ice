// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, section 4): the one
// live `IceBarEnvironment` -- existing vizprobe pieces (`HelperControl`,
// `HelperDefaults`, `CGWindowListStripCapturer`, `LiveMenuBarAXReader`,
// `LiveFrontmost`, `BarScan`, `LiveEvidence`, `Pump`) behind the step's seams,
// plus the window server's list (deviation 2 C3) and the oracle's templates
// (the corpus's own, with K1's sha256 checked against the pre-registration).
import AppKit
import C2Core
import Foundation
import IceBarCorpus
import IceBarOracle
import IceBarRunCore
import IceBarStage
import IceCore
import MenuBarCapture
import VZGlyphs

final class LiveIceBarHelper: IceBarHelper {
    let control: HelperControl

    init(_ control: HelperControl) {
        self.control = control
    }

    var pid: pid_t { control.pid }
    var isRunning: Bool { control.isRunning }
    func send(_ line: String) { control.send(line) }
    func awaitUp(timeout: Double) -> Bool { control.awaitReply("up", timeout: timeout) != nil }
    func quit(timeout: Double) { control.quit(timeout: timeout) }
}

/// Every helper this process launched, for the signal and watchdog stop
/// (each helper also exits on its own when this process does).
final class LaunchedHelpers: @unchecked Sendable {
    private let lock = NSLock()
    private var all = [HelperControl]()

    func add(_ helper: HelperControl) { lock.withLock { all.append(helper) } }
    func requestQuitAll() { lock.withLock { all }.forEach { $0.requestQuit() } }
}

struct LiveIceBarLauncher: IceBarHelperLaunching {
    let apps: URL
    let registry: LaunchedHelpers

    func launch(app: String, bundleID: String, arguments: [String]) -> IceBarHelper? {
        guard let control = try? HelperControl(appURL: apps.appendingPathComponent(app), bundleID: bundleID, role: arguments.joined(separator: " "),
                                               arguments: arguments, controllerPID: getpid())
        else { return nil }
        registry.add(control)
        return LiveIceBarHelper(control)
    }
}

/// Q12: every window the window server lists, off-screen ones included, in
/// the captured display's coordinates (as `LiveMenuBarAXReader` gives frames).
struct LiveWindowLister: IceBarWindowListing {
    let origin: CGPoint

    func windows(owners: Set<Int32>) -> [WindowEntry] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [NSDictionary] else { return [] }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, owners.contains(pid),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dictionary)
            else { return nil }
            return WindowEntry(pid: pid, layer: layer, bounds: WindowBounds(x: rect.minX - origin.x, y: rect.minY - origin.y, width: rect.width, height: rect.height))
        }
    }
}

/// C2's Menus helper: launched, brought forward, calibrated to its width
/// class by `C2MenuCalibration`, and checked frontmost with the same title
/// edges before every cycle (as `StageC1Menus.swift`).
final class LiveIceBarMenus: IceBarMenus {
    static let edgeTolerancePt = 1.0
    static let settleSeconds = 0.3

    let launcher: LiveIceBarLauncher
    private let frontmost = LiveFrontmost()
    private var helper: IceBarHelper?
    private var edges = [Double]()

    init(launcher: LiveIceBarLauncher) {
        self.launcher = launcher
    }

    func launchAndCalibrate(_ width: C2MenuWidth) -> String? {
        guard let helper = launcher.launch(app: Roster.menusApp, bundleID: Roster.otherBundleID,
                                           arguments: Roster.menusArguments(lifetimeSeconds: StepArguments.helperLifetimeSeconds)),
              helper.awaitUp(timeout: 5)
        else { return "Menus did not come up" }
        self.helper = helper
        _ = frontmost.activate(pid: helper.pid)
        var calibration = C2MenuCalibration(width: width)
        var step = C2MenuCalibration.Step.send(calibration.count)
        while case .send(let count) = step {
            helper.send("menus \(count)")
            Pump.run(Self.settleSeconds)
            step = calibration.next(lastTitleEnd: frontmost.menuTitleRightEdges(pid: helper.pid)?.last)
        }
        guard case .done = step else { return "calibration failed for \(width.rawValue)" }
        _ = frontmost.activate(pid: helper.pid)
        Pump.run(Self.settleSeconds)
        guard frontmost.frontmostPID() == helper.pid, let read = frontmost.menuTitleRightEdges(pid: helper.pid) else {
            return "Menus is not frontmost after activation"
        }
        edges = read
        return nil
    }

    func stillInPlace() -> Bool {
        guard let helper else { return true }
        guard frontmost.frontmostPID() == helper.pid, let read = frontmost.menuTitleRightEdges(pid: helper.pid) else { return false }
        return read.count == edges.count && zip(read, edges).allSatisfy { abs($0 - $1) <= Self.edgeTolerancePt }
    }

    func quit() {
        helper?.quit(timeout: 2)
        helper = nil
    }
}

struct LiveIceBarClock: IceBarClock {
    func now() -> Double { ProcessInfo.processInfo.systemUptime }

    func sleep(until time: Double) {
        let wait = time - now()
        if wait > 0 { Pump.run(wait) }
    }
}

final class LiveIceBarEvidence: IceBarEvidence {
    let base: LiveEvidence

    init(_ base: LiveEvidence) {
        self.base = base
    }

    func record(_ kind: String, _ fields: [String: Any]) { base.record(kind, fields) }
    func keep(_ image: StripImage, label: String) { base.keep(image, label: label) }
}

enum IceBarLiveWiring {
    enum WiringError: Error {
        case noScreen
        case k1Changed(String)
    }

    /// The corpus's own renderings and K1 chevron (`CorpusTemplates`), at scale 2.
    static func templates() throws -> StageTemplates {
        let corpus = try CorpusTemplates(kDirectory: KCaptures.directory)
        guard corpus.k1SHA256 == KCaptures.inputs[0].sha256 else { throw WiringError.k1Changed(corpus.k1SHA256) }
        let helpers = try corpus.helpers(scale: 2)
        return StageTemplates(helpers: Dictionary(uniqueKeysWithValues: helpers.map { ($0.id, $0) }), chevron: corpus.chevron)
    }

    static func environment(apps: URL, evidence: LiveEvidence, registry: LaunchedHelpers) throws -> IceBarEnvironment {
        guard let screen = NSScreen.main, let geometry = BarGeometry(screen: screen) else { throw WiringError.noScreen }
        let origin = CGDisplayBounds(screen.directDisplayID ?? CGMainDisplayID()).origin
        let launcher = LiveIceBarLauncher(apps: apps, registry: registry)
        return IceBarEnvironment(
            capturer: CGWindowListStripCapturer(),
            axReader: LiveMenuBarAXReader(screen: screen),
            windows: LiveWindowLister(origin: origin),
            launcher: launcher,
            menus: LiveIceBarMenus(launcher: launcher),
            clock: LiveIceBarClock(),
            evidence: LiveIceBarEvidence(evidence),
            geometry: geometry,
            barOwners: { BarScan.items(origin: origin).map { BarOwner(bundleID: $0.bundleID, pid: $0.pid) } },
            forgetDomain: { HelperDefaults.forget($0) },
            domainKeys: { HelperDefaults.keys($0) }
        )
    }
}

/// Deviation 5 D5.2: between S-adv variants only, the desktop picture is one
/// of two staged solid images (dark grey, light grey: inside E5's dark and
/// light ranges), each written into the sitting's directory and recorded
/// with its sha256; the original picture is restored before S1 and whenever
/// the sitting ends on its normal path (a signal to `icebar-run` included;
/// SIGKILL or a crash cannot restore: the first record holds the original's
/// path). The next step process's own warm-up and settle follow every change.
final class LiveDesktopPicture {
    static let sidePx = 64

    private let directory: URL
    private let log: RunnerLog
    private let screen: NSScreen
    let original: URL
    /// The original's scaling, clipping and fill colour, handed back with it.
    private let originalOptions: [NSWorkspace.DesktopImageOptionKey: Any]

    /// `nil` unless the original picture can be read now: one that could not
    /// be restored later is refused before anything changes.
    init?(directory: URL, log: RunnerLog) {
        guard let screen = NSScreen.main, let original = NSWorkspace.shared.desktopImageURL(for: screen),
              let data = try? Data(contentsOf: original)
        else {
            log.record(["event": "desktopPicture.failed", "appearance": "original", "error": "no main screen, or the original picture cannot be read"])
            return nil
        }
        self.directory = directory
        self.log = log
        self.screen = screen
        self.original = original
        originalOptions = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        log.record(["event": "desktopPicture.original", "path": original.path, "sha256": Digest.sha256(data)])
    }

    /// `nil`: the original picture, set even if its bytes can no longer be read (the hash is then left out).
    func set(_ appearance: IceBarRunCore.Appearance?) -> Bool {
        let label = appearance?.rawValue ?? "original"
        let image: URL
        switch appearance {
        case nil:
            image = original
        case let staged?:
            // A staged image that cannot be written never falls back to the original.
            guard let url = self.staged(staged) else {
                log.record(["event": "desktopPicture.failed", "appearance": label, "error": "the staged image cannot be written"])
                return false
            }
            image = url
        }
        do {
            try NSWorkspace.shared.setDesktopImageURL(image, for: screen, options: appearance == nil ? originalOptions : [:])
        } catch {
            log.record(["event": "desktopPicture.failed", "appearance": label, "error": "\(error)"])
            return false
        }
        let sha = (try? Data(contentsOf: image)).map(Digest.sha256) ?? "unreadable"
        log.record(["event": "desktopPicture", "appearance": label, "path": image.path, "sha256": sha])
        return true
    }

    /// The staged solid image for `appearance`, written anew at each change
    /// (whatever is at its path -- the directory is shared -- is removed first).
    private func staged(_ appearance: IceBarRunCore.Appearance) -> URL? {
        let level: UInt8
        switch appearance {
        case .dark: level = 30
        case .light: level = 225
        case .neither: return nil
        }
        let url = directory.appendingPathComponent("desktop-\(appearance.rawValue).png")
        try? FileManager.default.removeItem(at: url)
        let bytes = (0..<(Self.sidePx * Self.sidePx)).flatMap { _ -> [UInt8] in [level, level, level, 255] }
        let image = StripImage(width: Self.sidePx, height: Self.sidePx, scale: 1, bytes: bytes)
        return (try? image.writePNG(to: url)) == nil ? nil : url
    }
}
