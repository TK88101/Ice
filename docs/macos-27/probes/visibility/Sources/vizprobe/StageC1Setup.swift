// I5 setup: section 2's bundle check, the pre-launch preflight/baseline,
// `caffeinate -d` for the run's duration, the fixed launch order
// (Protected, then the spacer, then Target) with a fresh discovery
// confirming each one before the next helper starts, and the
// discovery-confirmed reap P0-6 requires before any relaunch or at
// teardown.
import AppKit
import C1Core
import C1Live
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

extension StageC1 {
    /// Existing bundle ids only (Target's and Protected's -- the spacer
    /// carries Protected's, P0-1), executables inside their bundles, and
    /// no helper under either already running.
    func step0Bundles() -> StepResult {
        for (url, expected) in [(apps.target, C1HelperRole.target), (apps.protected, C1HelperRole.protected), (apps.spacer, C1HelperRole.protected)] {
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
        let running = NSWorkspace.shared.runningApplications.filter { C1HelperRole.all.contains($0.bundleIdentifier ?? "") }
        guard running.isEmpty else { return .abort("\(running.count) helper(s) under a C1 bundle id already running") }
        return .ok
    }

    /// Section 5 step 1's "dry minute" setup half: geometry, the warm-up,
    /// evidence, and `caffeinate -d` for the run's duration only.
    func step1Setup() -> StepResult {
        guard let screen = NSScreen.main, let geometry = BarGeometry(screen: screen) else {
            return .abort("no bar geometry (NSScreen.main unavailable)")
        }
        self.geometry = geometry

        do {
            evidence = try LiveEvidence(binaryURLs: c1BinaryURLs(), arguments: CommandLine.arguments, geometry: geometry, parameters: parameters, suffix: dry ? "vzc1dry" : "vzc1")
        } catch {
            return .abort("could not create the evidence directory: \(error)")
        }

        // caffeinate -d, ended by teardown or emergencyStop -- never left
        // running past this process's own life either, since it is a
        // child process this process owns.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-d"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            caffeinate = process
        } catch {
            evidence.record("caffeinate.failed", ["error": "\(error)"])
        }

        warmUpOnce()
        return .ok
    }

    /// Section 2: "warmed up once at the start (24 captures, 0.25 s
    /// apart)." Before any helper exists -- pre-channel, so the raw
    /// capturer is the right one here (P0-2 only requires
    /// `latchingCapturer` for post-channel captures).
    func warmUpOnce() {
        for _ in 0..<PreflightCheck.warmUpCaptures {
            _ = capturer.capture()
            Pump.run(PreflightCheck.warmUpInterval)
        }
    }

    /// Section 2's launch order: Protected, the spacer, Target -- each
    /// waits for `up` and a fresh discovery listing its item (by pid and
    /// AX identifier, P0-1 -- never by bundle id) before the next helper
    /// starts. Builds `channel` and, from it, `latchingCapturer` (P0-2):
    /// every capture from here on goes through the latch first, even
    /// though it has no owner baseline to assess against yet (its own
    /// `assess` closure reads `ownerBaseline` lazily and is a no-op until
    /// `step3Baseline` sets it -- there is nothing to compare against
    /// before then, so silence is the faithful answer, not a gap).
    func step2Launch() -> StepResult {
        guard let protected = launchAndDiscover(label: "protected", app: apps.protected, bundleID: C1HelperRole.protected, role: "reference", identifier: "vz-reference") else {
            return .abort("could not launch or discover Protected")
        }
        protectedHelper = protected.helper
        protectedKey = protected.key

        guard let spacer = launchAndDiscover(label: "spacer", app: apps.spacer, bundleID: C1HelperRole.protected, role: "spacer", identifier: SpacerIdentifier.value) else {
            return .abort("could not launch or discover the spacer")
        }
        spacerHelper = spacer.helper
        spacerKey = spacer.key

        guard let target = launchAndDiscover(label: "target", app: apps.target, bundleID: C1HelperRole.target, role: "target", identifier: "vz-target") else {
            return .abort("could not launch or discover Target")
        }
        targetHelper = target.helper
        targetKey = target.key

        let channel = HelperControlChannel(helpers: [protected.helper, spacer.helper, target.helper], spacer: { [weak self] in self?.spacerHelper })
        self.channel = channel
        expansionDriver = C1ExpansionDriver(channel: channel, dry: dry)
        latchingCapturer = LatchingCapturer(
            base: capturer,
            channel: channel,
            onTrip: { [weak self] reason in self?.onLatchTrip(reason) }
        ) { [weak self] image in
            self?.assessLatch(image: image) ?? .init(captureFailed: true)
        }
        evidence.record("step2.launched", ["protected": describeKey(protected.key), "spacer": describeKey(spacer.key), "target": describeKey(target.key)])
        return .ok
    }

