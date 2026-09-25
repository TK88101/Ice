// icewatch's read-only subcommands: `preflight`, `dry-run`, `dump-windows`.
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IceWatchCore

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
