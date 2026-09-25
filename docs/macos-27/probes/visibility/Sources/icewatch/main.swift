// icewatch -- the first run's supervisor, recorder, watchdog and restorer
// (docs/plans/2026-09-24-ice-first-run.md, section 5).
//
//   icewatch preflight
//   icewatch dry-run --seconds N --evidence <dir> [--interval 0.2]
//   icewatch dump-windows --pid <pid>
//   icewatch run (--app <X.app> | --exec <path>) --domain <d> --backup <plist>
//                [--set Key=true|false ...] [--log <ndjson>] --controller <pid>
//                --evidence <dir> [--interval 0.2] [--go-timeout 900]
//                [--detach] [-- child arguments]
//
// --detach starts the supervisor in a new session owned by launchd, so
// stopping or ending the Bash task that launched it cannot kill it before
// it has restored the domain.
//
// Read-only toward every other process: Accessibility attribute reads and
// process listings only; no capture, no AX write or action, no event. It
// signals only its own child (path and start time checked) and the child
// app's own XPC services, and writes only the given defaults domain and
// the evidence directory.
import AppKit
import Foundation
import IceWatchCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("icewatch: \(message)\n".utf8))
    exit(Outcome.armFailed.rawValue)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail("usage: icewatch preflight|dry-run|dump-windows|run ...") }
arguments.removeFirst()

let valuedOptions: [String: Set<String>] = [
    "preflight": [],
    "dump-windows": ["--pid"],
    "dry-run": ["--seconds", "--evidence", "--interval"],
    "run": ["--app", "--exec", "--domain", "--backup", "--set", "--log", "--controller", "--evidence", "--interval", "--go-timeout"],
]
let flagOptions: [String: Set<String>] = ["run": ["--detach"]]
guard let valued = valuedOptions[command] else { fail("unknown command \(command)") }
let parsed: Options.Parsed
do {
    parsed = try Options.parse(arguments, valued: valued, flags: flagOptions[command] ?? [])
} catch {
    fail("\(error)")
}
let childArguments = parsed.child

func values(_ name: String) -> [String] { parsed.values[name] ?? [] }

func value(_ name: String) -> String? { parsed.value(name) }

switch command {
case "preflight":
    exit(Preflight.run())

case "dump-windows":
    guard let pid = value("--pid").flatMap(Int32.init) else { fail("dump-windows needs --pid") }
    exit(DumpWindows.run(pid: pid))

case "dry-run":
    guard let directory = value("--evidence") else { fail("dry-run needs --evidence") }
    let seconds = value("--seconds").flatMap(Double.init) ?? 60
    let interval = value("--interval").flatMap(Double.init) ?? 0.2
    guard let evidence = try? Evidence(directory: directory) else { fail("cannot open evidence \(directory)") }
    guard let reader = BarReader() else { fail("no display") }
    exit(DryRun.run(seconds: seconds, interval: interval, evidence: evidence, reader: reader))

case "run":
    var options = RunOptions()
    // Canonical paths throughout: proc_pidpath reports /private/tmp, never
    // /tmp (the P2 defect: identity never matched, the child was never
    // signalled).
    options.appPath = value("--app").map(Proc.canonical)
    options.execPath = value("--exec")
    options.domain = value("--domain") ?? ""
    options.backup = value("--backup") ?? ""
    options.logPath = value("--log")
    options.controller = value("--controller").flatMap(Int32.init) ?? 0
    options.evidence = value("--evidence") ?? ""
    options.interval = value("--interval").flatMap(Double.init) ?? 0.2
    guard (0.05...1).contains(options.interval) else { fail("--interval must be in [0.05, 1]") }
    options.goTimeout = value("--go-timeout").flatMap(Double.init) ?? 900
    options.childArguments = childArguments
    do {
        options.settings = try SettingsArguments.parse(values("--set"))
    } catch {
        fail("\(error)")
    }
    guard !options.domain.isEmpty, !options.backup.isEmpty, !options.evidence.isEmpty else {
        fail("run needs --domain, --backup and --evidence")
    }

    let executable: String
    if let appPath = options.appPath {
        guard
            let info = NSDictionary(contentsOfFile: appPath + "/Contents/Info.plist"),
            let name = info["CFBundleExecutable"] as? String
        else { fail("no Info.plist in \(appPath)") }
        executable = Proc.canonical(appPath + "/Contents/MacOS/" + name)
    } else if let execPath = options.execPath {
        executable = Proc.canonical(execPath)
    } else {
        fail("run needs --app or --exec")
    }
    guard FileManager.default.isExecutableFile(atPath: executable) else { fail("not executable: \(executable)") }
    guard let evidence = try? Evidence(directory: options.evidence) else { fail("cannot open evidence \(options.evidence)") }

    if parsed.flags.contains("--detach") {
        // Re-run this same command, minus --detach, in a new session, and
        // return at once: the supervisor then belongs to launchd, not to the
        // Bash task (see Proc.spawnDetached).
        let me = Proc.canonical(Bundle.main.executablePath ?? CommandLine.arguments[0])
        var again = Array(CommandLine.arguments.dropFirst()).filter { $0 != "--detach" }
        if !again.contains("--") { again.append("--") }
        do {
            let pid = try Proc.spawnDetached(path: me, arguments: again, stdout: evidence.url("icewatch-stdout.txt").path, stderr: evidence.url("icewatch-stderr.txt").path)
            print("icewatch detached: pid \(pid)")
            exit(0)
        } catch {
            fail("detach failed: \(error.localizedDescription)")
        }
    }
    guard let reader = BarReader() else { fail("no display") }

    let supervisor = Supervisor(options: options, evidence: evidence, reader: reader, executable: executable)
    if let problem = supervisor.arm() {
        evidence.record("armFailed", ["reason": problem])
        fail(problem)
    }
    supervisor.run()

default:
    fail("unknown command \(command)")
}
