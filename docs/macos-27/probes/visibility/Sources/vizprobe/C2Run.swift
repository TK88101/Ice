// C2 T4 (docs/plans/2026-09-28-c2-protocol.md section 2, 6.1 item 5):
// `vizprobe c2-run` -- the sequencer. Refuses to start unless the guards
// hold, then runs one `vizprobe c2-config` process per C2Core step, trusts a
// process's evidence only through its verified final manifest, and writes
// its own `runner.jsonl` and, last, `runner.final.json` (atomic).
//
//   vizprobe c2-run --sitting A|B [--length <L>] --apps <dir>
//       --evidence-root <dir> --expect-user <name> --owner-user <name>
//       --expect-geometry <WxH[:lo-hi]>
import AppKit
import C2Core
import CryptoKit
import Foundation
import IceCore
import MenuBarCapture

enum C2RunCommand {
    static func run(_ arguments: [String]) -> Never {
        guard let sitting = option("--sitting", in: arguments), ["A", "B"].contains(sitting) else { fail("c2-run: --sitting must be A or B") }
        guard let apps = option("--apps", in: arguments), let rootPath = option("--evidence-root", in: arguments),
              let expectedUser = option("--expect-user", in: arguments), let ownerUser = option("--owner-user", in: arguments),
              let expectedGeometry = option("--expect-geometry", in: arguments).flatMap(C2Guards.Geometry.init(spec:))
        else { fail("c2-run: --apps, --evidence-root, --expect-user, --owner-user and --expect-geometry are required") }
        let length = option("--length", in: arguments).flatMap(Double.init)
        if sitting == "B", length == nil { fail("c2-run: sitting B needs --length") }

        guard C2Guards.userAllowed(current: NSUserName(), expected: expectedUser, owner: ownerUser) else {
            fail("c2-run: refused -- this is not the isolated account")
        }
        guard sessionOnConsole() else { fail("c2-run: refused -- this session is not the one on screen") }
        guard let screen = NSScreen.main, let bar = BarGeometry(screen: screen),
              expectedGeometry.matches(C2Guards.Geometry(widthPt: bar.widthPt, heightPt: bar.heightPt, notchLo: bar.notch?.lo, notchHi: bar.notch?.hi))
        else { fail("c2-run: refused -- the display does not match --expect-geometry") }
        let roster = BarScan.items().map(\.bundleID)
        guard !roster.isEmpty else {
            fail("c2-run: refused -- no bar items could be read (is Accessibility granted to this Terminal, and was Terminal reopened after granting?)")
        }
        guard C2Guards.rosterAllowed(bundleIDs: roster) else {
            let foreign = Set(roster.filter { !C2Guards.rosterAllowed(bundleIDs: [$0]) }).sorted()
            fail("c2-run: refused -- the bar has an item that is not a system item: \(foreign.joined(separator: ", "))")
        }

        let root = URL(fileURLWithPath: rootPath)
        let runDirectory = root.appendingPathComponent("\(LiveEvidence.timestamp(Date(), format: "yyyyMMdd-HHmmss"))-c2\(sitting)")
        do { try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: false) } catch {
            fail("c2-run: cannot create \(runDirectory.path): \(error)")
        }
        let caffeinate = Process()
        caffeinate.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        caffeinate.arguments = ["-d", "-i", "-w", "\(getpid())"]
        try? caffeinate.run()

