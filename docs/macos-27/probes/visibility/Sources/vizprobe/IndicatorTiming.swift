// `vizprobe indicator --apps <dir>`: when the system's capture indicator comes
// and goes, and what it moves (plan 2026-10-09-lab-first-run-followup, S1).
//
// Two sacrificial reference helpers (`com.icespike4.protected`), then capture
// sessions through Ice's own capturer and bracket (`CGWindowListStripCapturer`,
// `Sampler`) in four shapes, each three times with 30 s of no capturing after:
//   A  continuous, 30 s
//   B  a baseline's shape (4 warm-up captures, then samples for 3 s)
//   C  an observation's shape (4 warm-up captures, 2 samples)
//   D  a baseline, 2 s, then five observations 1 s apart
//   E  fifteen observations, one every 3.5 s (a calibration walk's cadence)
//   G  one observation with every retry (2 samples five times, 1 s apart)
// `--shapes A,B,...` runs only those (E and G twice each).
// Meanwhile the helpers' and MenuBarAgent's Accessibility frames are read four
// times a second. Read-only towards everything but our own helpers: nothing is
// moved, clicked or resized. Side effects: two status items for about nine
// minutes, the capture indicator, the helper's defaults domain (deleted).
// Evidence: ~/IceReverse-evidence/<run id>/ (the captures show the owner's bar).
import AppKit
import Foundation
import IceCore
import MenuBarCapture

enum IndicatorTimingCommand {
    private static let helperBundleID = "com.icespike4.protected"
    private static let quiet = 30.0
    private static let watchdogSeconds = 900.0

    static func run(_ arguments: [String]) -> Never {
        guard let appsPath = option("--apps", in: arguments) else { fail("indicator: missing --apps <dir>") }
        let app = URL(fileURLWithPath: appsPath).appendingPathComponent("Protected.app")
        guard FileManager.default.fileExists(atPath: app.path) else { fail("indicator: no Protected.app in \(appsPath)") }
        guard AXIsProcessTrusted() else { fail("indicator: no Accessibility permission") }
        guard NSWorkspace.shared.runningApplications.allSatisfy({ $0.bundleIdentifier != helperBundleID }) else {
            fail("indicator: a helper is already running")
        }
        guard let screen = NSScreen.main else { fail("indicator: no screen") }

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("IceReverse-evidence/\(stamp.string(from: Date()))-indicator")
        let log: IndicatorLog
        do {
            log = try IndicatorLog(directory: directory)
        } catch {
            fail("indicator: cannot write \(directory.path): \(error)")
        }

        deleteHelperDomain()
        let helpers = Helpers()
        // Every way out quits the helpers and empties their domain.
        let stop: @Sendable (Int32, String?) -> Never = { code, why in
            if let why { FileHandle.standardError.write(Data("vizprobe: indicator: \(why)\n".utf8)) }
            helpers.quitAll()
            deleteHelperDomain()
            exit(code)
        }
        signal(SIGPIPE, SIG_IGN)
        var sources = [DispatchSourceSignal]()
        for number in [SIGINT, SIGTERM, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { stop(3, "signal \(number)") }
            source.resume()
            sources.append(source)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + watchdogSeconds) { stop(2, "watchdog") }

        var items = [String: pid_t]()
        for (id, glyph) in [("ref1", "reference"), ("ref2", "alt")] {
            do {
                let helper = try HelperControl(
                    appURL: app,
                    bundleID: helperBundleID,
                    role: id,
                    arguments: ["--items", "1", "--identifiers", "vz-indicator-\(id)", "--glyphs", glyph, "--lifetime", "\(Int(watchdogSeconds))"],
                    controllerPID: getpid()
                )
                helpers.add(helper)
                guard helper.awaitReply("up", timeout: 5) != nil else { stop(1, "\(id) did not come up") }
                items[id] = helper.pid
            } catch {
                stop(1, "\(error)")
            }
        }

        let reader = LiveMenuBarAXReader(screen: screen)
        let capturer = LoggingCapturer(log: log)
        let sampler = Sampler(capturer: capturer, axReader: reader)
        let watched = items
        Thread.detachNewThread {
            while true {
                log.axRead(reader.read(items: watched))
                Thread.sleep(forTimeInterval: 0.25)
            }
        }

        func warmUp() {
            for _ in 0..<SessionShape.warmUpCount {
                _ = capturer.capture()
                Pump.run(SessionShape.warmUpSpacing)
            }
        }
        /// Samples until both the count and the span, where given, are met.
        func samples(count: Int = 0, span: Double = 0) {
            let start = ProcessInfo.processInfo.systemUptime
            var taken = 0
            while true {
                if sampler.sample(items: watched) == nil { log.event("sampleFailed") }
                taken += 1
                if taken >= count, ProcessInfo.processInfo.systemUptime - start >= span { break }
                Pump.run(SessionShape.sampleSpacing)
            }
        }
        func baseline() {
            warmUp()
            samples(count: SessionShape.baselineMinSamples, span: SessionShape.baselineMinSpan)
        }
        func observation() {
            warmUp()
            samples(count: SessionShape.observationSamples)
        }
        let shapes: [(String, () -> Void)] = [
            ("A", { samples(span: 30) }),
            ("B", baseline),
            ("C", observation),
            ("D", {
                baseline()
                Pump.run(2)
                for _ in 0..<5 {
                    observation()
                    Pump.run(1)
                }
            }),
            ("E", {
                for _ in 0..<15 {
                    let start = ProcessInfo.processInfo.systemUptime
                    observation()
                    Pump.run(max(0, 3.5 - (ProcessInfo.processInfo.systemUptime - start)))
                }
            }),
            ("G", {
                warmUp()
                for attempt in 0..<5 {
                    samples(count: SessionShape.observationSamples)
                    if attempt < 4 { Pump.run(1) }
                }
            }),
        ]
        let chosen = option("--shapes", in: arguments)?.split(separator: ",").map(String.init) ?? ["A", "B", "C", "D"]

        log.phase("settle", "begin")
        Pump.run(quiet)
        for (name, shape) in shapes where chosen.contains(name) {
            for round in 1...(["E", "G"].contains(name) ? 2 : 3) {
                let phase = "\(name)\(round)"
                capturer.phase = phase
                log.phase(phase, "begin")
                shape()
                log.phase(phase, "captureEnd")
                Pump.run(quiet)
                log.phase(phase, "end")
            }
        }
        print(directory.path)
        stop(0, nil)
    }

