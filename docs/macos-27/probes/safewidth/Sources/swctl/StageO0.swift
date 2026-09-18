// Stage O0 — replicate the observation behind FINDINGS' "order dependence".
//
// The original run (axspike2g) held, in one process, a spacer created at length 1
// and then three 24 pt probes; its first step was 1 -> 600 directly, while an
// earlier run had stepped 1 -> 300 -> 600. Here the same topology is rebuilt, with
// markers on the probes instead of digits so pixels can say which are visible,
// and both paths are run N times with captures at fixed hold times.
//
// There is no P in this topology, so the guard's protected check is fed a
// synthetic "present" reading; the user-item templates still guard the user's bar.
import AppKit
import SafeWidthCore

final class O0Topology: SpacerControl {
    static let probeLength: CGFloat = 24
    static let restLength: CGFloat = 1
    static let probeNames = ["probe0", "probe1", "probe2"]

    private(set) var spacer: NSStatusItem?
    private(set) var probes: [NSStatusItem] = []
    private let palette: Palette
    private let probePairs: [(RGBA, RGBA)]

    init(palette: Palette) {
        self.palette = palette
        let t = palette.pairs["T"]!
        let p = palette.pairs["P"]!
        probePairs = [t, p, (t.1, t.0)]
    }

    func markerSpecs() -> [String: MarkerSpec] {
        var specs: [String: MarkerSpec] = [:]
        for (name, pair) in zip(Self.probeNames, probePairs) {
            specs[name] = Palette.spec(pair, narrow: false)
        }
        specs["S.left"] = palette.spec("S.left")
        specs["S.right"] = palette.spec("S.right")
        return specs
    }

    /// Spacer first at length 1 with a "|" title, then the three probes, as the
    /// original did. The spacer also carries our edge markers.
    func build() {
        Spacer.forgetPreferredPositions()
        let spacer = NSStatusBar.system.statusItem(withLength: Self.restLength)
        spacer.button?.title = "|"
        spacer.button?.setAccessibilityIdentifier(Spacer.identifier)
        if let button = spacer.button {
            let left = MarkerView(frame: NSRect(x: 0, y: 6, width: Spacer.markerWidth, height: Spacer.markerHeight))
            left.colours = palette.nsPair("S.left")
            left.autoresizingMask = [.maxXMargin]
            button.addSubview(left)
            let right = MarkerView(frame: NSRect(x: max(0, button.bounds.width - Spacer.markerWidth), y: 6, width: Spacer.markerWidth, height: Spacer.markerHeight))
            right.colours = palette.nsPair("S.right")
            right.autoresizingMask = [.minXMargin]
            button.addSubview(right)
        }
        self.spacer = spacer
        Session.spin(0.3)
        probes = zip(Self.probeNames, probePairs).map { name, pair in
            let item = NSStatusBar.system.statusItem(withLength: Self.probeLength)
            item.button?.image = Self.marker(pair)
            item.button?.imagePosition = .imageOnly
            item.button?.setAccessibilityIdentifier("IceSpike4-\(name)")
            Session.spin(0.2)
            return item
        }
    }

    func remove() {
        probes.forEach { NSStatusBar.system.removeStatusItem($0) }
        probes = []
        if let spacer {
            NSStatusBar.system.removeStatusItem(spacer)
        }
        spacer = nil
        Spacer.forgetPreferredPositions()
    }

    /// nil = the original rest length, 1.
    func set(_ length: Double?) {
        spacer?.length = length.map { CGFloat($0) } ?? Self.restLength
    }

    var appKitFrame: CGRect? {
        spacer?.button?.window?.frame
    }

    private static func marker(_ pair: (RGBA, RGBA)) -> NSImage {
        let left = Palette.nsColour(pair.0)
        let right = Palette.nsColour(pair.1)
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            left.setFill()
            NSRect(x: 0, y: 0, width: rect.width / 2, height: rect.height).fill()
            right.setFill()
            NSRect(x: rect.width / 2, y: 0, width: rect.width / 2, height: rect.height).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

enum StageO0 {
    static let paths: [(name: String, steps: [Double])] = [
        ("jump", [600]),
        ("step", [300, 600]),
    ]

    static func run(_ experiment: Experiment, repeats: Int) throws {
        let topology = O0Topology(palette: experiment.palette)
        var instrument: Instrument?
        defer {
            experiment.teardown(removeOwnItems: { topology.remove() }, instrument: instrument)
        }
        _ = try experiment.launchFront(FrontConfig.all["mid"]!)
        try experiment.captureBaseline()
        let live = experiment.instrument(markers: topology.markerSpecs())
        instrument = live
        let world = LiveWorld(
            instrument: live, spacer: topology, deadman: experiment.deadman, evidence: experiment.evidence,
            expectedFrontmost: experiment.front.bundleID, helperPids: [],
            guardState: Stages.guardFor(experiment, protectedExpected: Span(lo: 0, hi: 1))
        )
        world.pillThreshold = experiment.pillThreshold
        world.syntheticProtected = .unique(Span(lo: 0, hi: 1))
        let runner = Runner(world: world, config: Stages.runnerConfig)
        for rep in 0..<repeats {
            for path in paths {
                world.context = ["stage": "o0", "path": path.name, "rep": rep]
                topology.remove()
                Session.spin(0.5)
                topology.build()
                Session.spin(1.5)
                let baseline = world.assess(length: nil)
                experiment.evidence.record("o0.baseline", world.context.merging([
                    "markers": world.last.map { $0.markers.mapValues(LiveWorld.describe) } ?? [:],
                    "decision": baseline.map { String(describing: $0.decision) } ?? "no capture",
                    "capture": world.last.flatMap { experiment.evidence.keep($0.frame.file, label: "o0-base-\(path.name)-\(rep)") } ?? "?",
                ]) { $1 })
                let outcome = walk(path.steps, runner: runner, world: world, experiment: experiment, label: "\(path.name)-\(rep)")
                print("O0 \(path.name) rep \(rep): \(outcome)")
                guard outcome.hasPrefix("settled") else {
                    return
                }
                // O0 has no Actors latch, so the rest is checked here: anything but a
                // settled rest (a guard stop or harm included) ends the stage.
                let rest = runner.rest(pillAtStart: false)
                guard case .settled = rest else {
                    print("O0 \(path.name) rep \(rep): return to rest ended as \(rest) — stopping")
                    return
                }
            }
        }
    }

    /// Steps through the path; the last step is held with captures at the hold
    /// times. Returns a short description of how it ended.
    private static func walk(_ steps: [Double], runner: Runner, world: LiveWorld, experiment: Experiment, label: String) -> String {
        for (index, length) in steps.enumerated() {
            let isLast = index == steps.count - 1
            let outcome = runner.probe(length: length, holds: isLast ? Stages.holds : [], pillAtStart: false)
            if let observation = world.last {
                experiment.evidence.record("o0.step", world.context.merging([
                    "length": length,
                    "outcome": String(describing: outcome),
                    "markers": observation.markers.mapValues(LiveWorld.describe),
                    "capture": experiment.evidence.keep(observation.frame.file, label: "o0-\(label)-\(Int(length))") ?? "?",
                ]) { $1 })
            }
            guard case .settled = outcome else {
                return String(describing: outcome)
            }
        }
        return "settled"
    }
}
