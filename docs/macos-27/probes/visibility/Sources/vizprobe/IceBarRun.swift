// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q20-Q22): the three
// route C commands. Every decision is `IceBarRunCore`'s; this file is I/O.
//
//   vizprobe icebar-run --apps <dir> --evidence-root <dir> --expect-user <name>
//       --owner-user <name> --expect-geometry <WxH:lo-hi>
//                                 the sitting: S0, then S-adv, then S1, one
//                                 `icebar-step` process per step, Chinese
//                                 progress lines and route C 7a's final line
//   vizprobe icebar-step ...      one step (`StepArguments`), writes result.json
//   vizprobe icebar-dry --apps <dir>
//                                 launches nothing, captures nothing: bundles,
//                                 templates (K1's sha256), the start-up check,
//                                 the rosters
import AppKit
import C2Core
import Foundation
import IceBarClaim
import IceBarOracle
import IceBarRunCore
import IceBarStage
import IceCore
import MenuBarCapture
import VZGlyphs

/// Risk K2 (open, owner): how S-adv's dark and light bar are produced within
/// one sitting (E3 vs E5). Until the owner decides, S-adv does not run.
enum AppearanceDecision {
    static let decided = false
}

enum IceBarStepCommand {
    static func run(_ arguments: [String]) -> Never {
        let step: StepArguments
        switch StepArguments.parse(arguments) {
        case .success(let value): step = value
        case .failure(let error): fail("icebar-step: \(error)")
        }
        let apps = URL(fileURLWithPath: step.appsPath)
        LiveEvidence.directoryOverride = URL(fileURLWithPath: step.evidencePath)
        let binaries = ["vizprobe": URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath(),
                        "vzhelper": apps.appendingPathComponent("Target.app/Contents/MacOS/vzhelper")]
        let geometry = NSScreen.main.flatMap { BarGeometry(screen: $0) }
        let evidence: LiveEvidence
        do {
            evidence = try LiveEvidence(binaryURLs: binaries, arguments: arguments, geometry: geometry, parameters: .preRegistered, suffix: "icebar-step")
        } catch {
            fail("icebar-step: cannot create \(step.evidencePath): \(error)")
        }
        let registry = LaunchedHelpers()
        let finisher = StepFinisher(evidence: evidence)
        for number in [SIGINT, SIGTERM, SIGHUP] { finisher.stop(on: number, registry: registry) }
        signal(SIGPIPE, SIG_IGN)
        DispatchQueue.global().asyncAfter(deadline: .now() + step.watchdogMinutes * 60) {
            registry.requestQuitAll()
            finisher.finish(StepReport(status: .inconclusive, reason: "watchdog after \(step.watchdogMinutes) min"), code: 2)
        }
        do {
            let environment = try IceBarLiveWiring.environment(apps: apps, evidence: evidence, registry: registry)
            let templates = try IceBarLiveWiring.templates()
            let report = IceBarStep(environment: environment, plan: step.plan(glyphOrder: Glyph.allCases.map(\.rawValue)), templates: templates).run()
            finisher.finish(report, code: report.status == .completed ? 0 : 1)
        } catch {
            finisher.finish(StepReport(status: .inconclusive, reason: "wiring: \(error)"), code: 1)
        }
    }
}

/// Writes `result.json` and the hashed final manifest exactly once, whoever gets there first.
final class StepFinisher: @unchecked Sendable {
    private let evidence: LiveEvidence
    private let lock = NSLock()
    private var done = false
    private var sources = [DispatchSourceSignal]()

    init(evidence: LiveEvidence) {
        self.evidence = evidence
    }

    func stop(on number: Int32, registry: LaunchedHelpers) {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { [self] in
            registry.requestQuitAll()
            finish(StepReport(status: .inconclusive, reason: "signal \(number)"), code: 3)
        }
        source.resume()
        sources.append(source)
    }

    func finish(_ report: StepReport, code: Int32) -> Never {
        lock.lock()
        if done {
            lock.unlock()
            while true { sleep(60) }
        }
        done = true
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            try? data.write(to: evidence.directory.appendingPathComponent("result.json"))
        }
        evidence.record("step.result", ["status": report.status.rawValue, "reason": report.reason ?? ""])
        evidence.close()
        exit(code)
    }
}

enum IceBarRunCommand {
    static func run(_ arguments: [String]) -> Never {
        guard let apps = option("--apps", in: arguments), let rootPath = option("--evidence-root", in: arguments),
              let expectedUser = option("--expect-user", in: arguments), let ownerUser = option("--owner-user", in: arguments),
              let expectedGeometry = option("--expect-geometry", in: arguments).flatMap(C2Guards.Geometry.init(spec:))
        else { fail("icebar-run: --apps, --evidence-root, --expect-user, --owner-user and --expect-geometry are required") }
        guard C2Guards.userAllowed(current: NSUserName(), expected: expectedUser, owner: ownerUser) else { fail("icebar-run: refused -- this is not the isolated account") }
        guard C2RunCommand.sessionOnConsole() else { fail("icebar-run: refused -- this session is not the one on screen") }
        guard let screen = NSScreen.main, let bar = BarGeometry(screen: screen),
              expectedGeometry.matches(C2Guards.Geometry(widthPt: bar.widthPt, heightPt: bar.heightPt, notchLo: bar.notch?.lo, notchHi: bar.notch?.hi))
        else { fail("icebar-run: refused -- the display does not match --expect-geometry") }
        guard C2Guards.rosterAllowed(bundleIDs: BarScan.items().map(\.bundleID)) else { fail("icebar-run: refused -- the bar has a non-system item") }
        let directory = URL(fileURLWithPath: rootPath).appendingPathComponent("\(LiveEvidence.timestamp(Date(), format: "yyyyMMdd-HHmmss"))-icebar")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false) } catch {
            fail("icebar-run: cannot create \(directory.path): \(error)")
        }
        let caffeinate = Process()
        caffeinate.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        caffeinate.arguments = ["-d", "-i", "-w", "\(getpid())"]
        try? caffeinate.run()
        let sitting = IceBarSitting(apps: apps, directory: directory)
        let result = sitting.run()
        sitting.log.record(["event": "result", "result": "\(result)"])
        sitting.log.writeFinal(["result": "\(result)"])
        caffeinate.terminate()
        print(ProgressLine.final(result, directory: directory.path))
        switch result {
        case .completed: exit(0)
        case .failed: exit(1)
        case .interrupted: exit(4)
        case .safetyStop: exit(3)
        }
    }
}

