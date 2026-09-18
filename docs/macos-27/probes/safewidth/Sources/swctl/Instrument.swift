// One capture's worth of facts: our markers, the overflow chevron, every user
// item's template match, S's frames, the frontmost app. Pixels decide; AX is
// recorded beside them to explain mechanisms and to be checked against pixels.
import AppKit
import SafeWidthCore

struct Observation {
    let time: Double
    let frame: StripCapture.Frame
    let ax: AXSnapshot
    /// "T", "P", "S.left", "S.right", or probe names in O0.
    let markers: [String: MarkerResult]
    let chevron: MarkerResult
    let items: [ItemReading]
    let spacerAppKit: CGRect?
    let spacerAXLeft: Double?
    let orangePixels: Int
    /// The microphone pill as AX sees it, when it is there at all.
    let pillAX: AXItem?
}

final class Instrument {
    static let templateRadius = 40.0
    /// The same channel tolerance calibration used to call an item static; if the
    /// two drifted apart, items classified offline would read as lost live.
    static let templateTolerance = Calibrate.templateTolerance
    static let templateMismatch = 0.05
    static let chevronMismatch = 0.06
    static let orange = ColorMatch(center: RGBA(255, 149, 0), tolerance: 70)
    /// Orange pixels inside one item's own span that make it the microphone pill.
    static let pillOrange = 40
    static let rightOfNotch = Span(lo: 956.5, hi: 1728)

    let capture: StripCapture
    private(set) var baselines: [UserItemBaseline]
    let markerSpecs: [String: MarkerSpec]
    private(set) var chevronTemplate: ItemTemplate?
    private let userSpans: [Span]
    let presenceMinimum: [String: Int]
    let ink: ColorMatch
    let axPids: Set<pid_t>

    init(capture: StripCapture, baselines: [UserItemBaseline], presenceMinimum: [String: Int], ink: ColorMatch, markerSpecs: [String: MarkerSpec], axPids: Set<pid_t> = []) {
        self.axPids = axPids
        self.capture = capture
        self.baselines = baselines
        self.presenceMinimum = presenceMinimum
        self.ink = ink
        self.markerSpecs = markerSpecs
        userSpans = baselines.map(\.span)
    }

    /// An item whose look changed in place is no longer checked by its template.
    func reclassifyDynamic(_ id: String) {
        guard let index = baselines.firstIndex(where: { $0.id == id }) else {
            return
        }
        baselines[index].kind = .dynamic
    }

    func setChevronTemplate(_ template: ItemTemplate) {
        chevronTemplate = template
    }

    func observe(spacer: Spacer?, extraPids: [pid_t]) -> Observation? {
        let clock = Session.clock
        guard let frame = capture.capture(clock: clock) else {
            return nil
        }
        let ax = AXReader.snapshot(extraPids: extraPids, only: axPids.isEmpty ? nil : axPids.union(extraPids), menus: false)
        let bitmap = frame.bitmap
        let markers = markerSpecs.mapValues { Pixels.findMarker($0, in: bitmap, excluding: userSpans) }
        let items = baselines.map { baseline in
            ItemReading(id: baseline.id, template: Self.locate(baseline.template, in: bitmap))
        }
        let spacerAX = ax.items.first { $0.identifier == Spacer.identifier }
        let ours = Set(ax.items.filter { $0.identifier.hasPrefix("IceSpike4") }.map(\.pid))
        // The overflow chevron is also a MenuBarAgent item left of every
        // third-party item, so position alone cannot tell the two apart: require
        // the pill's own colour inside its own span.
        let pillAX = AXReader.pillLike(ax, ignoring: ours).flatMap { candidate -> AXItem? in
            let span = Span(lo: candidate.x, hi: candidate.x + candidate.w)
            return Pixels.count(Self.orange, in: bitmap, span: span) >= Self.pillOrange ? candidate : nil
        }
        return Observation(
            time: frame.finished,
            frame: frame,
            ax: ax,
            markers: markers,
            chevron: findChevron(in: bitmap),
            items: items,
            spacerAppKit: spacer?.appKitFrame,
            spacerAXLeft: spacerAX?.x,
            orangePixels: Pixels.count(Self.orange, in: bitmap, span: Self.rightOfNotch),
            pillAX: pillAX
        )
    }

