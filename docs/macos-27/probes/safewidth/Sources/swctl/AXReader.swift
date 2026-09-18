// Read-only Accessibility snapshot of every menu bar extra and of the frontmost
// app's menus. Nothing here writes an AX attribute or performs an action.
//
// AX is a secondary signal in this probe: frames of items displaced by a jump
// have been seen to lag behind what is on screen (docs/plans/2026-09-18-safe-width.md
// section 0). Pixels decide; AX explains.
import AppKit
import ApplicationServices

struct AXItem: Codable, Equatable {
    let pid: Int32
    let bundle: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let identifier: String
    let title: String
    let desc: String

}

struct AXSnapshot: Codable {
    let items: [AXItem]
    let frontmostBundle: String
    let frontmostMenuRightEdge: Double
    let frontmostMenuCount: Int
}

enum AXReader {
    /// Per-call messaging timeout, so a hung app cannot stall a capture loop.
    static let messagingTimeout: Float = 0.25

    /// The microphone-in-use pill, as far as AX can tell it apart: a MenuBarAgent
    /// item sitting left of every third-party item. With nothing of ours in the
    /// bar and the user's own bar not overflowing, only the pill does that.
    static func pillLike(_ snapshot: AXSnapshot, ignoring pids: Set<pid_t> = []) -> AXItem? {
        leadingAgentItems(snapshot, ignoring: pids).first
    }

    /// Every MenuBarAgent item left of the first third-party item: where both the
    /// pill and the overflow chevron stand. Where AX puts a pill that has been
    /// pushed out of the bar has never been observed.
    static func leadingAgentItems(_ snapshot: AXSnapshot, ignoring pids: Set<pid_t> = []) -> [AXItem] {
        let onBar = snapshot.items.filter { $0.y < 40 && !pids.contains($0.pid) }.sorted { $0.x < $1.x }
        guard onBar.contains(where: { $0.bundle != "com.apple.MenuBarAgent" }) else {
            return []
        }
        return Array(onBar.prefix { $0.bundle == "com.apple.MenuBarAgent" })
    }

    /// Asking every running app costs one AX round trip each, and an unresponsive
    /// app costs the full messaging timeout. `only` restricts the walk to the pids
    /// already known to own menu bar extras; `menus` is needed once per config, not
    /// once per capture.
    static func snapshot(extraPids: [pid_t] = [], only: Set<pid_t>? = nil, menus includeMenus: Bool = true) -> AXSnapshot {
        var targets = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .filter { only == nil || only!.contains($0.processIdentifier) }
            .map { (pid: $0.processIdentifier, bundle: $0.bundleIdentifier ?? $0.localizedName ?? "?") }
        for pid in extraPids + [getpid()] where !targets.contains(where: { $0.pid == pid }) {
            targets.append((pid: pid, bundle: pid == getpid() ? "<swctl>" : "<pid \(pid)>"))
        }
        let items = targets.flatMap { extras(pid: $0.pid, bundle: $0.bundle, details: includeMenus) }.sorted { $0.x < $1.x }
        let front = NSWorkspace.shared.frontmostApplication
        let menus = includeMenus ? (front.map { menuFrames(pid: $0.processIdentifier) } ?? []) : []
        return AXSnapshot(
            items: items,
            frontmostBundle: front?.bundleIdentifier ?? "?",
            frontmostMenuRightEdge: Double(menus.map(\.maxX).max() ?? 0),
            frontmostMenuCount: menus.count
        )
    }

    /// `details` also copies AXTitle and AXDescription: two extra cross-process
    /// round trips per item, wanted when a run is described, not on every capture.
    private static func extras(pid: pid_t, bundle: String, details: Bool) -> [AXItem] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let bar = element(app, "AXExtrasMenuBar") else {
            return []
        }
        return children(bar).compactMap { child in
            guard let frame = frame(child) else {
                return nil
            }
            return AXItem(
                pid: pid,
                bundle: bundle,
                x: frame.minX,
                y: frame.minY,
                w: frame.width,
                h: frame.height,
                identifier: string(child, "AXIdentifier"),
                title: details ? string(child, "AXTitle") : "",
                desc: details ? string(child, "AXDescription") : ""
            )
        }
    }

    private static func menuFrames(pid: pid_t) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let bar = element(app, "AXMenuBar") else {
            return []
        }
        return children(bar).compactMap(frame)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(parent, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (copy(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let value = copy(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        AXValueGetValue(value as! AXValue, .cgRect, &rect)
        return rect
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String {
        (copy(element, attribute) as? String) ?? ""
    }
}