    private static func deleteHelperDomain() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["delete", helperBundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

private final class Helpers: @unchecked Sendable {
    private let lock = NSLock()
    private var all = [HelperControl]()

    func add(_ helper: HelperControl) {
        lock.lock()
        defer { lock.unlock() }
        all.append(helper)
    }

    func quitAll() {
        lock.lock()
        let helpers = all
        lock.unlock()
        helpers.forEach { $0.quit() }
    }
}

/// The cadence of Ice's own sessions (`HiddenLengthObserver.liveWarmUpCount`,
/// `HidingVerification`'s warm-up spacing, `DetectorParameters.preRegistered`).
private enum SessionShape {
    static let warmUpCount = 4
    static let warmUpSpacing = 0.25
    static let sampleSpacing = DetectorParameters.preRegistered.minSampleSpacing
    static let baselineMinSamples = DetectorParameters.preRegistered.baselineMinSamples
    static let baselineMinSpan = DetectorParameters.preRegistered.baselineMinSpan
    static let observationSamples = DetectorParameters.preRegistered.minSamples
}

/// Ice's capturer, with every capture's time recorded and a strip kept about
/// every two seconds.
private final class LoggingCapturer: StripCapturing, @unchecked Sendable {
    private let inner = CGWindowListStripCapturer()
    private let log: IndicatorLog
    var phase = "settle"
    private var lastKept = 0.0

    init(log: IndicatorLog) {
        self.log = log
    }

    func capture() -> StripImage? {
        let image = inner.capture()
        let now = ProcessInfo.processInfo.systemUptime
        var kept: String?
        if let image, now - lastKept >= 2 {
            lastKept = now
            kept = log.keep(image, phase: phase, at: now)
        }
        log.capture(phase: phase, ok: image != nil, kept: kept)
        return image
    }
}

private final class IndicatorLog: @unchecked Sendable {
    private let directory: URL
    private let handle: FileHandle
    private let lock = NSLock()

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("captures"), withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("samples.jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    private func write(_ fields: [String: Any]) {
        var object = fields
        object["t"] = ProcessInfo.processInfo.systemUptime
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        lock.lock()
        defer { lock.unlock() }
        handle.write(data + Data("\n".utf8))
    }

    func phase(_ name: String, _ what: String) {
        write(["k": "phase", "name": name, "what": what, "wall": Date().timeIntervalSince1970])
    }

    func event(_ name: String) {
        write(["k": name])
    }

    func capture(phase: String, ok: Bool, kept: String?) {
        write(["k": "cap", "phase": phase, "ok": ok, "kept": kept ?? NSNull()])
    }

    func axRead(_ snapshot: MenuBarAXSnapshot?) {
        guard let snapshot else {
            write(["k": "ax", "failed": true])
            return
        }
        write([
            "k": "ax",
            "items": snapshot.itemFrames.mapValues { [$0.minX, $0.width] },
            "agent": snapshot.agentFrames.map { [$0.minX, $0.width] }.sorted { $0[0] < $1[0] },
        ])
    }

    func keep(_ image: StripImage, phase: String, at time: Double) -> String? {
        let name = String(format: "%@-%.2f.png", phase, time)
        do {
            try image.writePNG(to: directory.appendingPathComponent("captures/\(name)"))
            return name
        } catch {
            return nil
        }
    }
}
