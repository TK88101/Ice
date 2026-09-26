// I5 setup: section 2's bundle check, the pre-launch preflight/baseline,
// `caffeinate -d` for the run's duration, the fixed launch order
// (Protected, then the spacer, then Target) with a fresh discovery
// confirming each one before the next helper starts, and the
// discovery-confirmed reap P0-6 requires before any relaunch or at
// teardown.
//
// Rework #5, step A: every live/AppKit call the original
// `Sources/vizprobe/StageC1Setup.swift` made directly now goes through
// `environment` (`C1StageEnvironment`) instead.
import C1Core
import C1Live
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

/// Restated from `Sources/vizprobe/PreflightCheck.swift` (internal to a
/// different, executable target) rather than imported.
enum C1WarmUp {
    static let captures = 24
    static let interval = 0.25
}

extension StageC1 {
    /// Existing bundle ids only (Target's and Protected's -- the spacer
    /// carries Protected's, P0-1), executables inside their bundles, and
    /// no helper under either already running.
    func step0Bundles() -> StepResult {
        for (url, expected) in [(apps.target, C1HelperRole.target), (apps.protected, C1HelperRole.protected), (apps.spacer, C1HelperRole.protected)] {
            guard environment.helperLauncher.validateBundle(at: url, expectedBundleID: expected) else {
                return .abort("\(url.lastPathComponent) is not a valid \(expected) bundle with an executable vzhelper inside it")
            }
        }
        environment.pump.run(0.2)
        let running = environment.helperLauncher.runningBundleIDs(among: C1HelperRole.all)
        guard running.isEmpty else { return .abort("\(running.count) helper(s) under a C1 bundle id already running") }
        return .ok
    }

    /// Section 5 step 1's "dry minute" setup half: geometry, the warm-up,
    /// evidence, and `caffeinate -d` for the run's duration only.
    func step1Setup() -> StepResult {
        guard let geometry = environment.geometryProvider() else {
            return .abort("no bar geometry (NSScreen.main unavailable)")
        }
        self.geometry = geometry

        do {
            evidence = try environment.evidenceFactory.makeEvidence(binaryURLs: c1BinaryURLs(), arguments: CommandLine.arguments, geometry: geometry, parameters: parameters, suffix: dry ? "vzc1dry" : "vzc1")
        } catch {
            return .abort("could not create the evidence directory: \(error)")
        }

        // caffeinate -d, ended by teardown or emergencyStop -- never left
        // running past this process's own life either, since it is a
        // child process this process owns.
        if let failure = environment.caffeinate.start() {
            evidence?.record("caffeinate.failed", ["error": failure])
        } else {
            caffeinateStarted = true
        }

        warmUpOnce()
        return .ok
    }

    /// Section 2: "warmed up once at the start (24 captures, 0.25 s
    /// apart)." Before any helper exists -- pre-channel, so the raw
    /// capturer is the right one here (P0-2 only requires
    /// `latchingCapturer` for post-channel captures). The counts match
    /// `Sources/vizprobe/PreflightCheck.swift`'s own
    /// `warmUpCaptures`/`warmUpInterval` -- restated here rather than
    /// imported, like `SpacerIdentifier`: that file is internal to the
    /// `vizprobe` executable target, which this library cannot depend on.
    func warmUpOnce() {
        for _ in 0..<C1WarmUp.captures {
            _ = capturer.capture()
            environment.pump.run(C1WarmUp.interval)
        }
    }

    /// Section 2's launch order: Protected, the spacer, Target -- each
    /// waits for `up` and a fresh discovery listing its item (by pid and
    /// AX identifier, P0-1 -- never by bundle id) before the next helper
    /// starts. `channel` (and, from it, `latchingCapturer`, P0-2) is built
    /// *before* any launch and every helper is registered with it the
    /// instant its process starts (item 2), so a failure partway through
    /// -- Protected launches but the spacer does not, say -- still leaves
    /// `runCleanup()` a channel that knows about Protected and can quit
    /// and reap it. `latchingCapturer`'s `assess` closure reads
    /// `ownerBaseline` lazily and is a no-op until `step3Baseline` sets
    /// it -- there is nothing to compare against before then, so silence
    /// is the faithful answer, not a gap.
    func step2Launch() -> StepResult {
        let channel = HelperControlChannel()
        self.channel = channel
        expansionDriver = C1ExpansionDriver(channel: channel, dry: dry)
        latchingCapturer = LatchingCapturer(
            base: capturer,
            channel: channel,
            onTrip: { [weak self] reason in self?.onLatchTrip(reason) }
        ) { [weak self] image in
            self?.assessLatch(image: image) ?? .init(captureFailed: true)
        }

        guard let protected = launchAndDiscover(label: "protected", app: apps.protected, bundleID: C1HelperRole.protected, role: "reference", identifier: "vz-reference", channel: channel) else {
            return .abort("could not launch or discover Protected")
        }
        protectedHelper = protected.helper
        protectedKey = protected.key

        guard let spacer = launchAndDiscover(label: "spacer", app: apps.spacer, bundleID: C1HelperRole.protected, role: "spacer", identifier: SpacerIdentifier.value, channel: channel, isSpacer: true) else {
            return .abort("could not launch or discover the spacer")
        }
        spacerHelper = spacer.helper
        spacerKey = spacer.key

        guard let target = launchAndDiscover(label: "target", app: apps.target, bundleID: C1HelperRole.target, role: "target", identifier: "vz-target", channel: channel) else {
            return .abort("could not launch or discover Target")
        }
        targetHelper = target.helper
        targetKey = target.key

        evidence?.record("step2.launched", ["protected": describeKey(protected.key), "spacer": describeKey(spacer.key), "target": describeKey(target.key)])
        return .ok
    }

