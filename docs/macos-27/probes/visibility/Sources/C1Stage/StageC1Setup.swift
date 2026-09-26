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
        // Amendment v8, "Placement by the helpers' own preferred
        // position": `step1bPlacementPlan` always runs before this step
        // and aborts the whole run if it refuses -- a missing plan here
        // would mean that guard was bypassed; fail closed rather than
        // launch unpositioned.
        guard let plan = placementPlan else { return .abort("no placement plan (step1b did not run)") }

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

        // F5 (Amendment v6, crosscheck #4-#6/#9/#10/#12): checked before
        // every launch -- no launch after a stop.
        guard !isTerminal else { return .abort("terminal before launching Protected") }
        guard let protected = launchAndDiscover(label: "protected", app: apps.protected, bundleID: C1HelperRole.protected, role: "reference", identifier: "vz-reference", channel: channel, isProtected: true, autosaveName: C1AutosaveName.protected, preferredPosition: plan.protectedPreferredPosition) else {
            return .abort("could not launch or discover Protected")
        }
        protectedHelper = protected.helper
        protectedKey = protected.key

        guard !isTerminal else { return .abort("terminal before launching the spacer") }
        guard let spacer = launchAndDiscover(label: "spacer", app: apps.spacer, bundleID: C1HelperRole.protected, role: "spacer", identifier: SpacerIdentifier.value, channel: channel, isSpacer: true, autosaveName: C1AutosaveName.spacer, preferredPosition: plan.spacerPreferredPosition, forgetDomainFirst: false) else {
            return .abort("could not launch or discover the spacer")
        }
        spacerHelper = spacer.helper
        spacerKey = spacer.key

        guard !isTerminal else { return .abort("terminal before launching Target") }
        guard let target = launchAndDiscover(label: "target", app: apps.target, bundleID: C1HelperRole.target, role: "target", identifier: "vz-target", channel: channel, autosaveName: C1AutosaveName.target, preferredPosition: plan.targetPreferredPosition) else {
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
    ///
    /// Amendment v8, "Placement by the helpers' own preferred position"
    /// (option A): `autosaveName` (unique per role -- `C1AutosaveName`;
    /// Protected and the spacer share `bundleID` but never a name) and
    /// `preferredPosition` (`PlacementPlan`'s own value for this role) are
    /// written into `bundleID`'s own domain -- never the owner's -- right
    /// after the domain is confirmed empty and before this helper's own
    /// process ever launches, then passed to it as `--autosave` so AppKit
    /// reads the key back the moment the item is created.
    ///
    /// `forgetDomainFirst` (default `true`): whether this call forgets and
    /// re-verifies `bundleID`'s domain empty before writing. Protected and
    /// the spacer share one domain -- since Protected's own launch (always
    /// first, `step2Launch`'s own order) already forgot and verified it
    /// empty this run, the spacer's own call passes `false`, so it only
    /// adds its own key alongside Protected's rather than wiping it back
    /// out again before teardown was ever meant to.
    func launchAndDiscover(label: String, app: URL, bundleID: String, role: String, identifier: String, channel: HelperControlChannel, isSpacer: Bool = false, isProtected: Bool = false, autosaveName: String, preferredPosition: Double, forgetDomainFirst: Bool = true) -> (helper: any C1HelperControlling, key: ItemKey)? {
        if forgetDomainFirst {
            // Defense in depth against some stray process's leftovers from
            // an earlier, unrelated run -- never against a sibling helper
            // this same run already legitimately wrote to (that is exactly
            // what `forgetDomainFirst: false` is for).
            environment.helperDefaults.forget(bundleID)
            guard environment.helperDefaults.keys(bundleID) == [] else {
                evidence?.record("helper.launchRefused", ["label": label, "reason": "the \(bundleID) domain is not verifiably empty"])
                return nil
            }
        }
        // F5: a signal (or any other terminal event) that lands exactly
        // here must stop this launch from ever starting.
        guard !isTerminal else {
            evidence?.record("helper.launchRefused", ["label": label, "reason": "terminal before launch"])
            return nil
        }

        let preferredPositionKey = PreferredPositionKey.stringKey(autosaveName: autosaveName)
        let wroteKey = environment.helperDefaults.write(bundleID, key: preferredPositionKey, value: preferredPosition)
        evidence?.record("placement.keyWritten", ["label": label, "bundleID": bundleID, "autosaveName": autosaveName, "value": preferredPosition, "wrote": wroteKey])

        // G8 (Amendment v7): derived from the watchdog (`StageC1.effectiveHelperLifetimeSeconds`
        // = watchdog + backstop + margin), never a bare literal -- a
        // helper must not self-exit while the watchdog's own staged
        // teardown could still legitimately be running
        // (crosscheck-rework6.json's own "Helper --lifetime 900 is fixed
        // at the watchdog length" finding).
        let lifetimeArgument = String(Int(StageC1.effectiveHelperLifetimeSeconds))
        guard let helper = environment.helperLauncher.launch(appURL: app, bundleID: bundleID, role: role, arguments: ["--role", role, "--autosave", autosaveName, "--lifetime", lifetimeArgument], controllerPID: getpid()) else {
            evidence?.record("helper.launchFailed", ["label": label])
            return nil
        }
        channel.register(helper, isSpacer: isSpacer, isProtected: isProtected)
        // F5: a terminal event can also land *during* `launch(...)` itself
        // (e.g. a signal fired synchronously from within it) -- caught
        // here, right after registering, so this helper is quit at once
        // rather than left running past the stop.
        guard !isTerminal else {
            helper.quit()
            evidence?.record("helper.launchedAfterTerminal", ["label": label])
            return nil
        }
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
    ///
    /// F6 (Amendment v6, crosscheck #8/#11): through `timedDiscoverer`,
    /// not the raw `discoverer` -- this runs once a helper exists (after
    /// `channel`/`latchingCapturer` are built in `step2Launch`), so a hung
    /// pass here must trip like every other post-launch discovery read,
    /// not block indefinitely on `MenuBarDiscoverer`'s own shared serial
    /// queue.
    func discoverDeclared(pid: pid_t, identifier: String) -> DiscoveredItem? {
        let deadline = environment.pump.now() + 5
        repeat {
            guard !isTerminal else { return nil }
            environment.pump.run(0.1)
            if let result = environment.pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }) {
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

    /// P0-6: a discovery-confirmed reap of *all three* helpers, retried
    /// within `seconds` -- used only by a mid-run relaunch (section 2:
    /// "a relaunch first rests the spacer, quits and reaps all three
    /// helpers"), which really does start over with three fresh ones. F2
    /// (Amendment v6): the generic one-shot cleanup and the staged
    /// teardown never call this -- see `confirmNonProtectedReap()`/
    /// `confirmProtectedReap()` below, which keep Protected running until
    /// the staged fold read has passed. A failed discovery pass is
    /// inconclusive, never confirmed.
    @discardableResult
    func confirmReap(within seconds: Double = 5) -> Bool {
        expansionDriver?.collapse()
        channel?.quitAll()
        channel?.quitProtected()
        environment.pump.run(0.5)
        let helperPIDs: Set<pid_t> = Set([targetHelper, spacerHelper, protectedHelper].compactMap { $0?.pid })
        return waitForReap(of: helperPIDs, within: seconds, recordPrefix: "reap")
    }

    /// F2: the staged teardown's first stage -- Target and the spacer
    /// only. Protected is left running so the staged fold read still has
    /// a live reference.
    @discardableResult
    func confirmNonProtectedReap(within seconds: Double = 5) -> Bool {
        expansionDriver?.collapse()
        channel?.quitAll()
        environment.pump.run(0.5)
        let helperPIDs: Set<pid_t> = Set([targetHelper, spacerHelper].compactMap { $0?.pid })
        return waitForReap(of: helperPIDs, within: seconds, recordPrefix: "reap.nonProtected")
    }

    /// F2: the staged teardown's last helper-quit stage -- Protected
    /// alone, only once the settled fold read (with Protected as the sole
    /// reference) has confirmed absent.
    @discardableResult
    func confirmProtectedReap(within seconds: Double = 5) -> Bool {
        channel?.quitProtected()
        environment.pump.run(0.5)
        let helperPIDs: Set<pid_t> = Set([protectedHelper].compactMap { $0?.pid })
        return waitForReap(of: helperPIDs, within: seconds, recordPrefix: "reap.protected")
    }

    /// Shared retry loop behind the three reap variants above: re-discover
    /// (through `timedDiscoverer` -- round 4 item 3/F6: each attempt is
    /// bounded, so one hung pass cannot swallow the whole budget) until a
    /// pass lists none of `helperPIDs`, or the deadline passes.
    private func waitForReap(of helperPIDs: Set<pid_t>, within seconds: Double, recordPrefix: String) -> Bool {
        guard !helperPIDs.isEmpty else { return true }
        let deadline = environment.pump.now() + seconds
        repeat {
            let listed: Set<pid_t>? = environment.pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }).map { Set($0.set.items.map(\.key.pid)) }
            if C1ReapCheck.confirmed(listedPIDs: listed, helperPIDs: helperPIDs) {
                evidence?.record("\(recordPrefix).confirmed", [:])
                return true
            }
            environment.pump.run(0.2)
        } while environment.pump.now() < deadline
        evidence?.record("\(recordPrefix).notConfirmed", [:])
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
