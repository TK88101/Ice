import AppKit
import IceCore

/// The running-process half of one discovery pass (plan section 4.2): every
/// process `MenuBarDiscoverer` should ask Accessibility about, and the pid of
/// `com.apple.MenuBarAgent`'s process so `ItemCatalog.build` can route its
/// children to `systemElements` instead of listing them (D4).
public protocol RunningAppsProviding: Sendable {
    func processes() -> [ProcessInfoRecord]
    func agentPID() -> Int32?
}

/// `NSWorkspace.shared.runningApplications`, including Ice's own process
/// (plan section 4.2: "every running process including its own" -- nothing
/// here filters it out; `ItemCatalog.build` is what routes an own-process
/// record to `visibleControlItem`/the dividers instead of `items`).
public struct LiveRunningApps: RunningAppsProviding {
    public init() {}

    /// Background-only processes (activation policy `.prohibited`) are left
    /// out. None owned a menu bar item in the 2026-09-23 census, and every
    /// earlier probe that found the whole bar skipped them too. Reading them
    /// is not free: a suspended one (a WebKit content process in T6) holds an
    /// Accessibility request for the full timeout, which wakes it every tick
    /// and marks every pass incomplete (plan, Deviations 2).
    public func processes() -> [ProcessInfoRecord] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }.map { app in
            ProcessInfoRecord(
                pid: app.processIdentifier,
                bundleID: app.bundleIdentifier,
                localizedName: app.localizedName,
                executableName: app.executableURL?.lastPathComponent,
                launchTime: app.launchDate?.timeIntervalSince1970,
                isSelf: app.processIdentifier == selfPID
            )
        }
    }

    public func agentPID() -> Int32? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == LiveExtrasReader.menuBarAgentBundleID }?.processIdentifier
    }
}