        let log = RunnerLog(directory: runDirectory)
        let started = Date()
        var step = 0
        var bracket = C2BracketSequencer()
        var confirm = C2ConfirmSequencer(length: length ?? 0)
        while true {
            let next = sitting == "A" ? bracket.next() : confirm.next()
            guard case .run(let configuration, let lengths) = next else {
                guard case .finished(let verdict) = next else { break }
                log.finish(sitting: sitting, verdict: verdict)
                caffeinate.terminate()
                exit(exitCode(verdict))
            }
            step += 1
            // Switching accounts takes the bar away mid-sitting (2026-09-29
            // rehearsal); stop with that reason rather than a manifest-less
            // child's anonymous safety stop.
            let offConsole = { (when: String) -> Never in
                log.record(["event": "sessionOffConsole", "step": step, "when": when])
                progress("step \(step) \(when) -- this session left the screen; stopping", since: started)
                let verdict = C2Verdict.safetyStop(configuration: configuration.id)
                log.finish(sitting: sitting, verdict: verdict)
                caffeinate.terminate()
                exit(exitCode(verdict))
            }
            guard sessionOnConsole() else { offConsole("not started") }
            let directory = runDirectory.appendingPathComponent(String(format: "%03d-%@", step, configuration.id))
            let config = C2ConfigArguments(appsPath: apps, configuration: configuration, lengths: lengths, evidencePath: directory.path)
            log.record(["event": "start", "step": step, "configuration": configuration.id, "lengths": lengths])
            progress("step \(step) \(configuration.id) started (\(lengths.count) lengths)", since: started)
            let (code, leftConsole) = runChild(config.arguments)
            let result = readBack(directory)
            log.record(["event": "end", "step": step, "exit": Int(code), "status": "\(result.status)", "points": result.points.count])
            if leftConsole { offConsole("interrupted") }
            progress("step \(step) \(configuration.id) ended: \(result.status), \(result.points.count) points", since: started)
            if sitting == "A" { bracket.record(result) } else { confirm.record(result) }
        }
        fail("c2-run: sequencer ended without a verdict")
    }

    private static func exitCode(_ verdict: C2Verdict) -> Int32 {
        switch verdict {
        case .length, .pass: 0
        case .provisionalFail: 1
        case .safetyStop: 3
        }
    }

    /// Whether this login session is the one on screen (fast user switching
    /// moves another session to the console).
    static func sessionOnConsole() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session[kCGSessionOnConsoleKey as String] as? Bool ?? false
    }

    /// One line on the owner's screen per step, so progress is visible
    /// without touching the Mac.
    private static func progress(_ message: String, since start: Date) {
        let elapsed = Int(Date().timeIntervalSince(start))
        let clock = LiveEvidence.timestamp(Date(), format: "HH:mm:ss")
        let line = String(format: "c2-run: %@ [%@, elapsed %d:%02d]\n", message, clock, elapsed / 3600, elapsed % 3600 / 60)
        FileHandle.standardError.write(Data(line.utf8))
    }

    static let consolePollSeconds: UInt32 = 1

    /// Runs one `c2-config`; if this session leaves the screen meanwhile, the
    /// child gets SIGTERM, which `GuardedStage` turns into its terminal
    /// safety teardown (helpers quit and reaped, verdict recorded).
    /// `stop`: polled with the console; once true the child gets SIGTERM too.
    static func runChild(_ arguments: [String], stop: () -> Bool = { false }) -> (code: Int32, leftConsole: Bool) {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        child.arguments = arguments
        do { try child.run() } catch { return (-1, false) }
        var leftConsole = false
        var terminated = false
        while child.isRunning {
            sleep(consolePollSeconds)
            guard child.isRunning else { continue }
            if !terminated {
                leftConsole = !sessionOnConsole()
                terminated = leftConsole || stop()
                if terminated { child.terminate() }
            } else if !leftConsole {
                // `stop`'s caller ignores the signals itself, and a child inherits that until its
                // own handlers are installed: SIGTERM is sent again at every poll until it is reaped.
                child.terminate()
            }
        }
        child.waitUntilExit()
        return (child.terminationStatus, leftConsole)
    }

    /// A process's result, only through its verified final manifest; a
    /// missing or mismatching one is a safety stop (fail closed).
    static func readBack(_ directory: URL) -> C2ProcessResult {
        guard let object = verifiedFinalManifest(directory) else { return C2ProcessResult(status: .safetyStop, points: []) }
        let status = C2ProcessResult.Status(verdict: object["verdict"] as? String)
        let lines = (try? String(contentsOf: directory.appendingPathComponent("samples.jsonl"), encoding: .utf8))?.split(separator: "\n") ?? []
        let points = lines.compactMap { line -> C2Point? in
            guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  record["kind"] as? String == "c2.point",
                  let length = record["length"] as? Double,
                  let reading = (record["reading"] as? String).flatMap(C2Reading.init(name:))
            else { return nil }
            return C2Point(length: length, reading: reading)
        }
        return C2ProcessResult(status: status, points: points)
    }

    /// A step directory's `manifest.final.json`, only when every file it lists still hashes the same.
    static func verifiedFinalManifest(_ directory: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.final.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recorded = object["files"] as? [String: String],
              C2Manifest.verify(recorded: recorded, actual: hashes(of: directory))
        else { return nil }
        return object
    }

    static func hashes(of directory: URL) -> [String: String] {
        var files = [String: String]()
        let root = directory.standardizedFileURL.path + "/"
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let relative = url.standardizedFileURL.path.replacingOccurrences(of: root, with: "")
            guard relative != "manifest.final.json", let data = try? Data(contentsOf: url) else { continue }
            files[relative] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return files
    }
}

/// `runner.jsonl`, one record per event, then `runner.final.json` (atomic).
/// Shared by `c2-run` and route C's `icebar-run`.
final class RunnerLog {
    private let directory: URL
    private var lines = [String]()

    init(directory: URL) {
        self.directory = directory
    }

    func record(_ fields: [String: Any]) {
        var object = fields
        object["wall"] = LiveEvidence.timestamp(Date(), format: "yyyy-MM-dd'T'HH:mm:ss.SSSXXX")
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), let line = String(data: data, encoding: .utf8) else { return }
        lines.append(line)
        try? (lines.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("runner.jsonl"), atomically: true, encoding: .utf8)
    }

    func finish(sitting: String, verdict: C2Verdict) {
        record(["event": "verdict", "verdict": "\(verdict)"])
        writeFinal(["sitting": sitting, "verdict": "\(verdict)"])
        print("c2-run: sitting \(sitting): \(verdict)")
    }

    /// `runner.final.json`: `fields` plus every file's sha256.
    func writeFinal(_ fields: [String: Any]) {
        var final = fields
        final["files"] = C2RunCommand.hashes(of: directory)
        if let data = try? JSONSerialization.data(withJSONObject: final, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("runner.final.json"), options: .atomic)
        }
    }
}
