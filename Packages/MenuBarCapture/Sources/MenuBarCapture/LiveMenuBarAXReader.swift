import AppKit
import ApplicationServices
import IceCore

/// Reads `AXExtrasMenuBar` frames for the given pids and for
/// `com.apple.MenuBarAgent`. Read-only: mirrors the walk in
/// docs/macos-27/probes/safewidth/Sources/swctl/AXReader.swift, scoped to
/// exactly the pids this package is asked about. Never sets an attribute,
/// never performs an action.
public struct LiveMenuBarAXReader: MenuBarAXReading {
    /// Apple's own bundle id for the process that owns the system's menu bar
    /// extras (the clock, Control Centre, `«`).
    public static let menuBarAgentBundleID = "com.apple.MenuBarAgent"
    /// Per-call messaging timeout, so a hung app cannot stall a capture loop
    /// (matches `swctl`'s `AXReader.messagingTimeout`).
    public static let messagingTimeout: Float = 0.25

    /// Where the captured strip's origin sits in the global Accessibility
    /// space. Accessibility reports frames against the whole desktop, while a
    /// `StripImage` and its `BarGeometry` are local to one display, so on any
    /// arrangement whose captured screen does not start at the global origin
    /// the two coordinate systems disagree and every frame reads as outside
    /// the strip. Zero on a single-display Mac, which is why the live run of
    /// 2026-09-19 could not have caught this.
    public let origin: CGPoint

    public init(origin: CGPoint = .zero) {
        self.origin = origin
    }

    /// The reader for a given screen, with its origin taken from the display
    /// the strip is captured from.
    public init(screen: NSScreen) {
        self.init(origin: CGDisplayBounds(screen.directDisplayID ?? CGMainDisplayID()).origin)
    }

    public func read(items: [String: pid_t]) -> MenuBarAXSnapshot? {
        // MenuBarAgent's own extras are the whole-read trust anchor: a
        // capture always has one to find (plan section 3.5), so a failure to
        // even read it means nothing this call returns can be trusted.
        guard let agentPID = Self.runningPID(bundleID: Self.menuBarAgentBundleID) else {
            return nil
        }
        guard let agentRects = Self.extrasFrames(pid: agentPID) else {
            return nil
        }

        var itemFrames = [String: ItemFrame]()
        for (id, pid) in items {
            guard let frame = Self.extrasFrames(pid: pid)?.first else { continue }
            itemFrames[id] = ItemFrame(id: id, minX: frame.minX - origin.x, minY: frame.minY - origin.y, width: frame.width, height: frame.height)
        }

        return MenuBarAXSnapshot(
            itemFrames: itemFrames,
            agentFrames: agentRects.map { AgentFrame(minX: $0.minX - origin.x, minY: $0.minY - origin.y, width: $0.width) }
        )
    }

    private static func runningPID(bundleID: String) -> pid_t? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }?.processIdentifier
    }

    /// `nil` when `AXExtrasMenuBar` (or its children) could not be read at
    /// all -- the API call itself failed; an empty array when the call
    /// succeeded and found nothing.
    /// One process's menu bar extras, in global Accessibility coordinates.
    ///
    /// Public because the harnesses need the same walk with a different policy
    /// (every running app, rather than the pids a caller names). The protocol
    /// stays narrow; the mechanics are shared, so this walk exists once.
    public static func extrasFrames(pid: pid_t) -> [CGRect]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)

        var barValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &barValue) == .success,
              let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let bar = barValue as! AXUIElement

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenValue) == .success else {
            return nil
        }
        let children = (childrenValue as? [AXUIElement]) ?? []
        return children.compactMap(frame)
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        var rect = CGRect.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(value as! AXValue, .cgRect, &rect)
        return rect
    }
}
