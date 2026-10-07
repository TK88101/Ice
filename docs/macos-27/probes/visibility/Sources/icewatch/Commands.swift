// icewatch's read-only subcommands: `preflight`, `menu-frame`, `references`,
// `dry-run`, `dump-windows`.
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IceCore
import IceWatchCore
import MenuBarDetectorFeed
import MenuBarDiscovery

enum Preflight {
    /// Neither call prompts. Ice will be a child of this same chain, so what
    /// this process is granted is what Ice will be granted (plan M3).
    static func run() -> Int32 {
        let result: [String: Any] = [
            "axTrusted": AXIsProcessTrusted(),
            "screenCapture": CGPreflightScreenCaptureAccess(),
            "pid": getpid(),
        ]
        let data = (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])) ?? Data()
        print(String(decoding: data, as: UTF8.self))
        return 0
    }
}

enum MenuFrame {
    /// Reads the application menu's frame with Ice's own macOS 27 reader and
    /// the notch as Ice reads it (`NSScreen.frameOfNotch`'s left edge), and
    /// prints the long-menu verdict (plan 2026-10-07-icebar-menu-frame-fix, F4),
    /// with the main display's width and bar height for the placement check (F3).
    /// Read-only; exit 0 only for `fits`.
    static func run() -> Int32 {
        let pid = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
        let menuMaxX = ApplicationMenuReader.live.frame(owningPID: pid)?.maxX
        let screen = NSScreen.main
        let notchMinX = screen?.auxiliaryTopLeftArea.map { Double($0.maxX) }
        let displayWidth = screen.map { Double($0.frame.width) }
        let barHeight = screen.map { Double($0.frame.maxY - $0.visibleFrame.maxY) }
        let verdict = MenuWidthRule.verdict(menuMaxX: menuMaxX, notchMinX: notchMinX)
        print(MenuFrameReport.line(menuMaxX: menuMaxX, notchMinX: notchMinX, displayWidth: displayWidth, barHeight: barHeight, verdict: verdict.rawValue))
        return verdict == .fits ? 0 : 1
    }
}

enum References {
    static let helperPrefix = "vz-"

    /// One read-only discovery pass, then Ice's own rule for a baseline's
    /// references (`ExternalReferenceCheck`): is there an identifiable item
    /// between Ice's hidden divider and its icon (plan
    /// 2026-10-07-icebar-menu-frame-fix, section 11)? Exit 0 only for a
    /// complete pass with at least one reference. The line names other apps'
    /// items: it belongs in the evidence directory, not on the Terminal.
    /// This command-line process cannot answer Accessibility, so reading its
    /// own pid would only time out and mark the pass incomplete (as `mbdiscover`).
    struct OtherProcesses: RunningAppsProviding {
        let base = LiveRunningApps()
        func processes() -> [ProcessInfoRecord] { base.processes().filter { !$0.isSelf } }
        func agentPID() -> Int32? { base.agentPID() }
    }

    static func run() async -> Int32 {
        let own = OwnIdentifiers(visible: "Ice.ControlItem.Visible", hidden: "Ice.ControlItem.Hidden", alwaysHidden: "Ice.ControlItem.AlwaysHidden")
        let discoverer = MenuBarDiscoverer(
            apps: OtherProcesses(),
            reader: LiveExtrasReader(),
            display: LiveDisplay(),
            isTrusted: { AXIsProcessTrusted() },
            ownIdentifiers: own,
            now: { ProcessInfo.processInfo.systemUptime }
        )
        let set = await discoverer.discover(previous: nil)?.set
        let check = ExternalReferenceCheck(items: set?.items ?? [], own: own)

        func side(_ item: DiscoveredItem) -> String {
            ReferencesReport.side(midX: item.frame?.midX, dividerMinX: check.dividerMinX, iceIconMidX: check.iceIconMidX)
        }
        let helpers = check.others.filter { $0.key.identifier.hasPrefix(helperPrefix) }
        let foreign = check.others.filter { !$0.key.identifier.hasPrefix(helperPrefix) }
        // Ice's baseline makes a discovery pass of its own: an incomplete one
        // here says nothing about that one, so it is not a pass.
        let complete = if case .complete? = set?.completeness { true } else { false }
        print(ReferencesReport.line(
            complete: complete,
            items: set?.items.count ?? 0,
            dividerMinX: check.dividerMinX,
            iceIconMidX: check.iceIconMidX,
            references: check.references.count,
            helpers: helpers.map { ReferencesReport.Helper(id: $0.key.identifier, x: $0.frame?.minX, side: side($0)) },
            others: foreign.map {
                ReferencesReport.Other(
                    namespace: $0.key.namespace,
                    basis: DiscoveryLabels.basisName($0.basis),
                    position: DiscoveryLabels.positionName($0.position),
                    x: $0.frame?.minX,
                    side: side($0)
                )
            }
        ))
        return complete && !check.references.isEmpty ? 0 : 1
    }
}

