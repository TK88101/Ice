// Launches one vzhelper role and drives it over its stdin control channel.
//
// Launched by executing the bundle's own binary directly
// (`<app>/Contents/MacOS/vzhelper`), not through `/usr/bin/open` as
// probes/safewidth's `Session.launch` does: `open` hands the new process to
// LaunchServices and gives the caller no pipe to its stdin, and vzhelper's
// control channel *is* stdin (no signals -- a recycled pid would make a
// stray SIGUSR1 dangerous). Running the bundled executable directly still
// gives it the right `Bundle.main.bundleIdentifier`, because that is read
// from the Info.plist next to the running binary, not from how the process
// was started.
import Foundation

enum HelperControlError: Error {
    case launchFailed(String)
}

final class HelperControl {
    let role: String
    let bundleID: String
    private let process: Process
    private let stdin: Pipe

    var pid: pid_t { process.processIdentifier }
    var isRunning: Bool { process.isRunning }

    init(appURL: URL, bundleID: String, role: String, controllerPID: pid_t) throws {
        self.role = role
        self.bundleID = bundleID
        let executable = appURL.appendingPathComponent("Contents/MacOS/vzhelper")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw HelperControlError.launchFailed("no executable at \(executable.path)")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--controller", "\(controllerPID)", "--role", role]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        self.process = process
        self.stdin = stdin
        do {
            try process.run()
        } catch {
            throw HelperControlError.launchFailed("\(role): \(error)")
        }
    }

    private func send(_ line: String) {
        guard process.isRunning, let data = "\(line)\n".data(using: .utf8) else { return }
        do {
            try stdin.fileHandleForWriting.write(contentsOf: data)
        } catch {
            // The helper may have exited between the isRunning check and the
            // write (a race no probe on stdin can fully close); nothing more
            // to do here -- the caller's own settle/observe loop is what
            // ultimately notices a helper that is gone.
        }
    }

    func hide() { send("hide") }
    func show() { send("show") }

    /// Closing stdin is EOF, which vzhelper treats exactly like a `quit`
    /// line -- and unlike sending the line itself, it cannot race a byte
    /// still in flight. Waits up to `timeout`, then forces the issue.
    func quit(timeout: Double = 2) {
        try? stdin.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
}

enum HelperDefaults {
    /// Deletes a bundle id's defaults domain. `com.icespike4.target` and
    /// `com.icespike4.protected` are reused from probes/safewidth's own
    /// swhelper, which never set an autosave key either, but this runs
    /// unconditionally before every launch (plan 6.1 step 2) so no stored
    /// state from an earlier probe -- this one or safewidth's -- can survive
    /// into a run it was never part of.
    static func forget(_ bundleID: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["delete", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
