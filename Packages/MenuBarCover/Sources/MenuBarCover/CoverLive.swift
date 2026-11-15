//  CoverLive.swift
//  MenuBarCover
//
//  The live halves: `MenuBarAgent`'s Accessibility tree and hit test, the
//  window list and the two image calls, the displays' bars.

import AppKit
import ApplicationServices
import IceCore
import MenuBarDiscovery

/// Reads `MenuBarAgent` (plan D1; MEASURED 2026-11-15: one `AXWindow` per bar
/// with that bar's frame, one child per item slot, whose own child belongs to
/// the owning app). Read-only; call it off the main thread.
public final class LiveCoverBarReader: CoverBarReading {
    /// An answer later than this is no answer.
    public static let messagingTimeout: Float = 0.25
    /// A read that fails this often in a row, or runs this long, is abandoned.
    public static let maxFailures = 3
    public static let maxSeconds = 2.0

    /// The agent as last found, kept while that process lives.
    private var known: (pid: pid_t, element: AXUIElement)?
    private let lock = NSLock()

    public init() {}

    /// `MenuBarAgent`'s pid: Apple's own, by its path and signature, not by
    /// its bundle id alone (`LiveRunningApps.agentPID`, hardening H3).
    public static func agentPID() -> pid_t? {
        LiveRunningApps().agentPID()
    }

    private func agent() -> (pid: pid_t, element: AXUIElement)? {
        lock.lock()
        defer { lock.unlock() }
        if let known, kill(known.pid, 0) == 0 { return known }
        known = Self.agentPID().map { pid in
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
            return (pid, element)
        }
        return known
    }

    private func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else {
            return nil
        }
        var point = CGPoint.zero, extent = CGSize.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    public func slots(of bar: CoverBar) -> [CoverSlot]? {
        guard let agent = agent(), let windows = value(agent.element, kAXChildrenAttribute) else { return nil }
        let started = CFAbsoluteTimeGetCurrent()
        var failures = 0
        /// Counts a failed read; whether the whole read is to be abandoned.
        func failed() -> Bool {
            failures += 1
            return failures >= Self.maxFailures
        }
        var slots = [CoverSlot]()
        // Children are taken through `childElements`: `as? [AXUIElement]` does not check its elements.
        for window in LiveExtrasReader.childElements(windows) where value(window, kAXRoleAttribute) as? String == kAXWindowRole {
            guard let windowFrame = frame(window) else {
                if failed() { return nil }
                continue
            }
            guard abs(windowFrame.minX - bar.frame.minX) <= 1, abs(windowFrame.width - bar.frame.width) <= 1 else { continue }
            guard let children = value(window, kAXChildrenAttribute) else {
                if failed() { return nil }
                continue
            }
            for child in LiveExtrasReader.childElements(children) {
                guard CFAbsoluteTimeGetCurrent() - started <= Self.maxSeconds else { return nil }
                guard let slotFrame = frame(child) else {
                    if failed() { return nil }
                    continue
                }
                failures = 0
                var owner = agent.pid
                if let hosted = LiveExtrasReader.childElements(value(child, kAXChildrenAttribute)).first {
                    AXUIElementGetPid(hosted, &owner)
                }
                slots.append(CoverSlot(
                    owner: owner, minX: Double(slotFrame.minX - bar.frame.minX), maxX: Double(slotFrame.maxX - bar.frame.minX)
                ))
            }
        }
        return slots
    }

    public func owners(at xs: [Double], of bar: CoverBar) -> [Int32?] {
        guard let agent = agent() else { return xs.map { _ in nil } }
        let y = Float(bar.frame.midY)
        return xs.map { x in
            var element: AXUIElement?
            guard AXUIElementCopyElementAtPosition(agent.element, Float(bar.frame.minX) + Float(x), y, &element) == .success, let element else {
                return nil
            }
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            return pid
        }
    }
}

/// The window list and the image calls (plan D2). Call it off the main thread.
public final class LiveCoverCapturer: CoverCapturing {
    public init() {}

    /// The system's `Menubar` window of the bar, and the windows below it that
    /// reach into the strip, front to back.
    private func windows(of bar: CoverBar) -> (menubar: CGWindowID, below: [(id: CGWindowID, bounds: CGRect)])? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
        var menubar: CGWindowID?
        var below = [(id: CGWindowID, bounds: CGRect)]()
        for window in list {
            guard let id = window[kCGWindowNumber as String] as? CGWindowID else { continue }
            if menubar == nil {
                if let bounds = CoverBars.menubarBounds(window), abs(bounds.minX - bar.frame.minX) <= 1, abs(bounds.width - bar.frame.width) <= 1 {
                    menubar = id
                }
                continue
            }
            if let bounds = CoverBars.bounds(window), bounds.intersects(bar.frame) { below.append((id, bounds)) }
        }
        return menubar.map { ($0, below) }
    }

    public func strips(of bar: CoverBar) -> CoverStrips? {
        guard let windows = windows(of: bar),
              let below = CGWindowListCreateImage(bar.frame, .optionOnScreenBelowWindow, windows.menubar, [.bestResolution]),
              let onScreen = CGWindowListCreateImage(bar.frame, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
        else {
            return nil
        }
        return CoverStrips(below: below, onScreen: onScreen)
    }

    public func underStripSignature(of bar: CoverBar) -> String {
        guard let windows = windows(of: bar) else { return "unreadable" }
        return windows.below.map { "\($0.id):\(Int($0.bounds.minX)),\(Int($0.bounds.minY)),\(Int($0.bounds.width)),\(Int($0.bounds.height))" }
            .joined(separator: "|")
    }
}

public enum CoverBars {
    /// The bars of the connected displays that do not mirror another. Main thread.
    public static func current() -> [CoverBar] {
        let menubars = menubarHeights()
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            guard CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay else { return nil }
            let bounds = CGDisplayBounds(id)
            guard bounds.width > 0 else { return nil }
            let fallback = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
            var notch: ClosedRange<Double>?
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, left.maxX < right.minX {
                notch = Double(left.maxX - screen.frame.minX)...Double(right.minX - screen.frame.minX)
            }
            return CoverBar(
                displayID: id,
                frame: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: menubars[id] ?? fallback),
                scale: Double(screen.backingScaleFactor), notch: notch
            )
        }
    }

    static func bounds(_ window: [String: Any]) -> CGRect? {
        (window[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
    }

    /// The bounds of a window-list entry that is the system's `Menubar` window.
    static func menubarBounds(_ window: [String: Any]) -> CGRect? {
        guard window[kCGWindowOwnerName as String] as? String == "Window Server",
              window[kCGWindowName as String] as? String == "Menubar",
              window[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.mainMenuWindow))
        else {
            return nil
        }
        return bounds(window)
    }

    /// The height of each display's `Menubar` window, from the window list.
    private static func menubarHeights() -> [UInt32: CGFloat] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var heights = [UInt32: CGFloat]()
        for window in list {
            guard let bounds = menubarBounds(window), bounds.height > 0, bounds.height < 100 else { continue }
            var id: CGDirectDisplayID = 0
            var count: UInt32 = 0
            if CGGetDisplaysWithPoint(CGPoint(x: bounds.midX, y: bounds.minY + 1), 1, &id, &count) == .success, count > 0, heights[id] == nil {
                heights[id] = bounds.height
            }
        }
        return heights
    }
}
