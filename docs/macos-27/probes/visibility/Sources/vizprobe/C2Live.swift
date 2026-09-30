// C2 (docs/plans/2026-09-28-c2-protocol.md section 2, 6.1 items 4-5): the
// live frontmost/menu seam, `vizprobe c2-config` (one configuration, one
// length list, C1's guarded stage) and `vizprobe c2-run` (the sequencer:
// guards, one `c2-config` process per step, verified final manifests, stop
// rules). Every decision is C2Core's; this file is I/O.
import AppKit
import ApplicationServices
import C1Stage
import C2Core
import CryptoKit
import Foundation

struct LiveFrontmost: C1FrontmostControlling {
    func frontmostPID() -> pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    func menuTitleRightEdges(pid: pid_t) -> [Double]? {
        let app = AXUIElementCreateApplication(pid)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success, let bar else { return nil }
        var children: CFTypeRef?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement]
        else { return nil }
        var edges = [Double]()
        for item in items {
            var position: CFTypeRef?
            var size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size
            else { return nil }
            var point = CGPoint.zero
            var extent = CGSize.zero
            // swiftlint:disable force_cast
            AXValueGetValue(position as! AXValue, .cgPoint, &point)
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
            // swiftlint:enable force_cast
            edges.append(Double(point.x + extent.width))
        }
        return edges
    }

    func activate(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activate() ?? false
    }
}

enum C2ConfigCommand {
    static func run(_ arguments: [String]) -> Never {
        let parsed: C2ConfigArguments
        switch C2ConfigArguments.parse(arguments) {
        case .success(let value): parsed = value
        case .failure(let error): fail("c2-config: \(error)")
        }
        let apps = URL(fileURLWithPath: parsed.appsPath)
        let k = parsed.configuration.hiddenCount
        let c1Apps = C1Apps(
            target: apps.appendingPathComponent("Target.app"),
            protected: apps.appendingPathComponent("Protected.app"),
            spacer: apps.appendingPathComponent("Spacer.app"),
            extraHidden: (0..<(k - 1)).map { apps.appendingPathComponent("Hidden\($0 + 2).app") },
            menus: (apps.appendingPathComponent("Menus.app"), parsed.configuration.width)
        )
        LiveEvidence.directoryOverride = URL(fileURLWithPath: parsed.evidencePath)
        let stage = StageC1(environment: C1LiveWiring.make(frontmost: LiveFrontmost()), apps: c1Apps, dry: false, lengthPlan: .measure(parsed.lengths))
        GuardedStage.run(stage, name: "c2-config", watchdogMinutes: StageC1.watchdogMinutes)
    }
}
