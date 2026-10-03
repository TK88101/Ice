// T0: the two spikes, one process -- spike A's profiles in order, then spike
// B on the k = 1 band's midpoint. Launch, placement and teardown follow route
// C's step (`IceBarStep`); the readings are `SpikeCore`'s.
import C2Core
import Darwin
import IceBarOracle
import IceBarRunCore
import IceBarStage
import IceCore
import MenuBarCapture
import SpikeCore

public final class SpikeStage {
    static let launchTimeoutSeconds = 5.0
    static let discoverySeconds = 5.0
    static let restControlAttempts = 3
    /// After `closemenu`, how long the press call is given to return.
    static let pressResultWait = 2.0
    static let pollSeconds = 0.05

    let environment: IceBarEnvironment
    let templates: StageTemplates
    let plan: SpikeStagePlan
    let press: any SpikePressing
    let progress: (String) -> Void
    var roster = [RosterEntry]()
    /// Glyph helpers and the spacer, for the AX read of every bracket.
    var pids = [String: pid_t]()
    var launched = [(id: String, helper: IceBarHelper)]()
    var spacer: IceBarHelper?
    var menusLaunched = false
    var lastChange = 0.0
    var sequence = 0

    public init(environment: IceBarEnvironment, templates: StageTemplates, plan: SpikeStagePlan, press: any SpikePressing,
                progress: @escaping (String) -> Void = { _ in }) {
        self.environment = environment
        self.templates = templates
        self.plan = plan
        self.press = press
        self.progress = progress
    }

    var members: [String] { roster.filter { $0.role == .member }.map(\.id) }
    var visible: [String] { roster.filter { $0.role == .visible }.map(\.id) }
    var barHeight: Double { environment.geometry.heightPt }
    /// Route C's settle after a spacer write or a helper change (`SpikeStagePlan.cadence`).
    var settle: Double { SpikeStagePlan.cadence.settle }
    var clock: any IceBarClock { environment.clock }
    var evidence: any IceBarEvidence { environment.evidence }

    public func run() -> SpikeRunResult {
        var results = [ProfileResult]()
        for profile in plan.profiles {
            progress("spike A \(profile.name) 開始")
            let result = measure(profile)
            results.append(result)
            evidence.record("profile", ["profile": profile.name, "band": result.band?.text ?? "none", "problem": result.problem ?? "",
                                        "records": result.records.map { ["\($0.length)", "\($0.outcome)"] }])
            progress("spike A \(profile.name) 結束：" + (result.band.map { "區間 \($0.text)" } ?? result.problem.map { "沒跑成（\($0)）" } ?? "沒有區間"))
        }
        let a = SpikeAResult(profiles: results)
        evidence.record("spike.a", ["hideLine": a.hideLine, "noBandAtOne": a.noBandAtOne])
        var b: SpikeBResult?
        var bProblem: String?
        if plan.runB, let target = a.pressTarget {
            progress("spike B \(target.profile.name) @ \(Band.format(target.length)) pt 開始")
            (b, bProblem) = pressStage(target)
            evidence.record("spike.b", ["clickLine": SpikeVerdict.clickLine(a: a, b: b, bProblem: bProblem, runB: plan.runB), "problem": bProblem ?? ""])
            progress("spike B 結束：" + (b.map { "\(SpikeBRules.path($0).rawValue)" } ?? "沒跑完（\(bProblem ?? "")）"))
        }
        return SpikeRunResult(a: a, b: b, bProblem: bProblem, runB: plan.runB)
    }

    // MARK: - Launch and teardown (as `IceBarStep`, Q11 and Q21)

