// The shared frame of the 2026-09-23 plan's two live stages (section 6,
// T8a/T8b): `vizprobe discover` (steps 1, 2, 4, 7-10, 11) and
// `vizprobe verify` (steps 1-3, 5, 6, 11). Split in two so the steps that
// decide D9 and D10 (9, 10) run even when a verification step stops its run.
//
// Rules carried from section 6: existing bundle ids only (checked before
// anything runs); an autosave name only in step 10; the helper's domain
// deleted -- and verified empty by a fresh `defaults export` -- before every
// launch and after; room measured live before every launch; a `«` or a
// privacy pill left of the items, checked before and after every launch and
// at every safety check, an unexpected verdict or a safety event quits every
// helper and stops the run -- except outcomes the plan pre-registers as
// recorded or skipped. No spacer is expanded and no mouse event is posted
// anywhere in this file or the stages.
import AppKit
import CryptoKit
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

enum StageKind: String {
    case discover
    case verify
}

/// Leaves vizprobe itself out of discovery: it runs no status item, and a
/// process that never runs its app loop can only time out when read.
struct HarnessProcesses: RunningAppsProviding {
    let base: LiveRunningApps
    func processes() -> [ProcessInfoRecord] { base.processes().filter { !$0.isSelf } }
    func agentPID() -> Int32? { base.agentPID() }
}

final class StageRun {
    static let ownIdentifiers = OwnIdentifiers(
        visible: "Ice.ControlItem.Visible",
        hidden: "Ice.ControlItem.Hidden",
        alwaysHidden: "Ice.ControlItem.AlwaysHidden"
    )
    /// Section 6's room rule: 30 pt per item about to be launched, the
    /// chevron's 17.5 pt, and 41 pt more when the capture indicator is not
    /// already up.
    static let roomPerItemPt = 30.0
    static let chevronPt = 17.5
    static let indicatorPt = 41.0
    static let captureIndicatorWidthPt = 14.0...30.0
    /// Long enough for a whole stage; the controller-exit watch and the
    /// watchdog remain the primary deadmen.
    static let helperLifetime = "900"

    let kind: StageKind
    let apps: HelperApps
    let capturer = CGWindowListStripCapturer()
    let parameters = DetectorParameters.preRegistered
    let decision: MenuBarItemVisibility
    let discoverer = MenuBarDiscoverer(
        apps: HarnessProcesses(base: LiveRunningApps()),
        reader: LiveExtrasReader(),
        display: LiveDisplay(),
        isTrusted: { AXIsProcessTrusted() },
        ownIdentifiers: StageRun.ownIdentifiers,
        now: { ProcessInfo.processInfo.systemUptime }
    )

    var geometry: BarGeometry!
    var evidence: LiveEvidence!
    var monitor: SafetyMonitor!
    var preflightBaseline: BaselineResult!
    var agentDefaultsBefore: Data?

    /// Every helper launched this run, so an abort can quit them all.
    /// Guarded by `lock`: the watchdog and the signal handlers stop the run
    /// from another thread.
    private var helpers = [HelperControl]()
    private var stopping = false
    /// Whether this run launched anything: until it has, an abort must not
    /// empty the helper domains (step 0 stops because another helper under
    /// the same ids is running, and its domain is not ours to delete).
    private var launchedAny = false
    private let lock = NSLock()
    var reference: HelperControl?
    var referenceKey: ItemKey?
    var target: HelperControl?
    var targetKey: ItemKey?
    /// The results that decide something, printed at the end.
    var summary = [String: Any]()

    init(kind: StageKind, apps: HelperApps) {
        self.kind = kind
        self.apps = apps
        self.decision = MenuBarItemVisibility(maxMismatch: parameters.maxMismatch)
    }

    // MARK: - Running

