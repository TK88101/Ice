// swctl — the controller for docs/plans/2026-09-18-safe-width.md.
//
//   swctl b0 [--seconds 60] [--interval 1] --git <revision>
//   swctl calibrate --b0 <b0 run dir>
//   swctl c --config narrow|mid|wide --apps <dir> --calibration <file> [--null 30] --git <revision>
//   swctl o0 --apps <dir> --calibration <file> [--repeats 3] --git <revision>
//   swctl scan --config narrow|mid|wide --apps <dir> --calibration <file> --git <revision>
//
// Every stage writes its evidence to ~/IceReverse-evidence/<run-id>/.
import AppKit

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("swctl: \(message)\n".utf8))
    exit(64)
}

func required(_ name: String, in arguments: [String]) -> String {
    guard let value = option(name, in: arguments) else {
        fail("missing \(name)")
    }
    return value
}

/// Runs a stage that puts our items in the bar, with the watchdog armed.
func runExperiment(stage: String, arguments: [String], body: (Experiment) throws -> Void) {
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.finishLaunching()
    let watchdogMinutes = option("--watchdog", in: arguments).flatMap(Double.init) ?? 25
    DispatchQueue.global().asyncAfter(deadline: .now() + watchdogMinutes * 60) {
        FileHandle.standardError.write(Data("swctl: WATCHDOG after \(watchdogMinutes) min, exiting\n".utf8))
        exit(2)
    }
    do {
        let evidence = try Evidence(stage: stage, arguments: arguments, gitRevision: gitRevision)
        let experiment = try Experiment(
            apps: URL(fileURLWithPath: required("--apps", in: arguments)),
            calibrationFile: URL(fileURLWithPath: required("--calibration", in: arguments)),
            evidence: evidence,
            capture: capture
        )
        print("evidence: \(evidence.directory.path)")
        try body(experiment)
        evidence.record("stage.done", ["stage": stage])
        evidence.close()
    } catch {
        fail("\(stage) failed: \(error)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let stage = arguments.first else {
    fail("usage: swctl <b0|calibrate|c|o0> [options]")
}
let gitRevision = option("--git", in: arguments) ?? "unknown"
_ = NSApplication.shared

let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("swctl-\(getpid()).png")
let capture = StripCapture(widthPt: 1728, heightPt: 33, deadline: 1.0, scratchFile: scratch)

switch stage {
case "b0":
    let seconds = option("--seconds", in: arguments).flatMap(Double.init) ?? 60
    let interval = option("--interval", in: arguments).flatMap(Double.init) ?? 1
    do {
        let evidence = try Evidence(stage: "b0", arguments: arguments, gitRevision: gitRevision)
        BaselineStage.run(seconds: seconds, interval: interval, evidence: evidence, capture: capture)
        evidence.close()
    } catch {
        fail("cannot create evidence directory: \(error)")
    }
case "calibrate":
    let directory = URL(fileURLWithPath: required("--b0", in: arguments))
    do {
        let calibration = try Calibrate.run(b0Directory: directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = directory.appendingPathComponent("calibration.json")
        try encoder.encode(calibration).write(to: file)
        print("calibration: \(calibration.items.count) items, unused colours \(calibration.unusedColours), negative control matches \(calibration.negativeControlMatches)")
        for item in calibration.items {
            print(String(format: "  %-48@ x=%7.1f w=%5.1f %@ worst=%.3f presence>=%d", item.id as NSString, item.x, item.w, item.kind as NSString, item.worstMismatchAtZero, item.presenceMinimum))
        }
        print(file.path)
    } catch {
        fail("calibrate failed: \(error)")
    }
case "c":
    guard let config = FrontConfig.all[required("--config", in: arguments)] else {
        fail("unknown --config")
    }
    let nullSeconds = option("--null", in: arguments).flatMap(Double.init) ?? 30
    runExperiment(stage: "c-\(config.name)", arguments: arguments) { experiment in
        try Stages.calibrationAndNullControl(experiment, config: config, nullSeconds: nullSeconds)
    }
case "o0":
    let repeats = option("--repeats", in: arguments).flatMap(Int.init) ?? 3
    runExperiment(stage: "o0", arguments: arguments) { experiment in
        try StageO0.run(experiment, repeats: repeats)
    }
case "scan":
    guard let config = FrontConfig.all[required("--config", in: arguments)] else {
        fail("unknown --config")
    }
    runExperiment(stage: "scan-\(config.name)", arguments: arguments) { experiment in
        try StageScan.run(experiment, config: config)
    }
case "o1":
    let widths = required("--widths", in: arguments).split(separator: ",").compactMap { Double($0) }
    let repeats = option("--repeats", in: arguments).flatMap(Int.init) ?? 3
    runExperiment(stage: "o1", arguments: arguments) { experiment in
        try StageM.runO1(experiment, widths: widths, repeats: repeats)
    }
case "m":
    guard let config = FrontConfig.all[required("--config", in: arguments)] else {
        fail("unknown --config")
    }
    let parameters = StageM.Parameters(
        transitions: Transition.parse(required("--brackets", in: arguments)),
        edgeBound: option("--edge-bound", in: arguments).flatMap(Double.init),
        reset: ResetKind(rawValue: option("--reset", in: arguments) ?? "full") ?? .full,
        hold: option("--hold", in: arguments).flatMap(Double.init) ?? 0,
        repeats: option("--repeats", in: arguments).flatMap(Int.init) ?? 3,
        candidate: option("--candidate", in: arguments).flatMap(Double.init)
    )
    runExperiment(stage: "m-\(config.name)", arguments: arguments) { experiment in
        try StageM.run(experiment, config: config, parameters: parameters)
    }
default:
    fail("unknown stage \(stage)")
}