    /// Deletes the bundle id's domain, launches one helper, registers it
    /// with `channel` the instant its process exists (item 2), then waits
    /// for its `up` line and discovers its declared item -- by pid and AX
    /// identifier (P0-1). `nil` on any failure -- the caller aborts the
    /// whole launch sequence rather than continue with a partial roster,
    /// but the helper (if it got that far) stays registered for cleanup.
    func launchAndDiscover(label: String, app: URL, bundleID: String, role: String, identifier: String, channel: HelperControlChannel, isSpacer: Bool = false) -> (helper: any C1HelperControlling, key: ItemKey)? {
        // Neither vzhelper role here ever sets `--autosave`, so this never
        // has data to lose even when Protected and the spacer share a
        // bundle id and this runs while Protected is already up (P0-1) --
        // defense in depth against some stray process's leftovers, not a
        // uniqueness check any more.
        environment.helperDefaults.forget(bundleID)
        guard environment.helperDefaults.keys(bundleID) == [] else {
            evidence?.record("helper.launchRefused", ["label": label, "reason": "the \(bundleID) domain is not verifiably empty"])
            return nil
        }
        guard let helper = environment.helperLauncher.launch(appURL: app, bundleID: bundleID, role: role, arguments: ["--role", role, "--lifetime", "900"], controllerPID: getpid()) else {
            evidence?.record("helper.launchFailed", ["label": label])
            return nil
        }
        channel.register(helper, isSpacer: isSpacer)
        guard helper.awaitReply("up", timeout: 5) != nil else {
            helper.quit()
            evidence?.record("helper.noUp", ["label": label])
            return nil
        }
        guard let item = discoverDeclared(pid: helper.pid, identifier: identifier) else {
            helper.quit()
            evidence?.record("helper.notDiscovered", ["label": label])
            return nil
        }
        return (helper, item.key)
    }

    /// The one `.declared` item of `pid` with `identifier`, from a fresh
    /// discovery pass that read `pid` conclusively, within 5 s.
    func discoverDeclared(pid: pid_t, identifier: String) -> DiscoveredItem? {
        let deadline = environment.pump.now() + 5
        repeat {
            environment.pump.run(0.1)
            if let result = environment.pump.blocking({ await self.discoverer.discover(previous: nil) }) {
                let status = result.status(of: pid)
                if status.enumerated, !status.failed, !status.quarantined, !status.permissionDenied,
                   let item = result.set.items.first(where: { $0.key.pid == pid && $0.key.identifier == identifier && $0.basis == .declared }) {
                    return item
                }
            }
            environment.pump.run(0.2)
        } while environment.pump.now() < deadline
        return nil
    }

    /// P0-6: a discovery-confirmed reap, retried within `seconds`. Rests
    /// the spacer, quits every helper, then re-discovers until a pass
    /// lists none of their pids (`C1ReapCheck`) or the deadline passes. A
    /// failed discovery pass is inconclusive, never confirmed.
    @discardableResult
    func confirmReap(within seconds: Double = 5) -> Bool {
        expansionDriver?.collapse()
        channel?.quitAll()
        environment.pump.run(0.5)
        let helperPIDs: Set<pid_t> = Set([targetHelper, spacerHelper, protectedHelper].compactMap { $0?.pid })
        guard !helperPIDs.isEmpty else { return true }
        let deadline = environment.pump.now() + seconds
        repeat {
            // Round 4 item 3: through `timedDiscoverer`, not the raw
            // `discoverer` -- each attempt in this retry loop is bounded,
            // so a single hung pass cannot swallow the whole `seconds`
            // budget (or, called from `emergencyStop()`, block the
            // watchdog's own synchronous cleanup indefinitely).
            let listed: Set<pid_t>? = environment.pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }).map { Set($0.set.items.map(\.key.pid)) }
            if C1ReapCheck.confirmed(listedPIDs: listed, helperPIDs: helperPIDs) {
                evidence?.record("reap.confirmed", [:])
                return true
            }
            environment.pump.run(0.2)
        } while environment.pump.now() < deadline
        evidence?.record("reap.notConfirmed", [:])
        return false
    }

    func describeKey(_ key: ItemKey) -> [String: Any] {
        ["encoded": key.encoded, "pid": key.pid, "identifier": key.identifier]
    }

    private func c1BinaryURLs() -> [String: URL] {
        [
            "vizprobe": URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath(),
            "vzhelper.target": apps.target.appendingPathComponent("Contents/MacOS/vzhelper"),
            "vzhelper.protected": apps.protected.appendingPathComponent("Contents/MacOS/vzhelper"),
            "vzhelper.spacer": apps.spacer.appendingPathComponent("Contents/MacOS/vzhelper"),
        ]
    }
}