    /// `nil` on success, else the problem; `memberMenu` gives the members vzhelper's `--menu`.
    func launch(_ profile: SpikeProfile, memberMenu: Bool) -> String? {
        let entries: [RosterEntry]
        do {
            entries = try Roster.entries(glyphOrder: plan.glyphOrder, members: profile.members, colouredMembers: false)
        } catch {
            return "roster: \(error)"
        }
        if let missing = entries.first(where: { templates.helpers[$0.id] == nil }) { return "no oracle template for \(missing.id)" }
        if let problem = rosterGuard() { return problem }
        if let bundle = dirtyDomains().first { return "helper domain \(bundle) not empty before launch" }
        if let problem = environment.menus.launchAndCalibrate(profile.menu) { return "menus: \(problem)" }
        menusLaunched = true
        for entry in entries where entry.role == .visible {
            guard launchGlyph(entry, menu: false) else { return "\(entry.id) did not come up" }
        }
        guard let spacerHelper = environment.launcher.launch(app: Roster.spacerApp, bundleID: Roster.otherBundleID,
                                                             arguments: Roster.spacerArguments(lifetimeSeconds: plan.helperLifetimeSeconds)),
              spacerHelper.awaitUp(timeout: Self.launchTimeoutSeconds)
        else { return "the spacer did not come up" }
        spacer = spacerHelper
        launched.append(("spacer", spacerHelper))
        pids["spacer"] = spacerHelper.pid
        lastChange = clock.now()
        guard discovered("spacer") else { return "the spacer was not discovered" }
        for entry in entries where entry.role == .member {
            guard launchGlyph(entry, menu: memberMenu) else { return "\(entry.id) did not come up" }
        }
        if let problem = rosterGuard() { return problem }
        guard let read = environment.axReader.read(items: pids) else { return "placement read failed" }
        let placement = PlacementCheck.evaluate(frames: read.itemFrames, members: members, spacer: "spacer", visible: visible, barHeightPt: barHeight)
        evidence.record("placement", ["outcome": "\(placement)", "roster": roster.map { [$0.id, $0.role.rawValue] }, "menu": memberMenu])
        guard placement == .placed else { return "placement gate: \(placement)" }
        guard warmUp() else { return "a warm-up capture failed" }
        lastChange = clock.now()
        return nil
    }

    private func launchGlyph(_ entry: RosterEntry, menu: Bool) -> Bool {
        var arguments = Roster.arguments(entry, lifetimeSeconds: plan.helperLifetimeSeconds)
        if menu { arguments = SpikeHelperFlags.withMenu(arguments) }
        guard let helper = environment.launcher.launch(app: entry.app, bundleID: entry.bundleID, arguments: arguments),
              helper.awaitUp(timeout: Self.launchTimeoutSeconds)
        else { return false }
        launched.append((entry.id, helper))
        roster.removeAll { $0.id == entry.id }
        roster.append(entry)
        pids[entry.id] = helper.pid
        lastChange = clock.now()
        return discovered(entry.id)
    }

    /// The helper's own AX frame appears within a few seconds.
    private func discovered(_ id: String) -> Bool {
        let deadline = clock.now() + Self.discoverySeconds
        while clock.now() <= deadline {
            if let pid = pids[id], environment.axReader.read(items: [id: pid])?.itemFrames[id] != nil { return true }
            clock.sleep(until: clock.now() + 0.25)
        }
        return false
    }

    /// Only system items and this run's own helpers.
    private func rosterGuard() -> String? {
        let ours = Set(launched.map(\.helper.pid))
        if let foreign = environment.barOwners().first(where: { !C2Guards.rosterAllowed(bundleIDs: [$0.bundleID]) && !ours.contains($0.pid) }) {
            return "an unexpected item on the bar: \(foreign.bundleID)"
        }
        return nil
    }

    private func warmUp() -> Bool {
        var next = clock.now()
        for _ in 0..<SpikeStagePlan.cadence.warmUpCaptures {
            clock.sleep(until: next)
            guard environment.capturer.capture() != nil else { return false }
            next = clock.now() + SpikeStagePlan.cadence.warmUpSpacing
        }
        return true
    }

    /// Rest, quit everything, empty the domains, check the bar holds no helper; the stage is empty afterwards.
    @discardableResult
    func teardown() -> String? {
        spacer?.send("rest")
        for (_, helper) in launched.reversed() { helper.quit(timeout: 2) }
        if menusLaunched { environment.menus.quit() }
        var problems = [String]()
        if let alive = launched.first(where: { $0.helper.isRunning }) { problems.append("\(alive.id) still running") }
        problems += dirtyDomains().map { "helper domain \($0) not empty" }
        let ours = Set(launched.map(\.helper.pid))
        if environment.barOwners().contains(where: { ours.contains($0.pid) || Roster.bundleIDs.contains($0.bundleID) }) {
            problems.append("a helper is still on the bar")
        }
        launched = []
        roster = []
        pids = [:]
        spacer = nil
        menusLaunched = false
        evidence.record("teardown", ["problems": problems])
        return problems.isEmpty ? nil : problems.joined(separator: "; ")
    }

    private func dirtyDomains() -> [String] {
        Roster.bundleIDs.filter { !environment.forgetDomain($0) || environment.domainKeys($0) != [] }
    }

    func setLength(_ length: Double) {
        spacer?.send("length \(length)")
        lastChange = clock.now()
    }

    func rest() {
        spacer?.send("rest")
        lastChange = clock.now()
    }
}