    /// Deletes the bundle id's domain, launches one helper, waits for its
    /// `up` line, then discovers its declared item -- by pid and AX
    /// identifier (P0-1). `nil` on any failure -- the caller aborts the
    /// whole launch sequence rather than continue with a partial roster.
    func launchAndDiscover(label: String, app: URL, bundleID: String, role: String, identifier: String) -> (helper: HelperControl, key: ItemKey)? {
        // Neither vzhelper role here ever sets `--autosave`, so this never
        // has data to lose even when Protected and the spacer share a
        // bundle id and this runs while Protected is already up (P0-1) --
        // defense in depth against some stray process's leftovers, not a
        // uniqueness check any more.
        HelperDefaults.forget(bundleID)
        guard HelperDefaults.keys(bundleID) == [] else {
            evidence.record("helper.launchRefused", ["label": label, "reason": "the \(bundleID) domain is not verifiably empty"])
            return nil
        }
        guard let helper = try? HelperControl(appURL: app, bundleID: bundleID, role: role, arguments: ["--role", role, "--lifetime", "900"], controllerPID: getpid()) else {
            evidence.record("helper.launchFailed", ["label": label])
            return nil
        }
        guard helper.awaitReply("up", timeout: 5) != nil else {
            helper.quit()
            evidence.record("helper.noUp", ["label": label])
            return nil
        }
        guard let item = discoverDeclared(pid: helper.pid, identifier: identifier) else {
            helper.quit()
            evidence.record("helper.notDiscovered", ["label": label])
            return nil
        }
        return (helper, item.key)
    }

    /// The one `.declared` item of `pid` with `identifier`, from a fresh
    /// discovery pass that read `pid` conclusively, within 5 s.
    func discoverDeclared(pid: pid_t, identifier: String) -> DiscoveredItem? {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            Pump.run(0.1)
            if let result = Pump.blocking({ await self.discoverer.discover(previous: nil) }) {
                let status = result.status(of: pid)
                if status.enumerated, !status.failed, !status.quarantined, !status.permissionDenied,
                   let item = result.set.items.first(where: { $0.key.pid == pid && $0.key.identifier == identifier && $0.basis == .declared }) {
                    return item
                }
            }
            Pump.run(0.2)
        } while Date() < deadline
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
        Pump.run(0.5)
        let helperPIDs: Set<pid_t> = Set([targetHelper, spacerHelper, protectedHelper].compactMap { $0?.pid })
        guard !helperPIDs.isEmpty else { return true }
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            let listed: Set<pid_t>? = Pump.blocking({ await self.discoverer.discover(previous: nil) }).map { Set($0.set.items.map(\.key.pid)) }
            if C1ReapCheck.confirmed(listedPIDs: listed, helperPIDs: helperPIDs) {
                evidence?.record("reap.confirmed", [:])
                return true
            }
            Pump.run(0.2)
        } while Date() < deadline
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

/// The spacer's own AX identifier (`SpacerItem.identifier` in
/// `Sources/vzhelper/main.swift`), restated here rather than imported: the
/// `vzhelper` executable target is not a library another target can
/// depend on.
enum SpacerIdentifier {
    static let value = "vz-spacer"
}
