// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q10-Q22): one step
// process -- guards, launch in placement order, the placement gate, warm-up,
// the step's body (S0, an S-adv sweep, S-adv's `«` rest state, an S1 band
// batch or midpoint confirmation), and a teardown that leaves nothing behind.
import C2Core
import IceBarClaim
import IceBarOracle
import IceBarRunCore
import IceCore

public final class IceBarStep {
    public static let bundles = ["com.icespike4.target", "com.icespike4.protected"]
    public static let s0LengthPt = 728.0
    /// S-adv's `«` rest state: at most this long collecting episodes (Q17).
    public static let chevronTimeBoxSeconds = 1200.0
    static let launchTimeoutSeconds = 5.0
    static let discoverySeconds = 5.0

    let environment: IceBarEnvironment
    let plan: StepPlan
    let templates: StageTemplates
    let probe: Probe
    let cadence = CadenceParameters.preRegistered
    var lastChange = 0.0
    var spacer: IceBarHelper?
    private var launched = [(id: String, helper: IceBarHelper)]()
    private var menusLaunched = false

    public init(environment: IceBarEnvironment, plan: StepPlan, templates: StageTemplates) {
        self.environment = environment
        self.plan = plan
        self.templates = templates
        probe = Probe(environment: environment, templates: templates)
    }

    var s1Rules: Bool {
        switch plan.kind {
        case .s1Bracket, .s1Confirm: true
        default: false
        }
    }

    /// The bounds recorder every capture of this step went through (tests read it).
    public var recorder: BoundsRecordingCapturer { probe.recorder }
    public var judgedCaptures: Int { probe.judgedCaptures }

    public func run() -> StepReport {
        guard StartupCheck.evaluate(claim: .preRegistered, detector: .preRegistered, scale: environment.geometry.scale) == .ready else {
            return StepReport(status: .inconclusive, reason: "start-up check failed at scale \(environment.geometry.scale)")
        }
        let roster: [RosterEntry]
        do {
            roster = try Roster.entries(glyphOrder: plan.glyphOrder, members: Roster.maxMembers, colouredMembers: plan.colouredMembers)
        } catch {
            return StepReport(status: .inconclusive, reason: "roster: \(error)")
        }
        if let missing = roster.first(where: { templates.helpers[$0.id] == nil }) {
            return StepReport(status: .inconclusive, reason: "no oracle template for \(missing.id)")
        }
        let count = Roster.visibleGlyphs.count + plan.members
        var report = launch(Array(roster.prefix(count))) ?? body(spare: Array(roster.dropFirst(count)))
        report.roster = probe.roster
        if let problem = teardown() {
            report.status = .safetyStop
            report.reason = problem
        }
        environment.evidence.record("step", ["status": report.status.rawValue, "reason": report.reason ?? ""])
        return report
    }

    // MARK: - Launch and teardown

    /// Q11, Q21: guards, Menus, the visible helpers, the spacer, the members; the gate; warm-up.
    private func launch(_ roster: [RosterEntry]) -> StepReport? {
        if let foreign = environment.barOwners().first(where: { !$0.bundleID.hasPrefix("com.apple.") }) {
            return StepReport(status: .safetyStop, reason: "the bar has a non-system item before launch: \(foreign.bundleID)")
        }
        for bundle in Self.bundles where !environment.forgetDomain(bundle) || environment.domainKeys(bundle) != [] {
            return StepReport(status: .inconclusive, reason: "helper domain \(bundle) not empty before launch")
        }
        if let problem = environment.menus.launchAndCalibrate(plan.menu) {
            return StepReport(status: .inconclusive, reason: "menus: \(problem)")
        }
        menusLaunched = true
        for entry in roster where entry.role == .visible {
            guard launchGlyph(entry) else { return StepReport(status: .inconclusive, reason: "\(entry.id) did not come up") }
        }
        guard let spacerHelper = environment.launcher.launch(app: "Protected.app", bundleID: Self.bundles[1],
                                                             arguments: Roster.spacerArguments(lifetimeSeconds: plan.helperLifetimeSeconds)),
              spacerHelper.awaitUp(timeout: Self.launchTimeoutSeconds)
        else { return StepReport(status: .inconclusive, reason: "the spacer did not come up") }
        spacer = spacerHelper
        launched.append(("spacer", spacerHelper))
        probe.registerSpacer(pid: spacerHelper.pid)
        guard discovered("spacer") else { return StepReport(status: .inconclusive, reason: "the spacer was not discovered") }
        for entry in roster where entry.role == .member {
            guard launchGlyph(entry) else { return StepReport(status: .inconclusive, reason: "\(entry.id) did not come up") }
        }
        if let report = rosterGuard() { return report }
        guard let read = environment.axReader.read(items: probe.pids) else { return StepReport(status: .inconclusive, reason: "placement read failed") }
        let placement = PlacementCheck.evaluate(frames: read.itemFrames, members: probe.members, spacer: "spacer",
                                                visible: probe.visible, barHeightPt: environment.geometry.heightPt)
        environment.evidence.record("placement", ["outcome": "\(placement)", "roster": probe.roster.map { [$0.id, $0.role.rawValue, "\($0.coloured)"] }])
        guard placement == .placed else { return StepReport(status: .inconclusive, reason: "placement gate: \(placement)") }
        guard probe.warmUp(cadence) else { return StepReport(status: .inconclusive, reason: "a warm-up capture failed") }
        lastChange = environment.clock.now()
        return nil
    }

