// Launching and tearing down our own helper apps, and remembering and restoring
// the user's frontmost app. Only com.icespike4.* processes are ever launched,
// quit or have their defaults deleted; nothing of the user's is touched.
import AppKit

struct HelperApp {
    let name: String
    let bundleID: String
    let url: URL
}

enum Session {
    static let clock = { ProcessInfo.processInfo.systemUptime }

    /// Runs the run loop for `seconds`, so AppKit keeps laying out our status item.
    static func spin(_ seconds: Double) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    static func helper(_ name: String, bundleID: String, apps: URL) -> HelperApp {
        HelperApp(name: name, bundleID: bundleID, url: apps.appendingPathComponent("\(name).app"))
    }

    static func running(_ helper: HelperApp) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: helper.bundleID)
    }

    /// Deletes the helper's defaults domain, so no stored item position survives.
    static func forgetDefaults(_ helper: HelperApp) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["delete", helper.bundleID]
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// Launches a fresh instance through LaunchServices and waits until it is
    /// running. `background` keeps it from taking focus.
    static func launch(_ helper: HelperApp, background: Bool, arguments: [String], timeout: Double = 5) -> NSRunningApplication? {
        forgetDefaults(helper)
        let before = Set(running(helper).map(\.processIdentifier))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n"] + (background ? ["-g"] : []) + [helper.url.path, "--args"] + arguments
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let deadline = clock() + timeout
        while clock() < deadline {
            if let fresh = running(helper).first(where: { !before.contains($0.processIdentifier) }) {
                return fresh
            }
            spin(0.05)
        }
        return nil
    }

    /// Quits every instance of the helper, forcing it after `grace` seconds.
    static func quit(_ helper: HelperApp, grace: Double = 2) {
        let instances = running(helper)
        instances.forEach { $0.terminate() }
        let deadline = clock() + grace
        while clock() < deadline, instances.contains(where: { !$0.isTerminated }) {
            spin(0.05)
        }
        instances.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        spin(0.1)
    }

    static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Brings an app to the front through LaunchServices, which is not subject to
    /// the cooperative-activation refusal a background process would meet.
    static func activate(bundleID: String) {
        run(["/usr/bin/open", "-b", bundleID])
    }

    /// Our helper apps live in a scratch directory and are not registered with
    /// LaunchServices, so they can only be activated by path.
    static func activate(app url: URL) {
        run(["/usr/bin/open", url.path])
    }

    private static func run(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    static func waitForFrontmost(_ bundleID: String, timeout: Double = 3) -> Bool {
        let deadline = clock() + timeout
        while clock() < deadline {
            if frontmostBundleID() == bundleID {
                return true
            }
            spin(0.05)
        }
        return frontmostBundleID() == bundleID
    }
}