enum DryRun {
    /// Ticks against the bar with no child, no writes and no stop: records
    /// what would trip and every agent frame width seen (the capture
    /// indicator's width is measured this way in P2).
    static func run(seconds: Double, interval: Double, evidence: Evidence, reader: BarReader) -> Int32 {
        var evaluator = TripEvaluator(bar: reader.bar)
        var topology = TopologyTracker(bar: reader.bar)
        let watched = reader.enumerate()
        evidence.record("dryRun", ["seconds": seconds, "watched": watched.map(Int.init)])
        let start = ProcessInfo.processInfo.systemUptime
        var ticks = 0
        var slowest = 0.0
        var wouldTrip: [String] = []
        var widths: Set<Double> = []
        var lastEnumeration = start
        while ProcessInfo.processInfo.systemUptime - start < seconds {
            let begin = ProcessInfo.processInfo.systemUptime
            let (tick, record) = reader.tick()
            ticks += 1
            slowest = max(slowest, tick.duration)
            var entry = record
            entry["index"] = ticks
            evidence.record("tick", entry)
            for frame in tick.agentFrames where reader.bar.contains(frame) {
                widths.insert((frame.width * 2).rounded() / 2)
            }
            for trip in evaluator.evaluate(tick) {
                wouldTrip.append("\(trip)")
                evidence.record("wouldTrip", ["trip": "\(trip)"])
            }
            for event in topology.update(tick) {
                evidence.record("topology", ["event": "\(event)"])
            }
            if ProcessInfo.processInfo.systemUptime - lastEnumeration >= 1 {
                lastEnumeration = ProcessInfo.processInfo.systemUptime
                let added = reader.enumerate()
                if !added.isEmpty { evidence.record("watchedAdded", ["pids": added.map(Int.init)]) }
            }
            let rest = interval - (ProcessInfo.processInfo.systemUptime - begin)
            if rest > 0 { Thread.sleep(forTimeInterval: rest) }
        }
        let summary: [String: Any] = [
            "ticks": ticks, "slowestTick": slowest, "wouldTrip": wouldTrip,
            "agentWidthsOnBar": widths.sorted(), "watched": reader.watched.count,
        ]
        evidence.record("dryRunSummary", summary)
        let data = (try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])) ?? Data()
        print(String(decoding: data, as: UTF8.self))
        return wouldTrip.isEmpty ? 0 : 1
    }
}

enum DumpWindows {
    private static let attributes = ["AXRole", "AXValue", "AXTitle", "AXDescription", "AXIdentifier"]
    private static let maxDepth = 40
    private static let maxNodes = 5000

    /// A read-only walk of `pid`'s windows: attribute reads only, 0.25 s
    /// messaging timeout on every element, bounded depth and size.
    static func run(pid: pid_t) -> Int32 {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXWindows" as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            print("{\"error\":\"no AXWindows\"}")
            return 1
        }
        var nodes = 0
        var out: [[String: Any]] = []
        for window in windows {
            out.append(walk(window, depth: 0, nodes: &nodes))
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["pid": pid, "nodes": nodes, "windows": out], options: [.sortedKeys, .prettyPrinted])) ?? Data()
        print(String(decoding: data, as: UTF8.self))
        return 0
    }

    private static func walk(_ element: AXUIElement, depth: Int, nodes: inout Int) -> [String: Any] {
        nodes += 1
        AXUIElementSetMessagingTimeout(element, 0.25)
        var node: [String: Any] = [:]
        for attribute in attributes {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { continue }
            if let string = value as? String, !string.isEmpty {
                node[attribute] = string
            } else if let number = value as? NSNumber {
                node[attribute] = number
            }
        }
        guard depth < maxDepth, nodes < maxNodes else { return node }
        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement], !children.isEmpty {
            var list: [[String: Any]] = []
            for child in children where nodes < maxNodes {
                list.append(walk(child, depth: depth + 1, nodes: &nodes))
            }
            node["children"] = list
        }
        return node
    }
}
