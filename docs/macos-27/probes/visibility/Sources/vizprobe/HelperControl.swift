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

// Step A: `@unchecked Sendable` so `extension HelperControl: C1HelperControlling`
// (`StageC1Live.swift`) does not need a retroactive conformance in a
// different file (a hard error under Swift 6 mode) -- not a behaviour
// change: every method here already only ever touches its own state
// through `process`'s own thread-safety or `LineQueue`'s internal lock.
final class HelperControl: @unchecked Sendable {
    let role: String
    let bundleID: String
    private let process: Process
    private let stdin: Pipe
    private let stdout: Pipe
    /// vzhelper's reply lines (`up …`, `frames …`, `selfread …`), collected
    /// by a reader thread so the helper can never block on a full pipe.
    private let lines = LineQueue()

    var pid: pid_t { process.processIdentifier }
    var isRunning: Bool { process.isRunning }

    /// The 2026-09-19 form: one item, `--role`.
    convenience init(appURL: URL, bundleID: String, role: String, controllerPID: pid_t) throws {
        try self.init(appURL: appURL, bundleID: bundleID, role: role, arguments: ["--role", role], controllerPID: controllerPID)
    }

    /// Any vzhelper option set (2026-09-23 plan, T8a); `role` only labels
    /// the helper in the evidence.
    init(appURL: URL, bundleID: String, role: String, arguments: [String], controllerPID: pid_t) throws {
        self.role = role
        self.bundleID = bundleID
        let executable = appURL.appendingPathComponent("Contents/MacOS/vzhelper")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw HelperControlError.launchFailed("no executable at \(executable.path)")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--controller", "\(controllerPID)"] + arguments
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        self.process = process
        self.stdin = stdin
        self.stdout = stdout
        let lines = self.lines
        let handle = stdout.fileHandleForReading
        Thread.detachNewThread {
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    lines.push(line)
                }
            }
        }
        do {
            try process.run()
        } catch {
            throw HelperControlError.launchFailed("\(role): \(error)")
        }
    }

    /// The next reply line whose first word is `kind`, parsed as JSON, or
    /// `nil` after `timeout` seconds. Earlier lines of other kinds are kept.
    func awaitReply(_ kind: String, timeout: Double) -> [String: Any]? {
        guard let line = lines.pop(prefix: kind + " ", timeout: timeout) else { return nil }
        let payload = line.dropFirst(kind.count + 1)
        return (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any]
    }

    /// Sends `command` and waits for its reply of kind `kind`.
    func request(_ command: String, reply kind: String, timeout: Double = 3) -> [String: Any]? {
        send(command)
        return awaitReply(kind, timeout: timeout)
    }

    func send(_ line: String) {
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

    /// G5 (Amendment v7): the same EOF quit signal as `quit(timeout:)`,
    /// without the wait or the `terminate()`/`waitUntilExit()` fallback --
    /// the non-blocking form off-main terminal handling uses. Closing an
    /// already-closed pipe is a harmless no-op (`try?`), so a later,
    /// main-thread `quit(timeout:)` on the same helper (the real,
    /// discovery-confirmed reap) still runs safely afterward.
    func requestQuit() {
        try? stdin.fileHandleForWriting.close()
    }
}

/// A small blocking queue of reply lines, filled by `HelperControl`'s
/// reader thread.
final class LineQueue {
    private var lines = [String]()
    private let condition = NSCondition()

    func push(_ line: String) {
        condition.lock()
        lines.append(line)
        condition.broadcast()
        condition.unlock()
    }

    func pop(prefix: String, timeout: Double) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let index = lines.firstIndex(where: { $0.hasPrefix(prefix) }) {
                return lines.remove(at: index)
            }
            guard condition.wait(until: deadline) else { return nil }
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
    /// `true` when `defaults delete` succeeded or there was nothing to
    /// delete (the domain is then verified empty by `keys`).
    @discardableResult
    static func forget(_ bundleID: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["delete", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0 || keys(bundleID)?.isEmpty == true
    }

    /// The key names in a helper's defaults domain -- names only, never
    /// values -- read by a fresh `defaults export` process, so nothing this
    /// process has cached can answer for it. `[]` when the domain is empty
    /// or absent (`defaults export` of an absent domain exits 0 with an
    /// empty dictionary and creates nothing -- checked on macOS 27);
    /// `nil` when it could not be read.
    static func keys(_ bundleID: String) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["export", bundleID, "-"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist.keys.sorted()
    }

    /// Amendment v8, "Placement by the helpers' own preferred position"
    /// (option A): `defaults write <bundleID> <key> -float <value>`, run
    /// before that helper's own process ever launches -- the one write
    /// this whole enum makes (`forget`/`keys` only ever delete or read).
    /// `true` when the write process exited 0.
    @discardableResult
    static func write(_ bundleID: String, key: String, value: Double) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", bundleID, key, "-float", String(value)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