    func run(_ steps: [(name: String, body: () -> StepResult)]) -> Int32 {
        for step in steps {
            evidence?.record("step.begin", ["step": step.name])
            if case .abort(let reason) = step.body() {
                FileHandle.standardError.write(Data("vizprobe \(kind.rawValue): ABORTED at \(step.name) -- \(reason)\n".utf8))
                evidence?.record("run.aborted", ["step": step.name, "reason": reason])
                quitAll()
                // The teardown checks still run, recorded only: they are what
                // shows the user's bar is back as it was.
                if evidence != nil { _ = step11Teardown() }
                finish()
                return 1
            }
        }
        let teardown = step11Teardown()
        finish()
        if case .abort(let reason) = teardown {
            FileHandle.standardError.write(Data("vizprobe \(kind.rawValue): teardown -- \(reason)\n".utf8))
            return 1
        }
        print("vizprobe \(kind.rawValue): run completed -- evidence at \(evidence?.directory.path ?? "?")")
        return 0
    }

    private func finish() {
        evidence?.record("summary", summary)
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print("summary:\n\(text)")
        }
        evidence?.close()
    }

    func quitAll() {
        let (snapshot, launched): ([HelperControl], Bool) = lock.withLock {
            defer { helpers.removeAll() }
            return (helpers, launchedAny)
        }
        for helper in snapshot { helper.quit() }
        reference = nil
        target = nil
        guard launched else { return }
        for bundleID in HelperRole.allBundleIDs { HelperDefaults.forget(bundleID) }
    }

    /// For the watchdog and the signal handlers, from any thread: no launch
    /// may start after this; the domains are emptied first (they do not
    /// depend on the helper list), then every helper quits, then the domains
    /// are emptied again.
    func emergencyStop() {
        let (snapshot, launched): ([HelperControl], Bool) = lock.withLock {
            stopping = true
            defer { helpers.removeAll() }
            return (helpers, launchedAny)
        }
        guard launched else { return }
        for bundleID in HelperRole.allBundleIDs { HelperDefaults.forget(bundleID) }
        for helper in snapshot { helper.quit(timeout: 1) }
        for bundleID in HelperRole.allBundleIDs { HelperDefaults.forget(bundleID) }
    }

    /// Before anything runs: both bundles carry exactly the two allowed ids,
    /// their executables are inside them, and no helper under either id is
    /// already running (its domain would be deleted underneath it).
    func step0Bundles() -> StepResult {
        for (url, expected) in [(apps.target, HelperRole.target), (apps.reference, HelperRole.reference)] {
            let actual = Bundle(url: url)?.bundleIdentifier
            guard actual == expected else {
                return .abort("\(url.lastPathComponent) has bundle id \(actual ?? "none"), expected \(expected)")
            }
            let executable = url.appendingPathComponent("Contents/MacOS/vzhelper").resolvingSymlinksInPath().path
            guard executable.hasPrefix(url.resolvingSymlinksInPath().path + "/"), FileManager.default.isExecutableFile(atPath: executable) else {
                return .abort("\(url.lastPathComponent)'s executable is missing or outside the bundle")
            }
        }
        Pump.run(0.2)
        let running = NSWorkspace.shared.runningApplications.filter { HelperRole.allBundleIDs.contains($0.bundleIdentifier ?? "") }
        guard running.isEmpty else { return .abort("\(running.count) helper(s) under com.icespike4.* already running") }
        return .ok
    }

    // MARK: - Step 1

    /// The 2026-09-19 plan's 6.1 step 1 (shared `PreflightCheck`), the free
    /// room, and a read-only snapshot of MenuBarAgent's defaults.
    func step1Preflight() -> StepResult {
        let axReader = NSScreen.main.map { LiveMenuBarAXReader(screen: $0) } ?? LiveMenuBarAXReader()
        let outcome = PreflightCheck.run(capturer: capturer, axReader: axReader, parameters: parameters)
        guard let geometry = outcome.geometry else { return .abort("no bar geometry (NSScreen.main unavailable)") }
        self.geometry = geometry
        guard case .ready = outcome.preflight else { return .abort("preflight: \(outcome.preflight)") }
        guard let preflightBaseline = outcome.baseline else {
            return .abort("pre-flight baseline failed (a capture or an Accessibility read did not complete)")
        }
        self.preflightBaseline = preflightBaseline
        guard !outcome.chevronOrPillSignal else { return .abort("a chevron or a privacy pill is present before any helper is launched") }
        guard outcome.freeRoomOK else { return .abort("free room right of the notch is under \(Int(PreflightCheck.minFreeRoomPt)) pt") }

        do {
            evidence = try LiveEvidence(binaryURLs: binaryURLs(), arguments: CommandLine.arguments, geometry: geometry, parameters: parameters, suffix: "vz\(kind.rawValue)")
        } catch {
            return .abort("could not create the evidence directory: \(error)")
        }
        evidence.record("preflight", [
            "freeRoomPt": outcome.room?.freeRoomPt ?? -1,
            "acceptedThirdPartyItems": preflightBaseline.acceptedIDs.count,
            "rejectedThirdPartyItems": preflightBaseline.rejections.count,
            "foldAtBaseline": "\(preflightBaseline.foldAtBaseline)",
            "environmentIndicators": outcome.environmentIndicators.map { "\($0.minX)/\($0.width)" },
            "trusted": AXIsProcessTrusted(),
        ])
        guard !preflightBaseline.acceptedIDs.isEmpty else {
            return .abort("the pre-flight baseline accepted no user item, so the safety monitor would watch nothing")
        }
        do {
            monitor = try SafetyMonitor(baseline: preflightBaseline, parameters: parameters)
        } catch {
            return .abort("the pre-flight baseline had no calibrated ink; the safety monitor cannot start")
        }
        evidence.record("safetyMonitor.armed", ["watching": monitor.watchedCount])

        agentDefaultsBefore = MenuBarAgentDefaults.export()
        if let agentDefaultsBefore {
            try? agentDefaultsBefore.write(to: evidence.directory.appendingPathComponent("menubaragent-defaults-before.plist"))
        }
        evidence.record("menuBarAgentDefaults.before", ["bytes": agentDefaultsBefore?.count ?? -1])
        return .ok
    }

    // MARK: - Step 11

    /// Quits every helper, empties both helper domains (the plist files are
    /// left in place), re-baselines the bar and compares every user item and
    /// MenuBarAgent's defaults with step 1.
    func step11Teardown() -> StepResult {
        quitAll()
        Pump.run(1.0)

        let domains = HelperRole.allBundleIDs.map { ($0, HelperDefaults.keys($0)) }
        let domainsEmpty = domains.allSatisfy { $0.1?.isEmpty == true }
        evidence.record("teardown.helperDomains", ["empty": domainsEmpty, "keys": Dictionary(uniqueKeysWithValues: domains.map { ($0.0, $0.1 ?? ["<unreadable>"]) })])
        summary["helperDomainsEmpty"] = domainsEmpty

        let agentAfter = MenuBarAgentDefaults.export()
        if let agentAfter {
            try? agentAfter.write(to: evidence.directory.appendingPathComponent("menubaragent-defaults-after.plist"))
        }
        let agentEqual = agentAfter == agentDefaultsBefore
        evidence.record("menuBarAgentDefaults.after", [
            "bytes": agentAfter?.count ?? -1,
            "equal": agentEqual,
            "changedKeys": MenuBarAgentDefaults.changedKeys(before: agentDefaultsBefore, after: agentAfter),
        ])
        summary["menuBarAgentDefaultsUnchanged"] = agentEqual

        // Retried like the preflight baseline: about half of single attempts
        // read the fold `unreadable` while the capture indicator flickers
        // (2026-09-19), which says nothing about a chevron.
        var post = ThirdPartyBaseline.take(capturer: capturer, geometry: geometry, parameters: parameters)
        for _ in 1..<PreflightCheck.baselineAttempts where post?.foldAtBaseline != .absent {
            Pump.run(PreflightCheck.baselineRetryInterval)
            post = ThirdPartyBaseline.take(capturer: capturer, geometry: geometry, parameters: parameters)
        }
        guard let postBaseline = post else {
            return .abort("teardown: could not re-baseline the bar")
        }
        evidence.record("teardown.baseline", ["accepted": postBaseline.acceptedIDs.count, "foldAtBaseline": "\(postBaseline.foldAtBaseline)"])
        switch postBaseline.foldAtBaseline {
        case .absent: break
        case .present: return .abort("teardown: the chevron is up after quitting the helpers")
        case .unreadable: return .abort("teardown: the fold stayed unreadable over \(PreflightCheck.baselineAttempts) attempts, so the user's items were not verified")
        }
        var displaced = [String]()
        for id in preflightBaseline.acceptedIDs {
            guard let before = preflightBaseline.templates[id], let after = postBaseline.templates[id],
                  abs(before.originXPt - after.originXPt) <= parameters.referenceTolerancePt
            else {
                displaced.append(id)
                continue
            }
        }
        evidence.record("teardown.displaced", ["count": displaced.count])
        summary["userItemsDisplaced"] = displaced.count
        guard displaced.isEmpty else {
            return .abort("teardown: \(displaced.count) user item(s) not back at their pre-flight x")
        }
        return .ok
    }

    // MARK: - Room, launch, discovery, safety

    /// What the bar says about room and the fold right now.
    struct BarReading {
        let freePt: Double
        let neededPt: Double
        let indicatorUp: Bool
        /// A chevron- or pill-width MenuBarAgent frame left of the items.
        let chevronOrPill: Bool
        /// The MenuBarAgent frames, for the agent-set comparison.
        let agentFrames: [AgentFrame]
    }

    /// Section 6's room rule, read live: 30 pt per item about to be
    /// launched and the chevron's 17.5 pt; the capture indicator's 41 pt too
    /// when it is not up -- and when it is up, the free room is measured from
    /// the indicator itself, whose width is not free.
    static func readBar(forItems count: Int, geometry: BarGeometry, parameters: DetectorParameters) -> BarReading {
        Pump.run(0.2)
        let onBar = BarScan.items().filter { $0.minY >= 0 && $0.minY < geometry.heightPt }
        let isAgent = { (item: BarItem) in item.bundleID == BarScan.menuBarAgentBundleID }
        let leftmostItem = onBar.filter { !isAgent($0) }.map(\.minX).min() ?? geometry.widthPt
        let agentLeft = onBar.filter { isAgent($0) && $0.minX < leftmostItem }
        let asFrame = { (item: BarItem) in AgentFrame(minX: item.minX, minY: item.minY, width: item.width) }
        let foldLike = { (item: BarItem) in
            FoldWitness.isChevron(asFrame(item), parameters: parameters) || FoldWitness.isPill(asFrame(item), parameters: parameters)
        }
        // The capture indicator measured ≈ 20 pt wide (plan section 0); any
        // other agent frame left of the items is an environment indicator and
        // does not stand in for the 41 pt reserve.
        let indicators = agentLeft.filter { !foldLike($0) && (captureIndicatorWidthPt).contains($0.width) }
        let leftmost = min(leftmostItem, indicators.map(\.minX).min() ?? .infinity)
        let free = leftmost - (geometry.notch?.hi ?? 0)
        let needed = roomPerItemPt * Double(count) + chevronPt + (indicators.isEmpty ? indicatorPt : 0)
        return BarReading(
            freePt: free,
            neededPt: needed,
            indicatorUp: !indicators.isEmpty,
            chevronOrPill: agentLeft.contains(where: foldLike),
            agentFrames: onBar.filter(isAgent).map(asFrame)
        )
    }

    enum Room {
        case ok
        case skip
        case abort(String)
    }

    /// Before a launch: a `«` or a pill stops the run; too little room skips
    /// the step (both recorded).
    func room(forItems count: Int, step: String) -> Room {
        let bar = Self.readBar(forItems: count, geometry: geometry, parameters: parameters)
        evidence.record("room", ["step": step, "freePt": bar.freePt, "neededPt": bar.neededPt, "indicatorUp": bar.indicatorUp, "chevronOrPill": bar.chevronOrPill])
        if bar.chevronOrPill { return .abort("\(step): a chevron or a privacy pill is up left of the items") }
        guard bar.freePt >= bar.neededPt else {
            evidence.record("step.skipped", ["step": step, "reason": "room: \(bar.freePt) pt free, \(bar.neededPt) pt needed"])
            return .skip
        }
        return .ok
    }

    /// A `«` or a pill left of the items stops the run. A changed agent set
    /// is recorded only: the capture indicator comes and goes.
    func barCheck(_ label: String) -> StepResult {
        let bar = Self.readBar(forItems: 0, geometry: geometry, parameters: parameters)
        let agentSetMatches = FoldWitness.agentSetMatches(current: bar.agentFrames, baseline: preflightBaseline.agentFrames, parameters: parameters)
        evidence.record("bar.check", ["label": label, "chevronOrPill": bar.chevronOrPill, "agentSetMatchesPreflight": agentSetMatches, "indicatorUp": bar.indicatorUp])
        return bar.chevronOrPill ? .abort("\(label): a chevron or a privacy pill is up left of the items") : .ok
    }

    /// Deletes the bundle id's domain, launches one helper, waits for its
    /// `up` line.
    /// The domain is deleted and verified empty first; `nil` if it is not,
    /// if the run is stopping, or if the helper never reports `up`.
    func launch(label: String, app: URL, bundleID: String, arguments: [String]) -> HelperControl? {
        HelperDefaults.forget(bundleID)
        guard HelperDefaults.keys(bundleID) == [] else {
            evidence.record("helper.launchRefused", ["label": label, "reason": "the \(bundleID) domain is not verifiably empty"])
            return nil
        }
        let helper: HelperControl? = lock.withLock {
            guard !stopping else { return nil }
            guard let helper = try? HelperControl(appURL: app, bundleID: bundleID, role: label, arguments: arguments + ["--lifetime", Self.helperLifetime], controllerPID: getpid()) else {
                return nil
            }
            helpers.append(helper)
            launchedAny = true
            return helper
        }
        guard let helper else {
            evidence.record("helper.launchFailed", ["label": label])
            return nil
        }
        let up = helper.awaitReply("up", timeout: 5)
        evidence.record("helper.launched", ["label": label, "pid": helper.pid, "arguments": arguments, "up": up ?? NSNull()])
        return up == nil ? nil : helper
    }

    func quit(_ helper: HelperControl) {
        let pid = helper.pid
        helper.quit()
        lock.withLock { helpers.removeAll { $0 === helper } }
        HelperDefaults.forget(helper.bundleID)
        evidence.record("helper.quit", ["label": helper.role, "exited": kill(pid, 0) != 0, "domainEmpty": HelperDefaults.keys(helper.bundleID) == []])
    }

    /// One fresh, read-only discovery pass.
    func discover() -> DiscoveryResult? {
        Pump.run(0.1)
        let discoverer = self.discoverer
        return Pump.blocking { await discoverer.discover(previous: nil) }
    }

    /// Discovers until `pid` owns exactly `count` listed items in a pass that
    /// read `pid` conclusively, or 5 s. A pass whose read of `pid` failed
    /// proves nothing about its items, least of all their absence.
    func discoverItems(of pid: pid_t, count: Int) -> (result: DiscoveryResult, items: [DiscoveredItem])? {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let result = discover(), readConclusively(pid, in: result) {
                let items = result.set.items.filter { $0.process.pid == pid }
                if items.count == count { return (result, items) }
            }
            Pump.run(0.2)
        } while Date() < deadline
        return nil
    }

    /// A quarantined pid was not read at all, whatever `.complete` says: that
    /// completeness speaks only for eligible processes (2026-09-25
    /// responsiveness-quarantine plan, 3.6).
    func readConclusively(_ pid: pid_t, in result: DiscoveryResult) -> Bool {
        if result.quarantined.contains(where: { $0.pid == pid }) { return false }
        switch result.set.completeness {
        case .complete: return true
        case .incomplete(let failed): return !failed.contains(pid)
        case .permissionDenied: return false
        }
    }

    /// A helper item as the evidence may show it: nothing about the user's
    /// own apps is ever recorded.
    func describe(_ item: DiscoveredItem) -> [String: Any] {
        [
            "key": item.key.encoded,
            "basis": "\(item.basis)",
            "position": "\(item.position)",
            "frame": item.frame.map { [$0.minX, $0.minY, $0.width, $0.height] } ?? NSNull(),
        ]
    }

    /// The bar check, then one capture kept and fed to the safety monitor
    /// (2026-09-19 plan 6.2).
    func safetyCheck(_ label: String) -> StepResult {
        if case .abort(let reason) = barCheck(label) { return .abort(reason) }
        guard let capture = capturer.capture() else { return .abort("capture failed during the \(label) safety check") }
        evidence.keep(capture, label: "safety-\(label)")
        let tripped = monitor.feed(capture)
        evidence.record("safety.check", ["label": label, "tripped": tripped])
        return tripped ? .abort("safety monitor: a user item was not uniquely at its baseline position in two consecutive checks") : .ok
    }

    /// The warm-up that summons the capture indicator before a baseline
    /// (2026-09-19, Deviations 12-13).
    func warmUp() {
        for _ in 0..<PreflightCheck.warmUpCaptures {
            _ = capturer.capture()
            Pump.run(PreflightCheck.warmUpInterval)
        }
    }

    /// D15 in the harness (plan Deviation 8): every listed, named item on the
    /// bar left of the leftmost of `helperKeys`, from other processes. On
    /// macOS 27 a new helper item does not reliably appear at the left end, so
    /// a baseline over the helpers alone leaves those items' ink unexplained
    /// and the fold unreadable; observing them explains it, as the app's own
    /// check does. Read-only: only their frames are read.
    func neighboursLeft(of helperKeys: [ItemKey], in set: DiscoveredItemSet) -> [String: pid_t] {
        let helperPIDs = Set(helperKeys.map(\.pid))
        let helperFrames = set.items.filter { helperKeys.contains($0.key) }.compactMap(\.frame).map { CheckFrames.trim($0) }
        guard let leftmost = helperFrames.map(\.minX).min() else { return [:] }
        var neighbours = [String: pid_t]()
        for item in set.items where item.position == .onBar && item.basis != .positional && !helperPIDs.contains(item.key.pid) {
            guard let frame = item.frame, CheckFrames.trim(frame).maxX <= leftmost else { continue }
            neighbours[item.key.encoded] = item.key.pid
        }
        return neighbours
    }

    /// A `DiscoveredFrameReader` for the current display.
    func feedReader(origin: DiscoveryOrigin) -> DiscoveredFrameReader {
        DiscoveredFrameReader(extras: LiveExtrasReader(), apps: LiveRunningApps(), origin: origin)
    }

    /// Warm-up, then a baseline retried (5 x 1 s) until its fold reads
    /// `.absent` -- the same rule `HidingVerification` applies (D16).
    func baseline(observer: VisibilityObserver, items: [String: pid_t]) -> BaselineResult? {
        warmUp()
        var last: BaselineResult?
        for attempt in 0..<5 {
            if let result = observer.baseline(items: items, geometry: geometry) {
                last = result
                if result.foldAtBaseline == .absent { break }
            }
            if attempt < 4 { Pump.run(1.0) }
        }
        return last
    }

    private func binaryURLs() -> [String: URL] {
        [
            "vizprobe": URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath(),
            "vzhelper.target": apps.target.appendingPathComponent("Contents/MacOS/vzhelper"),
            "vzhelper.reference": apps.reference.appendingPathComponent("Contents/MacOS/vzhelper"),
        ]
    }
}

/// MenuBarAgent's defaults, read only (`defaults export <domain> -`), for the
/// step 1 / step 11 comparison. Kept in the evidence directory, never in the
/// repository.
enum MenuBarAgentDefaults {
    static let domain = "com.apple.MenuBarAgent"

    static func export() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["export", domain, "-"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    /// Top-level keys whose values differ -- names only.
    static func changedKeys(before: Data?, after: Data?) -> [String] {
        func dictionary(_ data: Data?) -> [String: Any] {
            guard let data else { return [:] }
            return ((try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]) ?? [:]
        }
        let a = dictionary(before)
        let b = dictionary(after)
        return Set(a.keys).union(b.keys).filter { key in
            switch (a[key], b[key]) {
            case let (x?, y?): return !(x as AnyObject).isEqual(y)
            default: return true
            }
        }.sorted()
    }
}