    private func launchGlyph(_ entry: RosterEntry) -> Bool {
        guard let helper = environment.launcher.launch(app: entry.app, bundleID: entry.bundleID,
                                                       arguments: Roster.arguments(entry, lifetimeSeconds: plan.helperLifetimeSeconds)),
              helper.awaitUp(timeout: Self.launchTimeoutSeconds)
        else { return false }
        launched.append((entry.id, helper))
        probe.register(entry, pid: helper.pid)
        lastChange = environment.clock.now()
        return discovered(entry.id)
    }

    private func quitGlyph(_ id: String) {
        guard let index = launched.firstIndex(where: { $0.id == id }) else { return }
        launched[index].helper.quit(timeout: 2)
        launched.remove(at: index)
        probe.unregister(id)
        lastChange = environment.clock.now()
    }

    /// The helper's own AX frame appears within a few seconds.
    private func discovered(_ id: String) -> Bool {
        let deadline = environment.clock.now() + Self.discoverySeconds
        while environment.clock.now() <= deadline {
            if environment.axReader.read(items: probe.pids)?.itemFrames[id] != nil { return true }
            environment.clock.sleep(until: environment.clock.now() + 0.25)
        }
        return false
    }

    /// Q21: only system items and this step's own helpers.
    private func rosterGuard() -> StepReport? {
        let ours = Set(launched.map(\.helper.pid))
        if let foreign = environment.barOwners().first(where: { !$0.bundleID.hasPrefix("com.apple.") && !ours.contains($0.pid) }) {
            return StepReport(status: .safetyStop, reason: "an unexpected item on the bar: \(foreign.bundleID)")
        }
        return nil
    }

    /// Rest, quit everything, empty the domains, and check the bar holds no helper.
    private func teardown() -> String? {
        spacer?.send("rest")
        for (_, helper) in launched.reversed() { helper.quit(timeout: 2) }
        if menusLaunched { environment.menus.quit() }
        var problems = [String]()
        if let alive = launched.first(where: { $0.helper.isRunning }) { problems.append("\(alive.id) still running") }
        for bundle in Self.bundles where !environment.forgetDomain(bundle) || environment.domainKeys(bundle) != [] {
            problems.append("helper domain \(bundle) not empty")
        }
        let ours = Set(launched.map(\.helper.pid))
        if environment.barOwners().contains(where: { ours.contains($0.pid) || Self.bundles.contains($0.bundleID) }) {
            problems.append("a helper is still on the bar")
        }
        environment.evidence.record("teardown", ["problems": problems])
        return problems.isEmpty ? nil : problems.joined(separator: "; ")
    }

    // MARK: - Bodies

    private func body(spare: [RosterEntry]) -> StepReport {
        switch plan.kind {
        case .s0: return s0()
        case .sAdvSweep(let variant): return sweep(variant)
        case .sAdvChevron: return chevronRest(spare: spare)
        case .s1Bracket(let lengths): return bracket(lengths)
        case .s1Confirm(let length): return confirm(length)
        }
    }

    private var observations: [ReportB] {
        probe.episodes.all.map { ReportB(episode: $0.episode, axChevron: $0.axChevron, pixels: $0.pixels) }
    }

    private func aborted(_ why: String, keeping report: StepReport = StepReport(status: .inconclusive)) -> StepReport {
        var report = report
        report.status = .inconclusive
        report.reason = why
        report.chevronObservations = observations
        return report
    }

    /// Q15, Q13, Q16.
    private func s0() -> StepReport {
        probe.feedsBControl = true
        probe.collectsC3 = true
        var results = [S0CycleResult]()
        var measurements = [BaselineMeasurements]()
        while S0Judge.nextCycleNeeded(results) {
            guard let run = cycle(Self.s0LengthPt) else { return aborted("an S0 cycle could not complete") }
            results.append(S0Judge.cycle(claimGranted: run.claimGranted, controlsPassed: run.controlsPassed))
            if let m = run.measurements { measurements.append(m) }
        }
        environment.menus.quit()
        menusLaunched = false
        lastChange = environment.clock.now()
        let final = control("final control")
        let outcome = S0Judge.stage(results, finalControlPassed: final?.passed ?? false)
        var report = StepReport(status: outcome == .noGo ? .noGo : .completed)
        report.s0 = S0Report(outcome: outcome, c3: C3Check.evaluate(probe.c3), section8: Section8Check.evaluate(measurements))
        report.chevronObservations = observations
        return report
    }

