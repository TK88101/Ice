// The real World for SafeWidthCore's Runner: our spacer, a capture, the guard.
import AppKit
import SafeWidthCore

/// Anything the runner can expand and put back to rest.
protocol SpacerControl: AnyObject {
    func set(_ length: Double?)
    var appKitFrame: CGRect? { get }
}

extension Spacer: SpacerControl {}

final class LiveWorld: World {
    let instrument: Instrument
    let spacer: SpacerControl
    let deadman: DeadmanThread
    let evidence: Evidence
    let expectedFrontmost: String
    var helperPids: [pid_t]
    var guardState: SafetyGuard
    /// nil until the quit-T attribution has run for this config.
    var overflowAttributed: Bool?
    /// MenuBarAgent items present at rest; a new one appearing is the provisional
    /// sign of an overflow chevron until a template has been validated.
    var restAgentItems: Set<String> = []
    /// Replaces P's marker reading in topologies without P (O0).
    var syntheticProtected: MarkerResult?
    /// Orange pixels right of the notch above this mean the microphone pill.
    var pillThreshold = 40
    /// Ink drawn inside the pill's own AX span counts as "still on screen".
    static let pillInk = 12
    static let maxGuardCaptures = 200
    private var lastVerdict = "clean"
    private var keptGuardCaptures = 0

    static func verdictKind(_ decision: GuardDecision) -> String {
        switch decision {
        case .clean: "clean"
        case .suspect: "suspect"
        case .restore: "restore"
        case .stop: "stop"
        }
    }
    var context: [String: Any] = [:]
    private(set) var last: Observation?

    init(instrument: Instrument, spacer: SpacerControl, deadman: DeadmanThread, evidence: Evidence,
         expectedFrontmost: String, helperPids: [pid_t], guardState: SafetyGuard) {
        self.instrument = instrument
        self.spacer = spacer
        self.deadman = deadman
        self.evidence = evidence
        self.expectedFrontmost = expectedFrontmost
        self.helperPids = helperPids
        self.guardState = guardState
    }

    func now() -> Double {
        Session.clock()
    }

    func setSpacer(_ length: Double?) {
        spacer.set(length)
        deadman.setAtRest(length == nil, at: now())
        evidence.record("spacer.set", context.merging(["length": length ?? -1]) { $1 })
    }

    func pause(_ seconds: Double) {
        Session.spin(seconds)
    }

    func assess(length: Double?) -> Assessment? {
        guard let observation = instrument.observe(spacer: spacer as? Spacer, extraPids: helperPids) else {
            evidence.record("capture.failed", context)
            return nil
        }
        last = observation
        let protected = syntheticProtected ?? observation.markers["P"] ?? .absent
        // The pill's own rule: AX says it is there, pixels say whether it is still
        // drawn. Without this the guard's .pillHidden branch can never fire.
        // `pillAX` is already colour-confirmed, so "in AX but not in pixels" means
        // the pill's own span went dark: something pushed it out from under itself.
        let pill = observation.pillAX.map { item in
            PillReading(
                axPresent: true,
                pixelPresent: instrument.inkCount(observation, span: Span(lo: item.x, hi: item.x + item.w)) >= Self.pillInk
            )
        }
        let reading = CaptureReading(time: observation.time, items: observation.items, protected: protected, pill: pill)
        let decision = guardState.assess(reading, presence: instrument.presence(observation))
        if case .clean = decision {
            deadman.noteClean(at: observation.time)
        }
        let sample = legSample(observation, length: length)
        let assessment = Assessment(
            time: observation.time,
            decision: decision,
            signature: instrument.signature(observation),
            sample: sample,
            frontmostOK: observation.ax.frontmostBundle == expectedFrontmost,
            helpersAlive: helperPids.allSatisfy { kill($0, 0) == 0 },
            pillAXPresent: observation.pillAX != nil
        )
        record(observation, assessment: assessment, length: length)
        return assessment
    }

    // MARK: - Sample construction

    func legSample(_ observation: Observation, length: Double?) -> LegSample {
        let left = spacerLeft(observation)
        return LegSample(
            length: length ?? 0,
            target: targetState(observation),
            spacerLeft: left.value,
            spacerLeftFromAX: left.fromAX,
            spacerAppKitWidth: observation.spacerAppKit.map { Double($0.width) },
            spacerDrawn: spacerDrawn(observation)
        )
    }

    /// The overflow chevron: AX says where a new MenuBarAgent item is, pixels say
    /// whether a glyph is actually drawn there. The template alone is not enough —
    /// the bar is translucent, so the same glyph over a different part of the
    /// wallpaper is a different crop.
    static let chevronInk = 20

