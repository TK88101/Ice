// `icewatch run` (plan 2026-09-24-ice-first-run.md, section 5): arm, write
// the run's settings, wait for `go`, spawn the child, record every tick,
// trip, stop, watch 30 s, restore and verify the preferences domain -- on
// every exit path except SIGKILL of icewatch itself (the user holds the
// manual restore line for that one).
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IceWatchCore

struct RunOptions {
    var appPath: String?
    var execPath: String?
    var domain = ""
    var backup = ""
    var settings: [(key: String, value: Bool)] = []
    var logPath: String?
    var controller: pid_t = 0
    var evidence = ""
    var interval = 0.2
    var goTimeout = 900.0
    var childArguments: [String] = []
}

enum Outcome: Int32 {
    case clean = 0
    case fold = 10
    case stack = 11
    case posting = 12
    case prefs = 13
    case secondIce = 14
    case controller = 15
    case deadman = 16
    case signal = 17
    case childExited = 18
    case restoreFailed = 20
    case armFailed = 21
    case noGo = 22
}

final class Supervisor {
    private let options: RunOptions
    private let evidence: Evidence
    private let reader: BarReader
    private let executable: String
    private var evaluator: TripEvaluator
    private var topology: TopologyTracker
    private var stopMachine = StopMachine()
    private var deadman: Deadman
    private let armedAt: Double
    private var goDeadline: Double
    private var backupPrefs: [String: Any] = [:]
    private var expectedPrefs: [String: Any] = [:]
    private var childPID: pid_t?
    private var childStart: UInt64?
    private var childGone = false
    private var reason: Outcome?
    private var tickIndex = 0
    private var busy = false
    private var lastEnumeration = 0.0
    private var lastPrefsPoll = 0.0
    private var lastStatus = 0.0
    private var lastExtend: Date?
    private var logHandle: FileHandle?
    private var lineBuffer = LineBuffer()
    private var iceLogLines = 0
    private var restoreStartedAt: Double?
    private var restorePendingMarked = false
    private var servicesTermed = false
    private var lastAgentCount: Int?
    private var bundleIDs: [String: String?] = [:]
    private var trips: [String] = []
    private var sources: [DispatchSourceProtocol] = []

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    init(options: RunOptions, evidence: Evidence, reader: BarReader, executable: String) {
        self.options = options
        self.evidence = evidence
        self.reader = reader
        self.executable = executable
        evaluator = TripEvaluator(bar: reader.bar)
        topology = TopologyTracker(bar: reader.bar)
        armedAt = Self.now
        deadman = Deadman(start: armedAt)
        goDeadline = armedAt + options.goTimeout
    }

    // MARK: Arm