    /// Q19: one cycle per length, an inconclusive cycle retried up to three times.
    private func bracket(_ lengths: [Double]) -> StepReport {
        var report = StepReport(status: .completed)
        for length in lengths {
            var readings = [C2Reading?]()
            while C2Retry.settleReading(readings) == nil {
                guard let run = cycle(length) else { return aborted("a cycle at \(length) pt could not complete", keeping: report) }
                if run.noGo {
                    report.status = .noGo
                    report.reason = "NO-GO at \(length) pt"
                    return report
                }
                readings.append(run.controlsPassed ? (run.inBand ? .hiddenNoFold : .stillDrawn) : nil)
            }
            report.points.append(ReportPoint(length: length, reading: "\(C2Retry.settleReading(readings) ?? .notShown)"))
        }
        return report
    }

    /// Q19: five cycles at the midpoint, accounted by the sequencer.
    private func confirm(_ length: Double) -> StepReport {
        var report = StepReport(status: .completed)
        for _ in 0..<S0Judge.cycles {
            guard let run = cycle(length) else { return aborted("a cycle at \(length) pt could not complete", keeping: report) }
            report.cycles.append(run.record)
            if run.noGo {
                report.status = .noGo
                report.reason = "NO-GO at \(length) pt"
                return report
            }
        }
        return report
    }

    /// Q17-Q18: one sweep up and down, with member rest controls around it.
    private func sweep(_ variant: SAdvVariant) -> StepReport {
        probe.feedsBControl = true
        guard environment.menus.stillInPlace(), let restControl = control("rest control") else { return aborted("the rest control could not be taken") }
        var sweep = SAdvSweep()
        var holds = [BarState]()
        while let length = sweep.nextLength() {
            setLength(length)
            guard let baseline = takeBaseline(),
                  let raw = observe(baseline, firstStart: max(environment.clock.now(), lastChange + cadence.settle))
            else { return aborted("an S-adv step at \(length) pt could not complete") }
            holds.append(baseline.holdState)
            let baselineJudged = judgeBaseline(baseline)
            let observation = judgeObservation(raw, baseline: baseline)
            sweep.record(stepResult(baseline, baselineJudged, observation, variant: variant, length: length, phase: sweep.phase))
        }
        rest()
        let restoreControl = control("restore control")
        let controlsHeld = restControl.passed && restoreControl?.passed == true
            && holds.allSatisfy { $0 == restControl.judged.state && $0 == restoreControl?.judged.state }
        var report = StepReport(status: .completed)
        switch sweep.status {
        case .noGo:
            report.status = .noGo
            report.sweep = .noGo
        case .done where controlsHeld:
            report.sweep = .pass
        default:
            report.sweep = .inconclusive
            report.reason = "sweep: \(sweep.status), controls held: \(controlsHeld)"
        }
        report.chevronObservations = observations
        return report
    }

    private func stepResult(_ baseline: BaselineRun, _ baselineJudged: [Judged], _ observation: ObservationRun, variant: SAdvVariant,
                            length: Double, phase: SAdvSweep.Phase) -> SAdvStepResult {
        let judged = baselineJudged + observation.judged
        let result: SAdvStepResult
        if observation.record.outcome == .noGo {
            result = .noGo
        } else if baseline.holdState.appearance.rawValue != variant.appearance.rawValue || judged.contains(where: { $0.verdict.inconclusive }) {
            result = .inconclusive
        } else {
            result = judged.contains { $0.verdict.seesMember } ? .membersSeen : .membersGone
        }
        environment.evidence.record("sAdv.step", ["length": length, "phase": "\(phase)", "result": "\(result)"])
        return result
    }

    /// Q17: members added at rest until `«` (a) shows, then episodes until `BControl` decides or the time box ends.
    private func chevronRest(spare: [RosterEntry]) -> StepReport {
        probe.feedsBControl = true
        let started = environment.clock.now()
        var last: RosterEntry?
        var shows = false
        for entry in spare where !shows {
            guard launchGlyph(entry), let read = control("chevron probe") else { return aborted("a member could not be added") }
            last = entry
            shows = ChevronRule.fromAX(reads: [read.judged.taken.timed.sample.agentFrames], barHeightPt: environment.geometry.heightPt)
        }
        var noGo = false
        while shows, let entry = last, environment.clock.now() - started < Self.chevronTimeBoxSeconds {
            guard let baseline = takeBaseline(),
                  let raw = observe(baseline, firstStart: max(environment.clock.now(), lastChange + cadence.settle))
            else { return aborted("a `«` episode could not complete") }
            _ = judgeBaseline(baseline)
            if judgeObservation(raw, baseline: baseline).record.outcome == .noGo {
                noGo = true
                break
            }
            switch BControl.evaluate(probe.episodes.all) {
            case .insufficientCaptures, .insufficientEpisodes: break
            case .valid, .mismatch: return chevronReport(noGo: false, shown: true)
            }
            quitGlyph(entry.id)
            guard control("chevron gone") != nil, launchGlyph(entry), control("chevron back") != nil else {
                return aborted("a `«` episode could not be repeated")
            }
        }
        return chevronReport(noGo: noGo, shown: shows)
    }

    private func chevronReport(noGo: Bool, shown: Bool) -> StepReport {
        var report = StepReport(status: noGo ? .noGo : .completed)
        report.sweep = noGo ? .noGo : .pass
        report.reason = shown ? nil : "no « (a) with \(probe.members.count) members"
        report.chevronObservations = observations
        return report
    }
}
