// Process plumbing for icewatch (plan 2026-09-24-ice-first-run.md,
// section 5). No Foundation `Process`: its `waitUntilExit` spins the run
// loop, which would re-enter the supervisor's timer.
import Darwin
import Foundation

enum Proc {
    /// The executable path of `pid`, or `nil` if it is gone.
    static func path(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    /// The start time of `pid` in microseconds since the epoch.
    static func startTime(_ pid: pid_t) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return nil
        }
        return UInt64(info.pbi_start_tvsec) * 1_000_000 + UInt64(info.pbi_start_tvusec)
    }

    static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 256)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(count, 0)))).filter { $0 > 0 }
    }

    static func allPaths() -> [(pid: pid_t, path: String)] {
        allPIDs().compactMap { pid in path(pid).map { (pid, $0) } }
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Spawns `path` with every signal at its default disposition and none
    /// blocked (icewatch itself ignores SIGHUP and handles SIGTERM, and
    /// ignored dispositions would otherwise be inherited across exec).
    static func spawn(path: String, arguments: [String], stdin: String = "/dev/null", stdout: String, stderr: String) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var all = sigset_t()
        sigfillset(&all)
        posix_spawnattr_setsigdefault(&attributes, &all)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attributes, &none)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, stdin, O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, stdout, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_addopen(&actions, 2, stderr, O_WRONLY | O_CREAT | O_APPEND, 0o644)

        return try spawn(path: path, arguments: arguments, actions: &actions, attributes: &attributes)
    }

    /// Starts `path` in a new session (`POSIX_SPAWN_SETSID`); once the caller
    /// exits, launchd adopts it, so it is no longer in the tree of the Bash
    /// task that started it. MEASURED 2026-09-24: stopping a Bash task sends
    /// SIGTERM, then SIGKILL, to every process in its tree, whatever their
    /// process group.
    static func spawnDetached(path: String, arguments: [String], stdout: String, stderr: String) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var all = sigset_t()
        sigfillset(&all)
        posix_spawnattr_setsigdefault(&attributes, &all)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attributes, &none)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, stdout, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_addopen(&actions, 2, stderr, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        return try spawn(path: path, arguments: arguments, actions: &actions, attributes: &attributes)
    }

    /// The kernel's canonical spelling of `path` (`/tmp/x` → `/private/tmp/x`),
    /// the same one `proc_pidpath` returns.
    static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Runs a short tool to completion and returns its status and stdout.
    /// Bounded: after `timeout` seconds the tool is killed and the status
    /// is -2, so a stuck `defaults` cannot freeze the supervisor.
    static func run(_ path: String, _ arguments: [String], timeout: Double = 10) -> (status: Int32, output: Data) {
        var pipe: [Int32] = [0, 0]
        guard Darwin.pipe(&pipe) == 0 else { return (-1, Data()) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, pipe[1], 1)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addclose(&actions, pipe[0])
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var all = sigset_t()
        sigfillset(&all)
        posix_spawnattr_setsigdefault(&attributes, &all)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF))

        let pid: pid_t
        do {
            pid = try spawn(path: path, arguments: arguments, actions: &actions, attributes: &attributes)
        } catch {
            close(pipe[0])
            close(pipe[1])
            return (-1, Data())
        }
        close(pipe[1])
        defer { close(pipe[0]) }

        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var timedOut = false
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { timedOut = true; break }
            var descriptor = pollfd(fd: pipe[0], events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(remaining, 1) * 1000))
            if ready < 0 && errno == EINTR { continue }
            if ready <= 0 { continue }
            let count = read(pipe[0], &buffer, buffer.count)
            if count > 0 { output.append(buffer, count: count) } else { break }
        }
        if timedOut { kill(pid, SIGKILL) }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        guard !timedOut else { return (-2, output) }
        let exitCode = (status & 0x7F) == 0 ? (status >> 8) & 0xFF : -1
        return (exitCode, output)
    }

    /// Reaps `pid` if it has exited; `true` when it is gone.
    static func reapIfExited(_ pid: pid_t) -> Bool {
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        return result == pid || (result == -1 && errno == ECHILD)
    }

    private static func spawn(path: String, arguments: [String], actions: inout posix_spawn_file_actions_t?, attributes: inout posix_spawnattr_t?) throws -> pid_t {
        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, path, &actions, &attributes, argv, environ)
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(result), userInfo: [NSLocalizedDescriptionKey: "posix_spawn \(path): \(String(cString: strerror(result)))"])
        }
        return pid
    }
}

/// `/usr/bin/defaults`, read and written only through its own commands so
/// cfprefsd stays the single writer (never the plist file directly).
enum DefaultsTool {
    static let path = "/usr/bin/defaults"

    /// Exported as a **binary** plist to a scratch file and read back:
    /// `defaults export <domain> -` writes XML, whose dates keep whole
    /// seconds only, so a sub-second `SULastCheckTime` never compared equal
    /// to the binary backup (the first run's arm failed on exactly that,
    /// MEASURED 2026-09-24, nothing written).
    static func export(_ domain: String) -> [String: Any]? {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("icewatch-export-\(getpid())-\(UInt64(ProcessInfo.processInfo.systemUptime * 1e6)).plist").path
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        guard Proc.run(path, ["export", domain, scratch]).status == 0 else { return nil }
        return read(plistAt: scratch)
    }

    static func read(plistAt file: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: file) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    static func writeBool(_ domain: String, _ key: String, _ value: Bool) -> Bool {
        Proc.run(path, ["write", domain, key, "-bool", value ? "true" : "false"]).status == 0
    }

    static func importFile(_ domain: String, _ file: String) -> Bool {
        Proc.run(path, ["import", domain, file]).status == 0
    }

    static func delete(_ domain: String) -> Bool {
        Proc.run(path, ["delete", domain]).status == 0
    }
}
