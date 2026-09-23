// Shared set-up for every stage that puts our items in the bar: the F config,
// the actors in creation order P, S, T, the rest-state check, resets, teardown.
import AppKit
import SafeWidthCore

struct FrontConfig {
    let name: String
    let menus: Int
    let title: String

    static let all: [String: FrontConfig] = [
        "narrow": FrontConfig(name: "narrow", menus: 0, title: "Menu"),
        "mid": FrontConfig(name: "mid", menus: 6, title: "Menu"),
        "wide": FrontConfig(name: "wide", menus: 11, title: "Menu"),
    ]
}

struct Palette {
    let pairs: [String: (RGBA, RGBA)]

    /// T, P and S's two edges each get their own ordered pair of colours that B0
    /// never saw in the strip.
    init(unused: [RGBA]) throws {
        guard unused.count >= 8 else {
            throw ExperimentError.notEnoughColours(unused.count)
        }
        pairs = [
            "T": (unused[0], unused[1]),
            "P": (unused[2], unused[3]),
            "S.left": (unused[4], unused[5]),
            "S.right": (unused[6], unused[7]),
        ]
    }

    func spec(_ name: String, tolerance: Int = 48) -> MarkerSpec? {
        guard let pair = pairs[name] else {
            return nil
        }
        return Self.spec(pair, narrow: name.hasPrefix("S."), tolerance: tolerance)
    }

    static let scale = 2.0

    static func spec(_ pair: (RGBA, RGBA), narrow: Bool, tolerance: Int = 48) -> MarkerSpec {
        MarkerSpec(
            left: ColorMatch(center: pair.0, tolerance: tolerance),
            right: ColorMatch(center: pair.1, tolerance: tolerance),
            minRun: MarkerGeometry.minRun(narrow: narrow, scale: scale),
            maxGap: 2,
            minRows: MarkerGeometry.minRows(scale: scale)
        )
    }

    static func nsColour(_ colour: RGBA) -> NSColor {
        NSColor(srgbRed: CGFloat(colour.r) / 255, green: CGFloat(colour.g) / 255, blue: CGFloat(colour.b) / 255, alpha: 1)
    }

    func nsPair(_ name: String) -> (NSColor, NSColor) {
        let colours = pairs[name]!
        return (Self.nsColour(colours.0), Self.nsColour(colours.1))
    }
}

enum ExperimentError: Error {
    case notEnoughColours(Int)
    case launchFailed(String)
    case notFrontmost(String)
    case restCheckFailed([String])
}

struct RestCheck {
    let ok: Bool
    let reasons: [String]
    let markers: [String: MarkerResult]
}

final class Experiment {
    let apps: URL
    let calibration: Calibration
    let palette: Palette
    let evidence: Evidence
    let capture: StripCapture
    private(set) var baselines: [UserItemBaseline] = []
    let userFrontmost: String?
    let deadman: DeadmanThread
    let target: HelperApp
    let protected: HelperApp
    let front: HelperApp

    init(apps: URL, calibrationFile: URL, evidence: Evidence, capture: StripCapture) throws {
        self.apps = apps
        self.evidence = evidence
        self.capture = capture
        calibration = try JSONDecoder().decode(Calibration.self, from: Data(contentsOf: calibrationFile))
        palette = try Palette(unused: calibration.unusedColours.compactMap(Calibrate.rgba))
        userFrontmost = Session.frontmostBundleID()
        deadman = DeadmanThread(limit: 2.0, evidence: evidence)
        target = Session.helper("Target", bundleID: "com.icespike4.target", apps: apps)
        protected = Session.helper("Protected", bundleID: "com.icespike4.protected", apps: apps)
        front = Session.helper("F", bundleID: "com.icespike4.front", apps: apps)
        deadman.start()
        evidence.record("experiment.start", ["userFrontmost": userFrontmost ?? "?", "b0": calibration.b0RunId])
    }

    private(set) var items: [CalibratedItem] = []
    private(set) var ink = ColorMatch(center: RGBA(0, 0, 0), tolerance: 100)
    /// Orange pixels right of the notch mean the microphone pill; the floor comes
    /// from this run's own baseline, because the wallpaper behind the translucent
    /// bar is a different colour at different times of day.
    private(set) var pillThreshold = 40

