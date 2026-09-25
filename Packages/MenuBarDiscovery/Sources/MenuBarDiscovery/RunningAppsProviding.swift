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
    /// earlier probe that found the whole bar skipped them too.
    ///
    /// That filter is **not** what handles suspended WebKit content processes,
    /// though an earlier note here said so: MEASURED 2026-09-25, they report
    /// `.accessory`, like real menu bar apps. `MenuBarDiscoverer`'s
    /// `ResponsivenessQuarantine` handles them, by behaviour, and needs each
    /// record's `startTime` to do it (responsiveness-quarantine plan, E0).
    public func processes() -> [ProcessInfoRecord] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }.map { app in
            ProcessInfoRecord(
                pid: app.processIdentifier,
                bundleID: app.bundleIdentifier,
                localizedName: app.localizedName,
                executableName: app.executableURL?.lastPathComponent,
                launchTime: app.launchDate?.timeIntervalSince1970,
                isSelf: app.processIdentifier == selfPID,
                startTime: Self.kernelStartTime(of: app.processIdentifier)
            )
        }
    }

    /// The kernel's start time for `pid`, in seconds since 1970, from
    /// `sysctl(KERN_PROC_PID)`; `nil` when the process is gone or the call
    /// fails. MEASURED 2026-09-25: available for 70 of 70 enumerated processes and
    /// identical across reads, where LaunchServices' `launchDate` was missing for
    /// 55 of them, every WebKit content process included.
    static func kernelStartTime(of pid: pid_t) -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_un.__p_starttime
        guard started.tv_sec > 0 else { return nil }
        return Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
    }

    public func agentPID() -> Int32? {
        NSWorkspace.shared.runningApplications.first { Self.isMenuBarAgent(bundleID: $0.bundleIdentifier, bundleURL: $0.bundleURL) }?.processIdentifier
    }

    /// The agent's bundle id **and** a bundle under `/System` (hardening plan
    /// H3): by id alone, any process claiming `com.apple.MenuBarAgent` that came
    /// first in the list would take over the agent's routing (D4) and its
    /// quarantine exemption. The path is standardized first, so `..` cannot walk
    /// out of `/System`, and compared by component, so `/SystemX` is not it.
    static func isMenuBarAgent(bundleID: String?, bundleURL: URL?) -> Bool {
        guard bundleID == LiveExtrasReader.menuBarAgentBundleID, let bundleURL, bundleURL.isFileURL else { return false }
        let components = bundleURL.standardizedFileURL.pathComponents
        return components.count > 1 && components[0] == "/" && components[1] == "System"
    }
}
