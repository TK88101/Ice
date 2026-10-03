// IceBar build plan T0 (docs/plans/2026-10-03-icebar-build.md, section 7
// note 1): the two commands. Every decision is `SpikeCore`'s or
// `SpikeStage`'s; this file is guards and I/O.
//
//   vizprobe spike-run --apps <dir> --evidence-root <dir> --expect-user <name>
//       --owner-user <name> --expect-geometry <WxH:lo-hi>
//       [--members 1,2,4,8] [--menus short,mid] [--lengths from:through:step] [--no-b]
//                                 spike A (band per k and menu), then spike B
//                                 (AXPress on the pushed-off member) in the
//                                 isolated account; the last lines are the
//                                 owner's two answers and, if a stop rule
//                                 fires, the one question
//   vizprobe spike-dry --apps <dir>
//                                 launches nothing, captures nothing: bundles,
//                                 vzhelper's --menu, templates, scale, the plan
import AppKit
import C2Core
import Foundation
import IceBarRunCore
import IceBarStage
import IceCore
import MenuBarCapture
import SpikeCore
import SpikeStage
import VZGlyphs

enum SpikeRunCommand {
    static let watchdogMinutes = 90.0

    static func run(_ arguments: [String]) -> Never {
        let parsed: SpikeArguments
        switch SpikeArguments.parse(arguments) {
        case .success(let value): parsed = value
        case .failure(let error): fail("spike-run: \(error)")
        }
        guard let expectedGeometry = C2Guards.Geometry(spec: parsed.expectedGeometry) else { fail("spike-run: bad --expect-geometry") }
        guard C2Guards.userAllowed(current: NSUserName(), expected: parsed.expectedUser, owner: parsed.ownerUser) else {
            fail("spike-run: refused -- this is not the isolated account")
        }
        guard C2RunCommand.sessionOnConsole() else { fail("spike-run: refused -- this session is not the one on screen") }
        guard let screen = NSScreen.main, let bar = BarGeometry(screen: screen),
              expectedGeometry.matches(C2Guards.Geometry(widthPt: bar.widthPt, heightPt: bar.heightPt, notchLo: bar.notch?.lo, notchHi: bar.notch?.hi))
        else { fail("spike-run: refused -- the display does not match --expect-geometry") }
        guard C2Guards.rosterAllowed(bundleIDs: BarScan.items().map(\.bundleID)) else { fail("spike-run: refused -- the bar has a non-system item") }

        let apps = URL(fileURLWithPath: parsed.appsPath)
        let directory = URL(fileURLWithPath: parsed.evidenceRoot).appendingPathComponent("\(LiveEvidence.timestamp(Date(), format: "yyyyMMdd-HHmmss"))-spike")
        LiveEvidence.directoryOverride = directory
        let binaries = ["vizprobe": URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath(),
                        "vzhelper": apps.appendingPathComponent("Target.app/Contents/MacOS/vzhelper")]
        let evidence: LiveEvidence
        do {
            evidence = try LiveEvidence(binaryURLs: binaries, arguments: arguments, geometry: bar, parameters: .preRegistered, suffix: "spike")
        } catch {
            fail("spike-run: cannot create \(directory.path): \(error)")
        }
        let registry = LaunchedHelpers()
        let finisher = SpikeFinisher(evidence: evidence, directory: directory)
        for number in [SIGINT, SIGTERM, SIGHUP] { finisher.stop(on: number, registry: registry) }
        signal(SIGPIPE, SIG_IGN)
        DispatchQueue.global().asyncAfter(deadline: .now() + watchdogMinutes * 60) {
            registry.requestQuitAll()
            finisher.finish(lines: ["結果：中斷｜watchdog after \(Int(watchdogMinutes)) min"], code: 2)
        }
        let caffeinate = Process()
        caffeinate.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        caffeinate.arguments = ["-d", "-i", "-w", "\(getpid())"]
        try? caffeinate.run()
        defer { caffeinate.terminate() }
        do {
            let environment = try IceBarLiveWiring.environment(apps: apps, evidence: evidence, registry: registry)
            let templates = try IceBarLiveWiring.templates()
            let plan = SpikeStagePlan(profiles: SpikeAPlan.profiles(members: parsed.members, menus: parsed.menus), lengths: parsed.lengths,
                                      runB: parsed.runB, glyphOrder: Glyph.allCases.map(\.rawValue),
                                      helperLifetimeSeconds: StepArguments.helperLifetimeSeconds)
            let started = Date()
            let stage = SpikeStage(environment: environment, templates: templates, plan: plan, press: LiveSpikePress()) { line in
                let elapsed = Int(Date().timeIntervalSince(started))
                let text = String(format: "spike-run: %@ [%@, %d:%02d]\n", line, LiveEvidence.timestamp(Date(), format: "HH:mm:ss"), elapsed / 60, elapsed % 60)
                try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
            }
            let result = stage.run()
            finisher.write(result)
            let final = result.stopQuestion.map { "結果：停下｜\($0)｜\(directory.path)" } ?? "結果：完成｜T0 兩題都有答案｜\(directory.path)"
            finisher.finish(lines: result.lines + [final], code: result.stopQuestion == nil ? 0 : 1)
        } catch {
            finisher.finish(lines: ["結果：中斷｜wiring: \(error)｜\(directory.path)"], code: 1)
        }
    }
}