    func chevronPresent(_ observation: Observation) -> Bool {
        if case .unique = observation.chevron {
            return true
        }
        return newAgentItems(observation).contains { item in
            instrument.inkCount(observation, span: Span(lo: item.x, hi: item.x + item.w)) >= Self.chevronInk
        }
    }

    func newAgentItems(_ observation: Observation) -> [AXItem] {
        observation.ax.items.filter { $0.bundle == "com.apple.MenuBarAgent" && !restAgentItems.contains(Self.key($0)) }
    }

    static func key(_ item: AXItem) -> String {
        "\(Int(item.x.rounded())):\(Int(item.w.rounded()))"
    }

    private func targetState(_ observation: Observation) -> TargetState {
        switch observation.markers["T"] ?? .absent {
        case .unique(let span):
            return .visible(x: span.mid)
        case .ambiguous:
            return .ambiguous
        case .absent:
            guard chevronPresent(observation), overflowAttributed != false else {
                return .invisibleUnconfirmed
            }
            return .overflowed
        }
    }

    private func spacerLeft(_ observation: Observation) -> (value: Double?, fromAX: Bool) {
        if case .unique(let span) = observation.markers["S.left"] ?? .absent {
            return (span.lo, false)
        }
        return (observation.spacerAXLeft, observation.spacerAXLeft != nil)
    }

    /// Is S still taking room from the bar?
    ///
    /// Its edge markers are only drawn while it is at rest — an expanded spacer
    /// renders nothing, which is what Ice's own does too — so this reads AX: while
    /// S squeezes, its x moves left of where it sits at rest; when it gives the
    /// room back, its x returns to the rest position while its window keeps
    /// growing to the right. nil when neither signal is available.
    var restSpacerX: Double?

    private func spacerDrawn(_ observation: Observation) -> Bool? {
        let markerDrawn = ["S.left", "S.right"].contains { key in
            if case .unique = observation.markers[key] ?? .absent { return true }
            return false
        }
        if markerDrawn {
            return true
        }
        guard let x = observation.spacerAXLeft, let rest = restSpacerX else {
            return nil
        }
        return x < rest - 2
    }

    // MARK: - Evidence

    private func record(_ observation: Observation, assessment: Assessment, length: Double?) {
        var fields = context
        fields["length"] = length ?? -1
        fields["t"] = observation.time
        fields["decision"] = String(describing: assessment.decision)
        fields["markers"] = observation.markers.mapValues(Self.describe)
        fields["chevron"] = Self.describe(observation.chevron)
        fields["target"] = String(describing: assessment.sample.target)
        fields["spacerLeft"] = assessment.sample.spacerLeft ?? -1
        fields["spacerLeftFromAX"] = assessment.sample.spacerLeftFromAX
        fields["spacerAppKit"] = observation.spacerAppKit.map { [$0.minX, $0.width] } ?? []
        fields["spacerAX"] = observation.spacerAXLeft ?? -1
        fields["spacerDrawn"] = assessment.sample.spacerDrawn.map { $0 ? "yes" : "no" } ?? "unknown"
        fields["room"] = instrument.room(observation) ?? -1
        fields["orange"] = observation.orangePixels
        fields["frontmost"] = observation.ax.frontmostBundle
        fields["newAgentItems"] = newAgentItems(observation).map { [$0.x, $0.w] }
        // Our own items as AX reports them, to set against what the pixels show.
        fields["ownAX"] = observation.ax.items.filter { $0.identifier.hasPrefix("IceSpike4") }.map { item -> [String: Any] in
            ["id": item.identifier, "x": item.x, "y": item.y, "w": item.w]
        }
        fields["items"] = observation.items.map { reading -> String in
            switch reading.template {
            case .found(let offset): return "\(reading.id)@\(offset)"
            case .notFound(let mismatch): return "\(reading.id)!\(String(format: "%.3f", mismatch))"
            }
        }
        // Keep a capture when the guard's verdict *changes*, not on every non-clean
        // frame: a noisy stretch at 12 Hz would otherwise copy a ~900 KB PNG twelve
        // times a second until the disk filled.
        let verdict = Self.verdictKind(assessment.decision)
        let mustKeep = verdict == "restore" || verdict == "stop"
        if verdict != "clean", verdict != lastVerdict, mustKeep || keptGuardCaptures < Self.maxGuardCaptures {
            keptGuardCaptures += 1
            fields["capture"] = evidence.keep(observation.frame.file, label: "guard") ?? "?"
        } else if verdict != "clean" {
            fields["captureSkipped"] = true
        }
        lastVerdict = verdict
        evidence.record("assess", fields)
    }

    static func describe(_ result: MarkerResult) -> String {
        switch result {
        case .absent: return "absent"
        case .unique(let span): return String(format: "%.1f-%.1f", span.lo, span.hi)
        case .ambiguous(let spans): return "ambiguous(\(spans.count))"
        }
    }
}
