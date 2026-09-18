// The T–S–P topology for one frontmost config, with the resets every trial
// starts from and the single jump probe that scans and bisections are built of.
import AppKit
import SafeWidthCore

enum ResetKind: String {
    /// Quit T, remove S, recreate S at rest, relaunch T.
    case full
    /// Put S back to rest and verify.
    case light
}

final class Actors {
    let experiment: Experiment
    let config: FrontConfig
    let instrument: Instrument
    let spacer: Spacer
    let world: LiveWorld
    let runner: Runner
    private(set) var protectedApp: NSRunningApplication
    private(set) var targetApp: NSRunningApplication
    /// Length at which the guard first fired; the config stops there.
    private(set) var harmAt: Double?
    /// The guard asked to stop (something it could not verify). Latched: no stage
    /// may expand the spacer again after this.
    private(set) var stopped = false

    private init(experiment: Experiment, config: FrontConfig, instrument: Instrument, spacer: Spacer,
                 world: LiveWorld, protectedApp: NSRunningApplication, targetApp: NSRunningApplication) {
        self.experiment = experiment
        self.config = config
        self.instrument = instrument
        self.spacer = spacer
        self.world = world
        self.protectedApp = protectedApp
        self.targetApp = targetApp
        runner = Runner(world: world, config: Stages.runnerConfig)
    }

    static func up(_ experiment: Experiment, config: FrontConfig) throws -> Actors {
        _ = try experiment.launchFront(config)
        // With F in front, and before any item of ours exists: this run's reference.
        try experiment.captureBaseline()
        let instrument = experiment.instrument(markers: Stages.markerSpecs(experiment))
        let protectedApp = try experiment.launchHelper(experiment.protected, marker: "P")
        let spacer = experiment.makeSpacer()
        let targetApp = try experiment.launchHelper(experiment.target, marker: "T")
        Session.spin(1.0)
        let rest = experiment.establishRest(instrument, spacer: spacer)
        guard rest.ok, case .unique(let protectedSpan) = rest.markers["P"] ?? .absent else {
            spacer.remove()
            throw ExperimentError.restCheckFailed(rest.reasons)
        }
        let world = LiveWorld(
            instrument: instrument, spacer: spacer, deadman: experiment.deadman, evidence: experiment.evidence,
            expectedFrontmost: experiment.front.bundleID,
            helperPids: [protectedApp.processIdentifier, targetApp.processIdentifier],
            guardState: Stages.guardFor(experiment, protectedExpected: protectedSpan)
        )
        world.pillThreshold = experiment.pillThreshold
        if let observation = instrument.observe(spacer: spacer, extraPids: []) {
            world.restAgentItems = Set(observation.ax.items.filter { $0.bundle == "com.apple.MenuBarAgent" }.map(LiveWorld.key))
            world.restSpacerX = observation.spacerAXLeft
        }
        return Actors(experiment: experiment, config: config, instrument: instrument, spacer: spacer,
                      world: world, protectedApp: protectedApp, targetApp: targetApp)
    }

    /// Returning to rest is a probe like any other: if the guard stops or harms
    /// there, that has to latch, or the next stage expands again on a bar the
    /// guard has already said it cannot verify.
    @discardableResult
    func restNow() -> ProbeOutcome {
        let outcome = runner.rest(pillAtStart: false)
        switch outcome {
        case .stop, .harm:
            note(ProbeRecord(outcome: outcome, sample: settledSample(outcome)), length: 0)
        default:
            break
        }
        return outcome
    }

    func reset(_ kind: ResetKind) -> RestCheck {
        switch kind {
        case .light:
            restNow()
        case .full:
            spacer.set(nil)
            world.deadman.setAtRest(true, at: world.now())
            Session.quit(experiment.target)
            spacer.recreate()
            Session.spin(0.4)
            if let app = try? experiment.launchHelper(experiment.target, marker: "T") {
                targetApp = app
            }
            world.helperPids = [protectedApp.processIdentifier, targetApp.processIdentifier]
            Session.spin(0.8)
        }
        let check = experiment.checkRest(instrument, spacer: spacer)
        // S is a new item after a full reset, so the x it rests at has to be read
        // again; W_selfov is measured against it.
        if check.ok, let observation = instrument.observe(spacer: spacer, extraPids: []) {
            world.restSpacerX = observation.spacerAXLeft
            world.restAgentItems = Set(observation.ax.items.filter { $0.bundle == "com.apple.MenuBarAgent" }.map(LiveWorld.key))
        }
        return check
    }