/// One sitting, as `SittingDriver` asks for it: each step is one child
/// process, trusted only through its verified final manifest.
final class IceBarSitting {
    let apps: String
    let directory: URL
    let log: RunnerLog
    private let started = Date()
    private var step = 0

    init(apps: String, directory: URL) {
        self.apps = apps
        self.directory = directory
        log = RunnerLog(directory: directory)
    }

    func run() -> SittingResult {
        var driver = SittingDriver(appearanceDecided: AppearanceDecision.decided)
        while true {
            switch driver.next() {
            case .finished(let result):
                return result
            case .run(let request):
                switch runStep(request) {
                case .ended(let result): driver.end(result)
                case .report(let report): driver.record(report)
                }
            }
        }
    }

    enum StepOutcome {
        case report(StepReport)
        case ended(SittingResult)
    }

    /// The session leaving the screen or a report that does not verify ends the sitting here.
    private func runStep(_ request: SittingRequest) -> StepOutcome {
        step += 1
        guard C2RunCommand.sessionOnConsole() else { return .ended(.interrupted("this session left the screen before step \(step)")) }
        let stepDirectory = directory.appendingPathComponent(String(format: "%03d-%@", step, request.name.replacingOccurrences(of: " ", with: "-")))
        let arguments = StepArguments(kind: request.kind, members: request.members, menu: request.menu, appsPath: apps, evidencePath: stepDirectory.path)
        log.record(["event": "start", "step": step, "name": request.name, "arguments": arguments.arguments])
        progress(ProgressLine.start(step: step, name: request.name, clock: clock(), elapsed: elapsed()))
        let (code, leftConsole) = C2RunCommand.runChild(arguments.arguments)
        let report = Self.readReport(stepDirectory)
        let status = report?.status.rawValue ?? "unverified"
        log.record(["event": "end", "step": step, "exit": Int(code), "status": status, "reason": report?.reason ?? ""])
        progress(ProgressLine.end(step: step, name: request.name, status: status, clock: clock(), elapsed: elapsed()))
        if leftConsole { return .ended(.interrupted("this session left the screen during step \(step)")) }
        guard let report else { return .ended(.safetyStop("step \(step) left no verified report")) }
        return .report(report)
    }

    /// `result.json`, trusted only through the step's verified final manifest.
    static func readReport(_ directory: URL) -> StepReport? {
        guard C2RunCommand.verifiedFinalManifest(directory) != nil,
              let result = try? Data(contentsOf: directory.appendingPathComponent("result.json"))
        else { return nil }
        return try? JSONDecoder().decode(StepReport.self, from: result)
    }

    private func clock() -> String { LiveEvidence.timestamp(Date(), format: "HH:mm:ss") }
    private func elapsed() -> Int { Int(Date().timeIntervalSince(started)) }
    private func progress(_ line: String) { FileHandle.standardError.write(Data((line + "\n").utf8)) }
}

enum IceBarDryCommand {
    /// Nothing launched, nothing captured, no event posted.
    static func run(_ arguments: [String]) -> Never {
        guard let apps = option("--apps", in: arguments) else { fail("icebar-dry: missing --apps <dir>") }
        var problems = [String]()
        for (app, bundle) in [(Roster.memberApp, Roster.memberBundleID), (Roster.otherApp, Roster.otherBundleID), (Roster.menusApp, Roster.otherBundleID)] {
            let url = URL(fileURLWithPath: apps).appendingPathComponent(app)
            if !LiveHelperLauncher().validateBundle(at: url, expectedBundleID: bundle) { problems.append("\(app) is not a \(bundle) helper bundle") }
        }
        do {
            let templates = try IceBarLiveWiring.templates()
            print("icebar-dry: templates \(templates.helpers.count) glyphs + chevron \(templates.chevron.map { "\($0.width)x\($0.height)" } ?? "none") (K1 sha256 as pre-registered)")
        } catch {
            problems.append("templates: \(error)")
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 0
        let startup = StartupCheck.evaluate(claim: .preRegistered, detector: .preRegistered, scale: Double(scale))
        print("icebar-dry: start-up check at scale \(scale): \(startup)")
        let order = Glyph.allCases.map(\.rawValue)
        for (stage, members, coloured) in [("S0", SittingDriver.s0.members, false), ("S-adv", SittingDriver.sAdvMembers, true), ("S1 k16", Roster.maxMembers, false)] {
            let roster = (try? Roster.entries(glyphOrder: order, members: members, colouredMembers: coloured)) ?? []
            print("icebar-dry: \(stage) roster " + roster.map { "\($0.id)/\($0.role.rawValue)\($0.coloured ? "/coloured" : "")@\($0.bundleID)" }.joined(separator: " "))
        }
        for problem in problems { print("icebar-dry: PROBLEM \(problem)") }
        exit(problems.isEmpty ? 0 : 1)
    }
}
