// Stages C (calibration and null control) and O0 (replicating the original
// order-dependence observation).
import AppKit
import SafeWidthCore

enum Stages {
    static let runnerConfig = RunnerConfig(
        captureInterval: 0.05,
        settleSpan: 0.6,
        settleTolerance: 0.5,
        settleTimeout: 5,
        restoreTimeout: 3,
        maxCaptureFailures: 3
    )
    static let holds: [Double] = [0.25, 0.5, 1, 2, 4, 8]

    static func guardFor(_ experiment: Experiment, protectedExpected: Span) -> SafetyGuard {
        SafetyGuard(
            baselines: experiment.baselines,
            protectedExpected: protectedExpected,
            protectedTolerance: 1.0,
            anchorTolerance: 1.0
        )
    }

    static func markerSpecs(_ experiment: Experiment) -> [String: MarkerSpec] {
        var specs: [String: MarkerSpec] = [:]
        for name in ["T", "P", "S.left", "S.right"] {
            specs[name] = experiment.palette.spec(name)
        }
        return specs
    }

    // MARK: - C: calibration with our items, and the null control

    static func calibrationAndNullControl(_ experiment: Experiment, config: FrontConfig, nullSeconds: Double) throws {
        var spacer: Spacer?
        var instrument: Instrument?
        defer {
            experiment.teardown(removeOwnItems: { spacer?.remove() }, instrument: instrument)
        }
        _ = try experiment.launchFront(config)
        // The baseline has to be taken with F already in front: the bar is
        // translucent over whatever window is beneath it.
        try experiment.captureBaseline()
        let live = experiment.instrument(markers: markerSpecs(experiment))
        instrument = live
        let protectedApp = try experiment.launchHelper(experiment.protected, marker: "P")
        spacer = experiment.makeSpacer()
        let targetApp = try experiment.launchHelper(experiment.target, marker: "T")
        Session.spin(1.0)
        guard let spacer else {
            return
        }
        let rest = experiment.establishRest(live, spacer: spacer)
        print("C1 \(config.name): rest \(rest.ok ? "ok" : "FAILED: \(rest.reasons.joined(separator: "; "))")")
        guard rest.ok, case .unique(let protectedSpan) = rest.markers["P"] ?? .absent else {
            throw ExperimentError.restCheckFailed(rest.reasons)
        }
        let world = LiveWorld(
            instrument: live, spacer: spacer, deadman: experiment.deadman, evidence: experiment.evidence,
            expectedFrontmost: experiment.front.bundleID,
            helperPids: [protectedApp.processIdentifier, targetApp.processIdentifier],
            guardState: guardFor(experiment, protectedExpected: protectedSpan)
        )
        world.pillThreshold = experiment.pillThreshold
        world.context = ["stage": "c", "config": config.name]
        if let observation = live.observe(spacer: spacer, extraPids: []) {
            world.restAgentItems = Set(observation.ax.items.filter { $0.bundle == "com.apple.MenuBarAgent" }.map(LiveWorld.key))
            world.restSpacerX = observation.spacerAXLeft
        }
        measureCadence(world)
        measureRestore(world)
        nullControl(world, seconds: nullSeconds)
    }

    /// C1: how long one assessment takes end to end.
    private static func measureCadence(_ world: LiveWorld) {
        var durations: [Double] = []
        for _ in 0..<10 {
            let start = world.now()
            _ = world.assess(length: nil)
            durations.append(world.now() - start)
        }
        let sorted = durations.sorted()
        world.evidence.record("c1.cadence", ["durations": durations, "median": sorted[sorted.count / 2], "max": sorted.last ?? 0])
        print(String(format: "C1 cadence: median %.0f ms, max %.0f ms", sorted[sorted.count / 2] * 1000, (sorted.last ?? 0) * 1000))
    }

    /// C1: from a tiny expansion that stays inside free room, how long until the
    /// guard sees a clean, settled rest again.
    private static func measureRestore(_ world: LiveWorld) {
        let runner = Runner(world: world, config: runnerConfig)
        let expanded = runner.probe(length: 8, holds: [], pillAtStart: false)
        let start = world.now()
        let back = runner.rest(pillAtStart: false)
        let elapsed = world.now() - start
        world.evidence.record("c1.restore", ["expanded": String(describing: expanded), "rest": String(describing: back), "seconds": elapsed])
        print(String(format: "C1 restore: %.2f s", elapsed) + " (\(String(describing: back).prefix(60)))")
    }

    /// C2: our items at rest, the guard on, nothing moving. Every non-clean
    /// decision here is drift, and its rate is the noise floor.
    private static func nullControl(_ world: LiveWorld, seconds: Double) {
        let start = world.now()
        var counts: [String: Int] = [:]
        while world.now() - start < seconds {
            guard let assessment = world.assess(length: nil) else {
                counts["captureFailed", default: 0] += 1
                continue
            }
            let key: String
            switch assessment.decision {
            case .clean(let info): key = info.isEmpty ? "clean" : "cleanWithInfo"
            case .suspect: key = "suspect"
            case .restore: key = "restore"
            case .stop: key = "stop"
            }
            counts[key, default: 0] += 1
            world.pause(0.2)
        }
        world.evidence.record("c2.null", ["seconds": seconds, "decisions": counts])
        print("C2 null control \(Int(seconds)) s: \(counts)")
    }
}