    /// Most captures have every user item exactly where it was, so try that offset
    /// alone first: the full search is 300 times the work and is only needed when
    /// something actually moved.
    static func locate(_ template: ItemTemplate, in bitmap: Bitmap) -> TemplateResult {
        let atZero = Pixels.locate(template, in: bitmap, searchRadius: 0, channelTolerance: templateTolerance, maxMismatch: templateMismatch)
        if case .found = atZero {
            return atZero
        }
        return Pixels.locate(template, in: bitmap, searchRadius: templateRadius, channelTolerance: templateTolerance, maxMismatch: templateMismatch)
    }

    /// The chevron, once a template has been cut and validated: the best match
    /// anywhere on the strip outside user items, if it is good enough.
    private func findChevron(in bitmap: Bitmap) -> MarkerResult {
        guard let template = chevronTemplate else {
            return .absent
        }
        let widthPt = Double(template.bitmap.width) / bitmap.scale
        let result = Pixels.locate(template, in: bitmap, searchRadius: 1728, channelTolerance: Self.templateTolerance, maxMismatch: Self.chevronMismatch)
        guard case .found(let offset) = result else {
            return .absent
        }
        let span = Span(lo: template.originX + offset, hi: template.originX + offset + widthPt)
        return userSpans.contains { $0.contains(span.mid) } ? .absent : .unique(span)
    }

    /// Ink pixels inside a span of this capture: what a drawn glyph leaves behind.
    func inkCount(_ observation: Observation, span: Span) -> Int {
        Pixels.count(ink, in: observation.frame.bitmap, span: span)
    }

    /// Presence of a user item's icon colour in a span of this capture.
    func presence(_ observation: Observation) -> (String, Span) -> Bool {
        let bitmap = observation.frame.bitmap
        let minimum = presenceMinimum
        let ink = ink
        return { id, span in
            Pixels.count(ink, in: bitmap, span: span) >= (minimum[id] ?? 1)
        }
    }

    /// Leftmost user item's current left edge, from its template when found.
    func room(_ observation: Observation) -> Double? {
        guard let first = baselines.first, let reading = observation.items.first else {
            return nil
        }
        if case .found(let offset) = reading.template {
            return first.template.originX + offset
        }
        return nil
    }

    func signature(_ observation: Observation) -> Signature {
        var markers = observation.markers
        markers["chevron"] = observation.chevron
        var offsets: [String: Double?] = [:]
        for (baseline, reading) in zip(baselines, observation.items) where baseline.kind == .static {
            if case .found(let offset) = reading.template {
                offsets[baseline.id] = offset
            } else {
                offsets[baseline.id] = .some(nil)
            }
        }
        return Signature(markers: markers, itemOffsets: offsets)
    }
}

/// Exits the process if no guard-clean capture has completed for too long while
/// the spacer is expanded. S dies with the process; helpers follow through their
/// watch on this pid.
final class DeadmanThread {
    private let lock = NSLock()
    private var deadman: Deadman
    private var atRest = true
    private let evidence: Evidence

    init(limit: Double, evidence: Evidence) {
        deadman = Deadman(limit: limit, start: Session.clock())
        self.evidence = evidence
    }

    func start() {
        let thread = Thread { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: 0.25)
                guard let self else {
                    return
                }
                self.lock.lock()
                let expired = self.deadman.expired(at: Session.clock(), spacerAtRest: self.atRest)
                self.lock.unlock()
                if expired {
                    self.evidence.record("deadman.fired", [:])
                    FileHandle.standardError.write(Data("swctl: DEADMAN fired, exiting so the spacer disappears\n".utf8))
                    exit(3)
                }
            }
        }
        thread.start()
    }

    func noteClean(at time: Double) {
        lock.lock()
        deadman.noteClean(at: time)
        lock.unlock()
    }

    func setAtRest(_ value: Bool, at time: Double) {
        lock.lock()
        if value == false && atRest {
            // Leaving rest restarts the clock: the next clean capture is due from now.
            deadman.noteClean(at: time)
        }
        atRest = value
        lock.unlock()
    }
}