/// Writes `result.json`, `lines.txt` and the hashed final manifest exactly once, whoever gets there first.
final class SpikeFinisher: @unchecked Sendable {
    struct Written: Codable {
        let a: SpikeAResult
        let b: SpikeBResult?
        let bProblem: String?
        let lines: [String]
        let stopQuestion: String?
    }

    private let evidence: LiveEvidence
    private let directory: URL
    private let lock = NSLock()
    private var done = false
    private var sources = [DispatchSourceSignal]()

    init(evidence: LiveEvidence, directory: URL) {
        self.evidence = evidence
        self.directory = directory
    }

    func stop(on number: Int32, registry: LaunchedHelpers) {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { [self] in
            registry.requestQuitAll()
            finish(lines: ["結果：中斷｜signal \(number)｜\(directory.path)"], code: 3)
        }
        source.resume()
        sources.append(source)
    }

    func write(_ result: SpikeRunResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let written = Written(a: result.a, b: result.b, bProblem: result.bProblem, lines: result.lines, stopQuestion: result.stopQuestion)
        if let data = try? encoder.encode(written) {
            try? data.write(to: directory.appendingPathComponent("result.json"))
        }
    }

    func finish(lines: [String], code: Int32) -> Never {
        lock.lock()
        if done {
            lock.unlock()
            while true { sleep(60) }
        }
        done = true
        try? (lines.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("lines.txt"), atomically: true, encoding: .utf8)
        evidence.record("spike.result", ["lines": lines, "code": Int(code)])
        evidence.close()
        for line in lines { print(line) }
        exit(code)
    }
}

enum SpikeDryCommand {
    /// Nothing launched, nothing captured, no event posted.
    static func run(_ arguments: [String]) -> Never {
        guard let appsPath = option("--apps", in: arguments) else { fail("spike-dry: missing --apps <dir>") }
        let apps = URL(fileURLWithPath: appsPath)
        var problems = [String]()
        for (app, bundle) in [(Roster.memberApp, Roster.memberBundleID), (Roster.otherApp, Roster.otherBundleID), (Roster.menusApp, Roster.otherBundleID)] {
            if !LiveHelperLauncher().validateBundle(at: apps.appendingPathComponent(app), expectedBundleID: bundle) {
                problems.append("\(app) is not a \(bundle) helper bundle")
            }
        }
        let helperBinary = apps.appendingPathComponent("Target.app/Contents/MacOS/vzhelper")
        if let data = try? Data(contentsOf: helperBinary) {
            let hasMenu = data.range(of: Data(SpikeHelperFlags.menu.utf8)) != nil && data.range(of: Data(SpikeHelperFlags.closeMenu.utf8)) != nil
            print("spike-dry: vzhelper knows \(SpikeHelperFlags.menu) and \(SpikeHelperFlags.closeMenu): \(hasMenu)")
            if !hasMenu { problems.append("the staged vzhelper does not know \(SpikeHelperFlags.menu)") }
        } else {
            problems.append("cannot read \(helperBinary.path)")
        }
        do {
            let templates = try IceBarLiveWiring.templates()
            print("spike-dry: templates \(templates.helpers.count) glyphs + chevron \(templates.chevron.map { "\($0.width)x\($0.height)" } ?? "none") (K1 sha256 as recorded)")
            if templates.chevron == nil { problems.append("no chevron template (ICEBAR_K_DIR)") }
        } catch {
            problems.append("templates: \(error)")
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 0
        print("spike-dry: screen scale \(scale) (the templates are at 2)")
        if scale != 2 { problems.append("screen scale \(scale) is not 2") }
        if let screen = NSScreen.main, let bar = BarGeometry(screen: screen) {
            print("spike-dry: geometry \(C2Guards.Geometry(widthPt: bar.widthPt, heightPt: bar.heightPt, notchLo: bar.notch?.lo, notchHi: bar.notch?.hi).spec)")
        }
        let profiles = SpikeAPlan.profiles(members: SpikeAPlan.standardMembers, menus: SpikeAPlan.standardMenus)
        let lengths = SpikeLengths.standard.values
        print("spike-dry: spike A profiles " + profiles.map(\.name).joined(separator: " "))
        print("spike-dry: lengths \(lengths.count): \(Band.format(lengths[0])) ... \(Band.format(lengths[lengths.count - 1])) pt by \(Band.format(SpikeLengths.standard.step)), each a jump from rest")
        let order = Glyph.allCases.map(\.rawValue)
        for k in SpikeAPlan.standardMembers {
            let roster = (try? Roster.entries(glyphOrder: order, members: k, colouredMembers: false)) ?? []
            print("spike-dry: k=\(k) roster " + roster.map { "\($0.id)/\($0.role.rawValue)@\($0.bundleID)" }.joined(separator: " "))
        }
        if let member = (try? Roster.entries(glyphOrder: order, members: 1, colouredMembers: false))?.first(where: { $0.role == .member }) {
            print("spike-dry: spike B member arguments " + SpikeHelperFlags.withMenu(Roster.arguments(member, lifetimeSeconds: StepArguments.helperLifetimeSeconds)).joined(separator: " "))
        }
        print("spike-dry: spike B \(SpikeBRules.trials) trials, a path works at \(SpikeBRules.needed), menu within \(SpikeBRules.openTimeout) s, pop-up window layer \(SpikeBRules.popUpMenuWindowLayer)")
        print("spike-dry: launched nothing, captured nothing")
        for problem in problems { print("spike-dry: PROBLEM \(problem)") }
        exit(problems.isEmpty ? 0 : 1)
    }
}