    /// Everything that must hold before anything is written. `nil` means
    /// armed; otherwise the reason not to start.
    func arm() -> String? {
        guard let backup = DefaultsTool.read(plistAt: options.backup), !backup.isEmpty else {
            return "backup \(options.backup) missing or unreadable"
        }
        backupPrefs = backup
        guard let current = DefaultsTool.export(options.domain) else {
            return "cannot export \(options.domain)"
        }
        let drift = PrefsCompare.differingKeys(expected: backup, actual: current, allowedPrefixes: [])
        guard drift.isEmpty else {
            return "the domain no longer equals the backup: \(drift.joined(separator: ", "))"
        }
        if let conflict = runningIce(childAllowed: false) {
            return "a process is already running from \(conflict)"
        }
        if let logPath = options.logPath {
            guard let size = (try? FileManager.default.attributesOfItem(atPath: logPath))?[.size] as? Int, size > 0 else {
                return "log \(logPath) missing or empty (is the log stream running?)"
            }
            logHandle = FileHandle(forReadingAtPath: logPath)
            // Only what is appended after arming is read: an earlier line in
            // a reused file must not trip.
            logHandle?.seekToEndOfFile()
        }
        guard options.controller > 0, Proc.isAlive(options.controller) else {
            return "controller \(options.controller) is not running"
        }

        guard setpgid(0, 0) == 0 || getpgrp() == getpid() else {
            return "cannot move into its own process group (errno \(errno))"
        }
        signal(SIGHUP, SIG_IGN)
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in self?.requestStop(.signal, "signal \(signalNumber)") }
            source.resume()
            sources.append(source)
        }
        let controller = DispatchSource.makeProcessSource(identifier: options.controller, eventMask: .exit, queue: .main)
        controller.setEventHandler { [weak self] in self?.requestStop(.controller, "controller \(self?.options.controller ?? 0) exited") }
        controller.resume()
        sources.append(controller)

        let watched = reader.enumerate()
        evidence.record("armed", [
            "pid": getpid(), "pgid": getpgrp(), "sid": getsid(0), "ppid": getppid(),
            "axTrusted": AXIsProcessTrusted(), "screenCapture": CGPreflightScreenCaptureAccess(),
            "controller": options.controller, "domain": options.domain,
            "executable": executable, "arguments": options.childArguments, "watched": watched.map(Int.init),
            "bar": [reader.bar.minX, reader.bar.maxX, reader.bar.height],
        ])

        // From here every exit path restores.
        for (key, value) in options.settings {
            guard DefaultsTool.writeBool(options.domain, key, value) else {
                requestStop(.armFailed, "write \(key) failed")
                return nil
            }
        }
        expectedPrefs = PrefsCompare.expected(backup: backupPrefs, setting: Dictionary(uniqueKeysWithValues: options.settings.map { ($0.key, $0.value) }))
        let written = DefaultsTool.export(options.domain) ?? [:]
        let mismatch = PrefsCompare.differingKeys(expected: expectedPrefs, actual: written, allowedPrefixes: [])
        evidence.record("settingsWritten", ["keys": options.settings.map(\.key), "mismatch": mismatch])
        if !mismatch.isEmpty {
            requestStop(.armFailed, "settings did not read back: \(mismatch.joined(separator: ", "))")
        }
        return nil
    }

    // MARK: Loop

    func run() -> Never {
        let timer = Timer(timeInterval: options.interval, repeats: true) { [weak self] _ in self?.onTick() }
        RunLoop.main.add(timer, forMode: .common)
        onTick()
        RunLoop.main.run()
        exit(Outcome.clean.rawValue)
    }

    private func onTick() {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let now = Self.now

        reapChild()
        if isEndingChild {
            // Nothing but the stop while the child is being ended: a slow AX
            // tick must not delay the KILL.
            advanceStop(now)
            if now - lastStatus >= 1 { lastStatus = now; writeStatus(now) }
            return
        }
        checkControlFiles(now)
        if childPID == nil, !stopMachine.isStopping, evidence.exists("go") {
            spawnChild()
        }

        let (tick, record) = reader.tick()
        tickIndex += 1
        var entry = record
        entry["index"] = tickIndex
        evidence.record("tick", entry)
        if tick.agentState == .ok {
            let count = tick.agentFrames.filter(reader.bar.contains).count
            if let lastAgentCount, lastAgentCount != count {
                evidence.record("topology", ["event": "agentCount \(lastAgentCount) -> \(count)", "widths": tick.agentFrames.filter(reader.bar.contains).map(\.width)])
            }
            lastAgentCount = count
        }

        if !stopMachine.isStopping {
            for trip in evaluator.evaluate(tick) {
                trips.append("\(trip)")
                switch trip {
                case .foldWithOverlap, .foldPersisting: requestStop(.fold, "\(trip)")
                case .stack: requestStop(.stack, "\(trip)")
                }
            }
            if isEndingChild {
                // A trip has just sent TERM: no further AX work this turn.
                writeStatus(now)
                return
            }
        }
        for event in topology.update(tick) {
            evidence.record("topology", ["event": "\(event)"])
        }
        if now - lastEnumeration >= 1 {
            lastEnumeration = now
            let added = reader.enumerate()
            if !added.isEmpty { evidence.record("watchedAdded", ["pids": added.map(Int.init)]) }
            if !stopMachine.isStopping, let conflict = runningIce(childAllowed: true) {
                requestStop(.secondIce, "another process from \(conflict)")
            }
        }
        if !stopMachine.isStopping, now - lastPrefsPoll >= 2 {
            lastPrefsPoll = now
            pollPrefs()
        }
        tailLog()
        advanceStop(now)
        if now - lastStatus >= 1 {
            lastStatus = now
            writeStatus(now)
        }
    }

    // MARK: Child

    private func spawnChild() {
        let stdout = evidence.url("child-stdout.txt").path
        let stderr = evidence.url("child-stderr.txt").path
        do {
            let pid = try Proc.spawn(path: executable, arguments: options.childArguments, stdout: stdout, stderr: stderr)
            childPID = pid
            for _ in 0..<20 where childStart == nil {
                childStart = Proc.startTime(pid)
                if childStart == nil { usleep(5_000) }
            }
            reader.setChild(pid: pid)
            evidence.record("spawned", ["pid": pid, "executable": executable, "start": childStart.map { Int($0) } ?? 0])
            if childStart == nil {
                // Unprovable identity: never signalled; the restore then waits
                // until the child is gone (the user quits it).
                requestStop(.childExited, "no start time for child \(pid); it will not be signalled")
            }
        } catch {
            requestStop(.childExited, "spawn failed: \(error.localizedDescription)")
        }
    }

    private func reapChild() {
        guard let pid = childPID, !childGone else { return }
        if Proc.reapIfExited(pid) {
            childGone = true
            evidence.record("childExited", ["pid": pid])
            if !stopMachine.isStopping { requestStop(.childExited, "child \(pid) exited on its own") }
        }
    }

    private var isEndingChild: Bool {
        switch stopMachine.phase {
        case .terminating, .killing: true
        default: false
        }
    }

    private func childStatus() -> ChildStatus {
        guard let pid = childPID else { return .notStarted }
        if childGone { return .gone }
        let matches = ChildIdentity.matches(expectedPath: executable, expectedStart: childStart, actualPath: Proc.path(pid), actualStart: Proc.startTime(pid))
        return .alive(identityMatches: matches)
    }

    // MARK: Stop

    private func requestStop(_ outcome: Outcome, _ detail: String) {
        if reason == nil {
            reason = outcome
            evidence.record("stop", ["outcome": "\(outcome)", "detail": detail])
        }
        perform(stopMachine.requestStop(now: Self.now, child: childStatus()))
    }

    private func advanceStop(_ now: Double) {
        guard stopMachine.isStopping else { return }
        perform(stopMachine.step(now: now, child: childStatus()))
    }

    private func perform(_ actions: [StopAction]) {
        for action in actions {
            switch action {
            case .sendTerm:
                signalChild(SIGTERM)
            case .sendKill:
                signalChild(SIGKILL)
            case .beginPostWatch:
                evidence.record("postWatch", ["seconds": stopMachine.postWatch])
            case .restore:
                restore()
            case .finish:
                finish()
            }
        }
    }

    private func signalChild(_ signalNumber: Int32) {
        guard let pid = childPID, case .alive(identityMatches: true) = childStatus() else {
            evidence.record("signalSkipped", ["signal": signalNumber])
            return
        }
        let result = kill(pid, signalNumber)
        evidence.record("signalled", ["pid": pid, "signal": signalNumber, "result": result])
    }

    /// The child app's own XPC services (inside its bundle): each one's path
    /// and start time are read, then read again right before the signal.
    private func stopServices(_ signalNumber: Int32) {
        guard let appPath = options.appPath else { return }
        let prefix = appPath + "/Contents/XPCServices/"
        for (pid, path) in Proc.allPaths() where path.hasPrefix(prefix) {
            let start = Proc.startTime(pid)
            guard ChildIdentity.matches(expectedPath: path, expectedStart: start, actualPath: Proc.path(pid), actualStart: Proc.startTime(pid)) else { continue }
            let result = kill(pid, signalNumber)
            evidence.record("serviceSignalled", ["pid": pid, "signal": signalNumber, "result": result])
        }
    }

    /// Retried every 0.5 s until it has restored: a stop never exits with the
    /// domain still changed (except SIGKILL of icewatch itself).
    private func restore() {
        let now = Self.now
        let started = restoreStartedAt ?? now
        restoreStartedAt = started
        if !servicesTermed {
            servicesTermed = true
            stopServices(SIGTERM)
        } else if now - started > 2 {
            stopServices(SIGKILL)
        }
        let running = Proc.allPaths().map { (pid: $0.pid, path: $0.path) }
        guard IceProcesses.noneRunning(running, bundleID: bundleID) else {
            if now - started > 10, !restorePendingMarked {
                restorePendingMarked = true
                let blocking = running.filter { IceProcesses.isIce($0.path, bundleID: bundleID) }.map(\.path)
                evidence.writeMarker("RESTORE-PENDING", "waiting for every Ice to quit: \(blocking)\nmanual: defaults import \(options.domain) \(options.backup)\n")
                evidence.record("restore", ["result": "pending", "blocking": blocking])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.restore() }
            return
        }
        if importAndVerify() || (DefaultsTool.delete(options.domain) && importAndVerify()) {
            // The scan before the import cannot exclude an Ice starting during
            // it (no lock exists); scan again, and if one appeared, wait for it
            // and restore again (Codex, icewatch review round 2).
            let after = Proc.allPaths().map { (pid: $0.pid, path: $0.path) }
            guard IceProcesses.noneRunning(after, bundleID: bundleID) else {
                evidence.record("restore", ["result": "iceAppearedDuringImport"])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.restore() }
                return
            }
            evidence.record("restore", ["result": "verified"])
            if restorePendingMarked { try? FileManager.default.removeItem(at: evidence.url("RESTORE-PENDING")) }
            perform(stopMachine.restoreFinished())
        } else {
            evidence.writeMarker("RESTORE-FAILED", "run: defaults delete \(options.domain); defaults import \(options.domain) \(options.backup)\n")
            evidence.record("restore", ["result": "failed"])
            exitNow(.restoreFailed)
        }
    }

    private func importAndVerify() -> Bool {
        guard DefaultsTool.importFile(options.domain, options.backup), let after = DefaultsTool.export(options.domain) else {
            return false
        }
        let differences = PrefsCompare.differingKeys(expected: backupPrefs, actual: after, allowedPrefixes: [])
        evidence.record("restoreCheck", ["differences": differences])
        return differences.isEmpty
    }

    private func finish() {
        exitNow(reason ?? .clean)
    }

    private func exitNow(_ outcome: Outcome) -> Never {
        writeStatus(Self.now, final: outcome)
        evidence.record("exit", ["outcome": "\(outcome)", "code": outcome.rawValue])
        exit(outcome.rawValue)
    }

    // MARK: Checks

    private func checkControlFiles(_ now: Double) {
        if let modified = evidence.modificationDate("extend"), modified != lastExtend {
            lastExtend = modified
            deadman.extend()
            evidence.record("deadmanExtended", ["deadlineInSeconds": deadman.deadline - now])
        }
        guard !stopMachine.isStopping else { return }
        if evidence.exists("stop") {
            requestStop(.clean, "stop requested")
        } else if deadman.isExpired(now: now) {
            requestStop(.deadman, "deadman")
        } else if childPID == nil, now > goDeadline {
            requestStop(.noGo, "no go within \(Int(options.goTimeout)) s")
        }
    }

    /// Any Ice that must not run now (by bundle identity, IceProcesses):
    /// before the child exists, any Ice at all; afterwards, any Ice outside
    /// the supervised bundle or a second process of the child's executable.
    private func runningIce(childAllowed: Bool) -> String? {
        let running = Proc.allPaths().filter { $0.pid != getpid() }.map { (pid: $0.pid, path: $0.path) }
        if !childAllowed {
            if let path = running.first(where: { IceProcesses.isIce($0.path, bundleID: bundleID) || $0.path == executable })?.path {
                return path
            }
            return nil
        }
        return IceProcesses.secondIce(running, childPID: childPID, supervisedBundle: options.appPath, childExecutable: executable, bundleID: bundleID)
    }

    /// `CFBundleIdentifier` of a bundle, read once per bundle path.
    private func bundleID(_ bundle: String) -> String? {
        if let cached = bundleIDs[bundle] { return cached }
        let info = NSDictionary(contentsOfFile: bundle + "/Contents/Info.plist")
        let identifier = info?["CFBundleIdentifier"] as? String
        bundleIDs[bundle] = identifier
        return identifier
    }

    private func pollPrefs() {
        guard let actual = DefaultsTool.export(options.domain) else {
            evidence.record("prefsPoll", ["result": "exportFailed"])
            return
        }
        let differences = PrefsCompare.differingKeys(expected: expectedPrefs, actual: actual, allowedPrefixes: PrefsCompare.runtimeAllowlist)
        if !differences.isEmpty {
            requestStop(.prefs, "settings changed: \(differences.joined(separator: ", "))")
        }
    }

    private func tailLog() {
        guard let logHandle else { return }
        let data = logHandle.availableData
        guard !data.isEmpty else { return }
        for line in lineBuffer.append(Array(data)) {
            guard let parsed = LogMatcher.parse(line) else { continue }
            if parsed.subsystem.hasPrefix("com.jordanbaird.Ice") { iceLogLines += 1 }
            if LogMatcher.isPosting(parsed), !stopMachine.isStopping {
                requestStop(.posting, "Posting line: \(parsed.message)")
            }
        }
    }

    private func writeStatus(_ now: Double, final outcome: Outcome? = nil) {
        var status: [String: Any] = [
            "phase": "\(stopMachine.phase)",
            "tick": tickIndex,
            "trips": trips,
            "iceLogLines": iceLogLines,
            "deadlineInSeconds": Int(deadman.deadline - now),
            "watched": reader.watched.keys.sorted().map(Int.init),
        ]
        if let childPID { status["childPID"] = childPID }
        status["childGone"] = childGone
        if let reason { status["stopReason"] = "\(reason)" }
        if let outcome { status["exit"] = "\(outcome)" }
        evidence.writeStatus(status)
    }
}
