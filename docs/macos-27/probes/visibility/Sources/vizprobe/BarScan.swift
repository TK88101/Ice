// A read-only Accessibility walk of every extras-menu-bar item currently on
// the bar, independent of anything under Packages/. Never writes an
// attribute, never performs an action, never targets a window.
//
// MenuBarCapture's `MenuBarAXReading` (Packages/MenuBarCapture) only reads
// frames for pids the caller already names -- exactly right for our own
// target and reference, whose pids we hold from launching them. The live
// protocol also needs the opposite: every third-party item on the bar right
// now, to find the leftmost one (the free-room and chevron checks of plan
// section 6.1 step 1 and step 3) and to give the safety monitor of 6.2
// something to watch. That is not something MenuBarCapture's protocol
// expresses, so this file holds that policy -- and calls
// `LiveMenuBarAXReader.extrasFrames(pid:)` for the walk itself, so the
// Accessibility mechanics exist in one place.
import AppKit
import ApplicationServices
import MenuBarCapture

struct BarItem: Equatable {
    let pid: pid_t
    let bundleID: String
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double
}

enum BarScan {
    /// Apple's own bundle id for the process that owns the system's menu bar
    /// extras (the clock, Control Centre, `«`). Matches
    /// MenuBarCapture's `LiveMenuBarAXReader.menuBarAgentBundleID`.
    static let menuBarAgentBundleID = "com.apple.MenuBarAgent"

    /// Per-call messaging timeout, so one hung app cannot stall a scan.
    static let messagingTimeout: Float = 0.25

    /// Every extras item on the bar right now, left to right. Costs one AX
    /// round trip per running application; fine for a probe that scans a
    /// handful of times per protocol step, not a hot loop.
    /// `origin` is the captured display's origin in the global Accessibility
    /// space: frames come back global, while the strip and its geometry are
    /// local to one display, and on any arrangement whose screen does not
    /// start at zero the two disagree.
    static func items(origin: CGPoint = CGDisplayBounds(NSScreen.main?.directDisplayID ?? CGMainDisplayID()).origin) -> [BarItem] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .flatMap { extras(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier ?? "?", origin: origin) }
            .sorted { $0.minX < $1.minX }
    }

    /// The walk itself lives in `MenuBarCapture.LiveMenuBarAXReader`; only the
    /// policy differs (every running app, rather than named pids), so this
    /// asks it for the frames and adds the bundle id the probe needs.
    private static func extras(pid: pid_t, bundleID: String, origin: CGPoint) -> [BarItem] {
        guard let frames = LiveMenuBarAXReader.extrasFrames(pid: pid) else { return [] }
        return frames.map {
            BarItem(pid: pid, bundleID: bundleID, minX: $0.minX - origin.x, minY: $0.minY - origin.y, width: $0.width, height: $0.height)
        }
    }
}