    /// Taken once F is frontmost and before any item of ours exists. The menu bar
    /// is translucent over whatever window is under it, so the reference has to be
    /// captured with the same app in front as the trials will run with.
    func captureBaseline() throws {
        let baseline = try Self.runBaseline(capture: capture, palette: palette, evidence: evidence)
        baselines = baseline.baselines
        items = baseline.items
        ink = baseline.ink
        pillThreshold = baseline.orange + 60
        axPids = baseline.pids
    }

    /// Processes that owned a menu bar extra at baseline, plus ours. Asking only
    /// these keeps one capture's AX walk short.
    private(set) var axPids: Set<pid_t> = []

    /// The pill takes ≈ 37 pt of the room right of the notch, which is more than
    /// the slack our items run in, so a trial cannot be measured while it is there.
    @discardableResult
    func waitForPillToGo(timeout: Double = 120) -> Bool {
        Self.waitForPill(toGoWithin: timeout, evidence: evidence)
    }

    /// One wait loop for the one physical object; the baseline and a voided trial
    /// used to have their own, with different timeouts and different record names.
    static func waitForPill(toGoWithin timeout: Double, evidence: Evidence) -> Bool {
        let deadline = Session.clock() + timeout
        while Session.clock() < deadline {
            if AXReader.pillLike(AXReader.snapshot()) == nil {
                Session.spin(1.0)
                evidence.record("pill.gone", [:])
                return true
            }
            Session.spin(2.0)
        }
        evidence.record("pill.stillPresent", ["waited": timeout])
        return false
    }

    /// LaunchServices hands focus back to the app that had it when a background
    /// helper starts, so F has to be put in front again after every launch.
    @discardableResult
    func ensureFront() -> Bool {
        if Session.frontmostBundleID() == front.bundleID {
            return true
        }
        Session.activate(app: front.url)
        let ok = Session.waitForFrontmost(front.bundleID)
        evidence.record("front.reactivated", ["ok": ok, "frontmost": Session.frontmostBundleID() ?? "?"])
        return ok
    }