    /// Quits T while S stays where it is, for the attribution check.
    func quitTargetOnly() {
        world.helperPids = [protectedApp.processIdentifier]
        Session.quit(experiment.target)
    }

    struct ProbeRecord {
        let outcome: ProbeOutcome
        let sample: LegSample?
    }

    /// False once the guard has stopped or fired: from then on nothing expands.
    var canExpand: Bool {
        !stopped && harmAt == nil
    }

    /// The only way any stage expands the spacer. It refuses once `canExpand` is
    /// false and latches whatever the guard says about this expansion, so a stop
    /// or a harm cannot be lost by a caller that forgets to look.
    func expand(_ length: Double, holds: [Double]) -> ProbeRecord? {
        guard canExpand else {
            return nil
        }
        let outcome = runner.probe(length: length, holds: holds, pillAtStart: false)
        let record = ProbeRecord(outcome: outcome, sample: settledSample(outcome))
        note(record, length: length)
        return record
    }

    /// One probe from a verified rest state. Returns nil if the rest state could
    /// not be established (the trial is void, not a measurement) or if the guard
    /// stopped or fired on the way back to rest.
    func jump(_ length: Double, reset kind: ResetKind, holds: [Double], label: [String: Any]) -> ProbeRecord? {
        guard canExpand else {
            return nil
        }
        var restCheck = reset(kind)
        if !restCheck.ok, restCheck.reasons.contains("microphone pill present") {
            experiment.waitForPillToGo()
            restCheck = reset(.full)
        }
        if !restCheck.ok {
            restCheck = reset(.full)
        }
        // A light reset rests through the guard, which may have stopped or fired
        // there; a rest check that passes afterwards does not undo that.
        guard restCheck.ok, canExpand else {
            let reasons = canExpand ? restCheck.reasons : ["guard stopped or fired during the reset"]
            experiment.evidence.record("probe.void", label.merging(["length": length, "reasons": reasons]) { $1 })
            return nil
        }
        world.context = label.merging(["config": config.name, "reset": kind.rawValue]) { $1 }
        let record = expand(length, holds: holds)
        if case .settled = record?.outcome {
            restNow()
        }
        return record
    }

    /// The state a probe is characterised by: the latest observation, which is
    /// the longest hold's when that came after settling — the hold protocol exists
    /// because a layout that looks settled early may still change — and the
    /// settled capture when a short hold expired mid-transition.
    func settledSample(_ outcome: ProbeOutcome) -> LegSample? {
        if case .settled(_, _, let latest) = outcome {
            return latest
        }
        return nil
    }

    func note(_ record: ProbeRecord, length: Double) {
        var fields = world.context
        fields["length"] = length
        fields["outcome"] = String(describing: record.outcome)
        if let sample = record.sample {
            fields["target"] = String(describing: sample.target)
            fields["spacerLeft"] = sample.spacerLeft ?? -1
            fields["spacerLeftFromAX"] = sample.spacerLeftFromAX
            fields["spacerAppKitWidth"] = sample.spacerAppKitWidth ?? -1
            fields["spacerDrawn"] = sample.spacerDrawn.map { $0 ? "yes" : "no" } ?? "unknown"
        }
        if case .stop = record.outcome {
            stopped = true
            fields["stopped"] = true
        }
        if case .harm(_, let reasons, let restored) = record.outcome {
            harmAt = harmAt ?? length
            stopped = stopped || !restored
            fields["harmReasons"] = reasons.map { String(describing: $0) }
            fields["restored"] = restored
        }
        if let observation = world.last {
            fields["capture"] = experiment.evidence.keep(observation.frame.file, label: "probe-\(config.name)-\(Int(length))") ?? "?"
        }
        experiment.evidence.record("probe", fields)
    }

    func teardown() {
        experiment.teardown(removeOwnItems: { spacer.remove() }, instrument: instrument)
    }
}
