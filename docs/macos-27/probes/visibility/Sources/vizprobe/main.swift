// vizprobe -- the live harness for T13/T14
// (docs/plans/2026-09-19-visibility-adapter.md, section 6).
//
//   vizprobe --dry-run              preflight + one baseline attempt, read-only,
//                                    nothing launched (T13's own DoD)
//   vizprobe discover|verify --apps <dir> [--dry-run] [--watchdog <minutes>]
//                                    the 2026-09-23 plan's live stages (T8a/T8b)
//   vizprobe live --apps <dir> [--watchdog <minutes>]
//                                    the full protocol of section 6 (T14);
//                                    <dir> is build.sh's output apps directory
//                                    (Target.app, Protected.app, Twin.app)
//
// This tool never launches anything, adds a menu bar item, or posts an
// event except inside `live`, and never on `--dry-run`.
import AppKit
import Foundation

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("vizprobe: \(message)\n".utf8))
    exit(64)
}

let arguments = Array(CommandLine.arguments.dropFirst())
// A status-bar-capable process is needed even for `--dry-run`'s read-only
// Accessibility walk (BarScan uses AXUIElementCreateApplication against
// running apps, which does not itself require this), and unconditionally
// for `live`, which draws real items.
_ = NSApplication.shared

// The 2026-09-23 plan's stages (T8a/T8b): `discover` and `verify`, each
// with its own `--dry-run`. Dispatched first, so their `--dry-run` never
// falls through to the 2026-09-19 one below.
if let stage = arguments.first.flatMap(StageKind.init(rawValue:)) {
    guard let appsPath = option("--apps", in: arguments) else {
        fail("\(stage.rawValue): missing --apps <dir> (build.sh's output apps directory)")
    }
    let appsURL = URL(fileURLWithPath: appsPath)
    let stageApps = HelperApps(
        target: appsURL.appendingPathComponent("Target.app"),
        reference: appsURL.appendingPathComponent("Protected.app"),
        twin: appsURL.appendingPathComponent("Twin.app")
    )
    if arguments.contains("--dry-run") {
        exit(StageDryRun.run(kind: stage, apps: stageApps))
    }
    let stageRun = StageRun(kind: stage, apps: stageApps)
    // A helper that dies between `isRunning` and a write would otherwise
    // kill this process with SIGPIPE before any domain is emptied.
    signal(SIGPIPE, SIG_IGN)
    // Ctrl-C, `kill` and a closed terminal stop the run the same way the
    // watchdog does.
    var stopSources = [DispatchSourceSignal]()
    for number in [SIGINT, SIGTERM, SIGHUP] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler {
            FileHandle.standardError.write(Data("vizprobe: signal \(number) -- quitting helpers and exiting\n".utf8))
            stageRun.emergencyStop()
            exit(3)
        }
        source.resume()
        stopSources.append(source)
    }
    let stageWatchdog = option("--watchdog", in: arguments).flatMap(Double.init) ?? 20
    DispatchQueue.global().asyncAfter(deadline: .now() + stageWatchdog * 60) {
        FileHandle.standardError.write(Data("vizprobe: WATCHDOG after \(stageWatchdog) min -- quitting helpers and exiting\n".utf8))
        stageRun.emergencyStop()
        exit(2)
    }
    exit(stageRun.run(stage == .discover ? stageRun.discoverSteps() : stageRun.verifySteps()))
}

if arguments.contains("--dry-run") {
    exit(DryRun.run())
}

guard arguments.first == "live" else {
    fail("usage: vizprobe --dry-run | vizprobe live --apps <dir>")
}
guard let appsPath = option("--apps", in: arguments) else {
    fail("live: missing --apps <dir> (build.sh's output apps directory)")
}
let appsURL = URL(fileURLWithPath: appsPath)
let apps = HelperApps(
    target: appsURL.appendingPathComponent("Target.app"),
    reference: appsURL.appendingPathComponent("Protected.app"),
    twin: appsURL.appendingPathComponent("Twin.app")
)
for (name, url) in [("Target.app", apps.target), ("Protected.app", apps.reference), ("Twin.app", apps.twin)] {
    guard FileManager.default.fileExists(atPath: url.path) else {
        fail("live: \(name) not found at \(url.path); run build.sh first")
    }
}

// A watchdog, the same shape as probes/safewidth's own
// (Sources/swctl/main.swift's `runExperiment`): if the protocol ever hangs
// somewhere this task's own bounds (settle deadlines, `maxAttempts` caps in
// MenuBarCapture's `VisibilityObserver`) do not cover, this is what keeps a
// helper from being left in the user's bar indefinitely.
let watchdogMinutes = option("--watchdog", in: arguments).flatMap(Double.init) ?? 20
let liveRun = LiveRun(apps: apps)
DispatchQueue.global().asyncAfter(deadline: .now() + watchdogMinutes * 60) {
    FileHandle.standardError.write(Data("vizprobe: WATCHDOG after \(watchdogMinutes) min -- quitting helpers and exiting\n".utf8))
    liveRun.quitHelpers()
    exit(2)
}
exit(liveRun.run())
