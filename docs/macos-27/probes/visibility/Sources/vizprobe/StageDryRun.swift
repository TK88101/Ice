// `vizprobe discover|verify --dry-run --apps <dir>`: everything a stage
// checks before its first launch, and nothing it does after -- no helper is
// launched, no item added, no defaults touched. What it reads: the helper
// bundles on disk, the glyphs (offscreen), the bar (captures, as the
// 2026-09-19 dry run does) and one read-only discovery pass, reported as
// counts only.
import AppKit
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDiscovery

enum StageDryRun {
    static func run(kind: StageKind, apps: HelperApps) -> Int32 {
        print("=== vizprobe \(kind.rawValue) --dry-run ===")
        var passed = true

        for (name, url) in [("Target.app", apps.target), ("Protected.app", apps.reference)] {
            let executable = url.appendingPathComponent("Contents/MacOS/vzhelper")
            let ok = FileManager.default.isExecutableFile(atPath: executable.path)
            print("helper \(name): \(ok ? "present" : "MISSING at \(executable.path)")")
            passed = passed && ok
        }
        let bundleIDs = [(apps.target, HelperRole.target), (apps.reference, HelperRole.reference)].map { url, expected -> Bool in
            let actual = Bundle(url: url)?.bundleIdentifier
            print("bundle id \(url.lastPathComponent): \(actual ?? "?") (expected \(expected))")
            return actual == expected
        }
        passed = passed && bundleIDs.allSatisfy { $0 }

        let glyphs = GlyphCheck.run()
        glyphs.lines.forEach { print($0) }
        passed = passed && glyphs.passed

        let leftovers = NSWorkspace.shared.runningApplications.filter { HelperRole.allBundleIDs.contains($0.bundleIdentifier ?? "") }
        print("helpers already running: \(leftovers.count)")
        passed = passed && leftovers.isEmpty

        print("--- read-only preflight (captures the bar, launches nothing) ---")
        let axReader = NSScreen.main.map { LiveMenuBarAXReader(screen: $0) } ?? LiveMenuBarAXReader()
        let outcome = PreflightCheck.run(capturer: CGWindowListStripCapturer(), axReader: axReader)
        if let geometry = outcome.geometry {
            print("geometry: widthPt=\(geometry.widthPt) heightPt=\(geometry.heightPt) scale=\(geometry.scale) notch=\(geometry.notch.map { "\($0.lo)-\($0.hi)" } ?? "none")")
            print("preflight: \(outcome.preflight)")
            print("baseline: \(outcome.baseline.map { "fold \($0.foldAtBaseline), \($0.acceptedIDs.count) user item(s) accepted" } ?? "failed")")
            print("chevron or pill: \(outcome.chevronOrPillSignal), free room \(outcome.room?.freeRoomPt.map { "\($0)" } ?? "?") pt")
            let bar = StageRun.readBar(forItems: 2, geometry: geometry, parameters: .preRegistered)
            print("step 2 room: \(bar.freePt) pt free, \(bar.neededPt) pt needed (indicator up: \(bar.indicatorUp))")
            passed = passed && outcome.ready && !bar.chevronOrPill && bar.freePt >= bar.neededPt
        } else {
            print("geometry: unavailable")
            passed = false
        }

        let discoverer = MenuBarDiscoverer(
            apps: HarnessProcesses(base: LiveRunningApps()),
            reader: LiveExtrasReader(),
            display: LiveDisplay(),
            isTrusted: { AXIsProcessTrusted() },
            ownIdentifiers: StageRun.ownIdentifiers,
            now: { ProcessInfo.processInfo.systemUptime }
        )
        if let result = Pump.blocking({ await discoverer.discover(previous: nil) }) {
            let onBar = result.set.items.filter { $0.position == .onBar }.count
            print("discovery: \(result.set.items.count) item(s), \(onBar) on the bar, completeness \(result.set.completeness), \(String(format: "%.0f", result.duration * 1000)) ms")
        } else {
            print("discovery: FAILED")
            passed = false
        }

        let steps = kind == .discover
            ? "0 bundles, 1 preflight, 2 launch reference+target, 4 hide/show (raw AX, CFEqual), quit target, 9 noDivider (MEASURED), 10a/10b autosave+identifier (MEASURED), 7 positional, 8 unnamed, 11 teardown"
            : "0 bundles, 1 preflight, 2 launch reference+target, 3 five cycles + controls a/b via DiscoveredFrameReader, 5 verification wiring, 6 two items (a) non-first child, (b) section quit/stay, 11 teardown"
        print("steps: \(steps)")
        print("verdict: \(passed ? "ready" : "NOT ready") -- nothing was launched")
        return passed ? 0 : 1
    }
}