    var presenceMinimum: [String: Int] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.presenceMinimum) })
    }

    func instrument(markers: [String: MarkerSpec]) -> Instrument {
        Instrument(capture: capture, baselines: baselines, presenceMinimum: presenceMinimum, ink: ink, markerSpecs: markers, axPids: axPids)
    }

    static let baselineCaptures = 8
    static let baselineInterval = 0.4
    static let baselineAttempts = 3

    /// This run's own baseline, taken before anything of ours is in the bar: the
    /// wallpaper behind the translucent bar changes during the day, so templates,
    /// the ink colour and the marker negative control are only valid per run.
    static let pillWait = 180.0

    private static func runBaseline(capture: StripCapture, palette: Palette, evidence: Evidence)
        throws -> (items: [CalibratedItem], baselines: [UserItemBaseline], ink: ColorMatch, orange: Int, pids: Set<pid_t>) {
        var snapshot = AXReader.snapshot()
        if let pill = AXReader.pillLike(snapshot) {
            print("baseline: microphone pill present at x=\(Int(pill.x)); waiting up to \(Int(pillWait)) s for it to go")
            guard waitForPill(toGoWithin: pillWait, evidence: evidence) else {
                throw ExperimentError.launchFailed("microphone pill still in the bar after \(Int(pillWait)) s")
            }
            snapshot = AXReader.snapshot()
        }
        // The bar only settles a moment after F comes to the front, and a run whose
        // reference was taken mid-change would call every item dynamic. Retry until
        // the captures agree with each other.
        var result: (items: [CalibratedItem], baselines: [UserItemBaseline], ink: ColorMatch)?
        var bitmaps: [Bitmap] = []
        for attempt in 0..<baselineAttempts {
            Session.spin(1.5)
            var frames: [StripCapture.Frame] = []
            for _ in 0..<baselineCaptures {
                if let frame = capture.capture(clock: Session.clock) {
                    frames.append(frame)
                    evidence.keep(frame.file, label: "baseline")
                }
                Session.spin(baselineInterval)
            }
            bitmaps = frames.map(\.bitmap).suffix(6).map { $0 }
            snapshot = AXReader.snapshot()
            guard bitmaps.count >= 4, let candidate = Calibrate.baselines(ax: snapshot, captures: bitmaps) else {
                continue
            }
            let dynamic = candidate.items.filter { $0.kind == "dynamic" }.count
            evidence.record("baseline.attempt", ["attempt": attempt, "items": candidate.items.count, "dynamic": dynamic])
            result = candidate
            if dynamic <= max(1, candidate.items.count / 5) {
                break
            }
            print("baseline: \(dynamic)/\(candidate.items.count) items changing; the bar has not settled, retrying")
        }
        guard let result else {
            throw ExperimentError.launchFailed("run baseline: no usable captures")
        }
        let collisions = palette.pairs.keys.sorted().filter { name in
            guard let spec = palette.spec(name) else { return false }
            return bitmaps.contains { Pixels.findMarker(spec, in: $0) != .absent }
        }
        evidence.record("baseline", [
            "items": result.items.map { ["id": $0.id, "x": $0.x, "w": $0.w, "kind": $0.kind, "presence": $0.presenceMinimum] },
            "ink": Calibrate.hex(result.ink.center),
            "markerCollisions": collisions,
            "frontmost": snapshot.frontmostBundle,
        ])
        guard collisions.isEmpty else {
            throw ExperimentError.launchFailed("marker colours already present in the bar: \(collisions)")
        }
        if let pill = AXReader.pillLike(AXReader.snapshot()) {
            evidence.record("baseline.pillArrivedDuringBaseline", ["x": pill.x])
            throw ExperimentError.launchFailed("the microphone pill arrived while the baseline was being taken; rerun")
        }
        let dynamic = result.items.filter { $0.kind == "dynamic" }.map(\.id)
        let orange = bitmaps.map { Pixels.count(Instrument.orange, in: $0, span: Instrument.rightOfNotch) }.max() ?? 0
        print("baseline: \(result.items.count) user items, ink \(Calibrate.hex(result.ink.center)), dynamic \(dynamic), orange floor \(orange)")
        let pids = Set(snapshot.items.map(\.pid))
        return (result.items, result.baselines, result.ink, orange, pids)
    }

    func helperArguments(_ name: String) -> [String] {
        guard let pair = palette.pairs[name] else {
            return ["--controller", "\(getpid())"]
        }
        return ["--controller", "\(getpid())", "--left", Calibrate.hex(pair.0), "--right", Calibrate.hex(pair.1), "--length", "12"]
    }

    static let fallbackRest = 10.0

    /// Rest check with Ice's own rest first. If the bar has no room for it (T is
    /// already overflowed at rest), that is recorded as a finding and the spacer
    /// falls back to a fixed narrow rest; the run is labelled accordingly.
    func establishRest(_ instrument: Instrument, spacer: Spacer) -> RestCheck {
        let iceRest = checkRest(instrument, spacer: spacer)
        guard !iceRest.ok, iceRest.reasons.contains("T marker absent") else {
            evidence.record("rest.mode", ["mode": "ice"])
            return iceRest
        }
        evidence.record("rest.iceRestNoRoom", ["reasons": iceRest.reasons, "fallback": Self.fallbackRest])
        print("rest: no room for Ice's rest width (T overflowed at rest); falling back to fixed \(Int(Self.fallbackRest)) pt")
        spacer.fixedRest = Self.fallbackRest
        Session.spin(1.0)
        let fallback = checkRest(instrument, spacer: spacer)
        evidence.record("rest.mode", ["mode": "fixed", "length": Self.fallbackRest, "ok": fallback.ok])
        return fallback
    }

    // MARK: - F

    func launchFront(_ config: FrontConfig) throws -> NSRunningApplication {
        Session.quit(front)
        let arguments = ["--controller", "\(getpid())", "--menus", "\(config.menus)", "--title", config.title]
        guard let app = Session.launch(front, background: false, arguments: arguments) else {
            throw ExperimentError.launchFailed("F")
        }
        if !Session.waitForFrontmost(front.bundleID) {
            Session.activate(bundleID: front.bundleID)
            guard Session.waitForFrontmost(front.bundleID) else {
                throw ExperimentError.notFrontmost(Session.frontmostBundleID() ?? "?")
            }
        }
        Session.spin(0.5)
        let snapshot = AXReader.snapshot()
        evidence.record("front.up", ["config": config.name, "menuRightEdge": snapshot.frontmostMenuRightEdge, "menus": snapshot.frontmostMenuCount])
        return app
    }

    // MARK: - Actors

    func launchHelper(_ helper: HelperApp, marker: String) throws -> NSRunningApplication {
        guard let app = Session.launch(helper, background: true, arguments: helperArguments(marker)) else {
            throw ExperimentError.launchFailed(helper.name)
        }
        Session.spin(0.6)
        ensureFront()
        return app
    }

    func makeSpacer() -> Spacer {
        Spacer.forgetPreferredPositions()
        let spacer = Spacer(leftColours: palette.nsPair("S.left"), rightColours: palette.nsPair("S.right"))
        Session.spin(0.4)
        return spacer
    }

    /// The rest state every trial must start from.
    func checkRest(_ instrument: Instrument, spacer: Spacer) -> RestCheck {
        guard let observation = instrument.observe(spacer: spacer, extraPids: []) else {
            return RestCheck(ok: false, reasons: ["capture failed"], markers: [:])
        }
        var reasons: [String] = []
        var mids: [String: Double] = [:]
        for name in ["T", "S.left", "P"] {
            if case .unique(let span) = observation.markers[name] ?? .absent {
                mids[name] = span.mid
            } else {
                reasons.append("\(name) marker \(LiveWorld.describe(observation.markers[name] ?? .absent))")
            }
        }
        if let t = mids["T"], let s = mids["S.left"], let p = mids["P"], !(t < s && s < p) {
            reasons.append("order is not T < S < P")
        }
        if let p = mids["P"], let firstUser = baselines.first?.template.originX, p >= firstUser {
            reasons.append("P is not left of every user item")
        }
        // An icon that changed in place (a badge, a status colour) is not a lost
        // item: if its ink is still in its own span, reclassify it as dynamic and
        // carry on, the way the guard does mid-trial.
        for id in staticItemsNotAtBaseline(observation) {
            guard let baseline = baselines.first(where: { $0.id == id }),
                  instrument.inkCount(observation, span: baseline.span) >= (presenceMinimum[id] ?? 1) else {
                reasons.append("user item \(id) not at its baseline position")
                continue
            }
            instrument.reclassifyDynamic(id)
            if let index = baselines.firstIndex(where: { $0.id == id }) {
                baselines[index].kind = .dynamic
            }
            evidence.record("rest.appearanceChanged", ["id": id])
        }
        if observation.orangePixels >= pillThreshold {
            reasons.append("microphone pill present")
        }
        let check = RestCheck(ok: reasons.isEmpty, reasons: reasons, markers: observation.markers)
        evidence.record("rest.check", [
            "ok": check.ok,
            "reasons": reasons,
            "markers": observation.markers.mapValues(LiveWorld.describe),
            "capture": evidence.keep(observation.frame.file, label: "rest") ?? "?",
        ])
        return check
    }

    func staticItemsNotAtBaseline(_ observation: Observation) -> [String] {
        zip(baselines, observation.items).compactMap { baseline, reading -> String? in
            guard baseline.kind == .static else { return nil }
            if case .found(let offset) = reading.template, abs(offset) <= 0.5 { return nil }
            return baseline.id
        }
    }

    // MARK: - Teardown

    /// Removes everything of ours and gives the user their frontmost app back, then
    /// checks that every static user item is where B0 saw it.
    func teardown(removeOwnItems: () -> Void, instrument: Instrument?) {
        removeOwnItems()
        Session.quit(target)
        Session.quit(protected)
        Session.quit(front)
        if let userFrontmost {
            Session.activate(bundleID: userFrontmost)
        }
        Session.spin(1.0)
        guard let instrument, let observation = instrument.observe(spacer: nil, extraPids: []) else {
            return
        }
        let displaced = staticItemsNotAtBaseline(observation)
        evidence.record("teardown", [
            "frontmost": Session.frontmostBundleID() ?? "?",
            "restoredFrontmost": userFrontmost ?? "?",
            "staticItemsNotAtBaseline": displaced,
            "helpersAlive": [target, protected, front].flatMap(Session.running).count,
            "capture": evidence.keep(observation.frame.file, label: "teardown") ?? "?",
        ])
        print("teardown: static items not at baseline: \(displaced.isEmpty ? "none" : displaced.joined(separator: ", "))")
    }
}
