import Foundation
import IceCore

struct ReplayResult {
    let entry: LabelEntry
    let iceCoreSaid: String
    let agree: Bool
    let diagnosis: String
}

/// Runs each label's own recipe through `StripAssessor`/`MenuBarItemVisibility`
/// and compares the result with the frozen expectation. This file is the only
/// one that calls into IceCore; `Cases.swift` never does.
enum Replay {
    /// Items our own bracket cares about — everything else in `ownAX` (the
    /// spacer) plays no role in the decision layer.
    private static let helperIDs: Set<String> = ["target", "protected"]

    static func run(_ run: RunEvidence, entries: [LabelEntry]) throws -> [ReplayResult] {
        let context = try RunContext(run: run)
        var helperBaseline: HelperBuiltBaseline?
        var results: [ReplayResult] = []

        var foldBaseline: BuiltBaseline?
        for entry in entries {
            switch entry.kind {
            case "targetDrawn", "targetNotDrawn":
                if helperBaseline == nil { helperBaseline = try HelperBaseline.build(context) }
                results.append(try replayHelperCapture(context, baseline: helperBaseline!, entry: entry))
            case "foldPresent":
                if foldBaseline == nil { foldBaseline = try FoldOnlyBaseline.build(context) }
                results.append(try replayFoldPresent(context, baseline: foldBaseline!, entry: entry))
            case "unstable":
                if helperBaseline == nil { helperBaseline = try HelperBaseline.build(context) }
                results.append(try replayInstability(context, baseline: helperBaseline!, entry: entry))
            case "foldAtBaselineAbsent":
                results.append(try replayFoldAtBaseline(context, entry: entry))
            case "notAbsent":
                results.append(try replayNotAbsent(context, entry: entry))
            default:
                throw ReplayError.unknownCase("\(entry.id): unhandled kind '\(entry.kind)'")
            }
        }
        return results
    }

    // MARK: - target visible / overflowed
    //
    // `target` is drawn purely as a two-colour edge marker (swctl's
    // `MarkerSpec`), with no separate icon: its ink bounding box is nearly
    // 100% "ink" by construction, so `ItemTemplate.cut`'s core-background
    // invariant (3.0/3.2 rule 4) rejects it as `.tooLittleBackground` no
    // matter what adapter drives it — the invariant has no override, and
    // `ItemTemplate.cut` is the only way to obtain an `ItemTemplate` at all.
    // This is expected to disagree; see the final report's primary finding.

    private static func replayHelperCapture(_ context: RunContext, baseline: HelperBuiltBaseline, entry: LabelEntry) throws -> ReplayResult {
        guard let capture = entry.captures.first else {
            throw ReplayError.reconstructionFailed("\(entry.id): no capture recorded")
        }
        let facts = try axFacts(context.run, capture: capture)
        let image = try context.decode(capture)
        let itemFrames = facts.ownAX.filter { helperIDs.contains($0.key) }
        let agentFrames = context.agentBaseline + facts.newAgentItems
        // One real capture, duplicated at a synthetic 0.31 s gap: the API
        // requires >= 2 samples >= 0.3 s apart, and there is only one real
        // frame for this instant. See HelperBaseline's header for the same
        // limit applied to the baseline itself.
        let samples = [
            ObservationSample(time: facts.wallSeconds, before: image, after: image, agentFrames: agentFrames, itemFrames: itemFrames),
            ObservationSample(time: facts.wallSeconds + 0.31, before: image, after: image, agentFrames: agentFrames, itemFrames: itemFrames),
        ]
        let reading = ManualAssess.observe(baseline: baseline.result, targets: ["target"], references: ["protected"], samples: samples, parameters: .preRegistered)
        let detector = MenuBarItemVisibility(maxMismatch: DetectorParameters.preRegistered.maxMismatch)

        guard let sighting = reading.sightings.first(where: { $0.id == "target" }) else {
            return ReplayResult(entry: entry, iceCoreSaid: "notObserved (no sighting at all)", agree: false,
                                 diagnosis: "target has no template (baseline rejections: \(baseline.result.rejected)) — "
                                     + "a two-colour marker's ink bounding box has almost no interior background pixels, "
                                     + "so ItemTemplate.cut's core-background-minimum invariant rejects it unconditionally; "
                                     + "this is not fixable from the adapter side, see the report's primary finding")
        }
        let verdict = detector.verdict(for: sighting, captureStable: reading.captureStable)
        let said = describe(verdict)
        let agree: Bool
        switch entry.kind {
        case "targetDrawn":
            if case .drawn(let x) = verdict, let expectedX = Cases.parseDrawnExpectation(entry.expected) {
                // Two independent measurements of the same edge (a
                // two-colour marker vs. an ink template) are not expected
                // to agree to the pixel; 5 pt is a generous sanity bound,
                // not a tuned tolerance.
                agree = abs(x - expectedX) <= 5
            } else {
                agree = false
            }
        default: // targetNotDrawn
            agree = verdict == .notDrawn
        }
        return ReplayResult(entry: entry, iceCoreSaid: said, agree: agree, diagnosis: diagnosis(agree: agree, said: said, match: sighting.match, appearance: sighting.appearance, placement: sighting.placement, captureStable: reading.captureStable))
    }

    // MARK: - the fold witness's own case (chevron 17.5 pt in AX)

    private static func replayFoldPresent(_ context: RunContext, baseline: BuiltBaseline, entry: LabelEntry) throws -> ReplayResult {
        guard let capture = entry.captures.first else {
            throw ReplayError.reconstructionFailed("\(entry.id): no capture recorded")
        }
        let facts = try axFacts(context.run, capture: capture)
        let image = try context.decode(capture)
        let agentFrames = context.agentBaseline + facts.newAgentItems
        let samples = [
            ObservationSample(time: facts.wallSeconds, before: image, after: image, agentFrames: agentFrames, itemFrames: [:]),
            ObservationSample(time: facts.wallSeconds + 0.31, before: image, after: image, agentFrames: agentFrames, itemFrames: [:]),
        ]
        let reading = StripAssessor.observe(baseline: baseline.result, targets: [], references: FoldOnlyBaseline.referenceIDs, samples: samples, parameters: .preRegistered)
        let said = describe(reading.fold)
        return ReplayResult(entry: entry, iceCoreSaid: said, agree: reading.fold == .present,
                             diagnosis: reading.fold == .present ? "agrees" : "fold read as \(said); captureStable=\(reading.captureStable); reference rejections: \(baseline.result.rejections)")
    }

    // MARK: - the Space slide

    private static func replayInstability(_ context: RunContext, baseline: HelperBuiltBaseline, entry: LabelEntry) throws -> ReplayResult {
        guard entry.captures.count == 2 else {
            throw ReplayError.reconstructionFailed("\(entry.id): expected exactly 2 captures")
        }
        var samples: [ObservationSample] = []
        for capture in entry.captures {
            let facts = try axFacts(context.run, capture: capture)
            let image = try context.decode(capture)
            let itemFrames = facts.ownAX.filter { helperIDs.contains($0.key) }
            samples.append(ObservationSample(
                time: facts.wallSeconds,
                before: image,
                after: image,
                agentFrames: context.agentBaseline + facts.newAgentItems,
                itemFrames: itemFrames
            ))
        }
        let reading = ManualAssess.observe(baseline: baseline.result, targets: ["target"], references: ["protected"], samples: samples, parameters: .preRegistered)
        let said = reading.captureStable ? "stable (a verdict was reached)" : "unstable (captureStable=false, fold=\(describe(reading.fold)))"
        return ReplayResult(entry: entry, iceCoreSaid: said, agree: !reading.captureStable,
                             diagnosis: !reading.captureStable ? "agrees; gap between the two real captures was \(samples[1].time - samples[0].time)s" : "IceCore reached a verdict despite the slide — investigate")
    }

    // MARK: - the pill at baseline

    private static func replayFoldAtBaseline(_ context: RunContext, entry: LabelEntry) throws -> ReplayResult {
        let baseline = try AmbientBaseline.build(context, itemIDs: Cases.pillBaselineOtherItems)
        let said = describe(baseline.result.foldAtBaseline)
        return ReplayResult(entry: entry, iceCoreSaid: said, agree: baseline.result.foldAtBaseline == .absent,
                             diagnosis: baseline.result.foldAtBaseline == .absent
                                 ? "agrees; \(baseline.result.acceptedIDs.count) items accepted (\(baseline.result.acceptedIDs.joined(separator: ", ")))"
                                 : "rejections: \(baseline.result.rejections)")
    }

    // MARK: - the Teams badge

    private static func replayNotAbsent(_ context: RunContext, entry: LabelEntry) throws -> ReplayResult {
        guard entry.captures.count == 2, let teardownCapture = entry.captures.last else {
            throw ReplayError.reconstructionFailed("\(entry.id): expected [baseline capture, teardown capture]")
        }
        let itemID = "com.microsoft.teams2#0"
        let baseline = try AmbientBaseline.build(context, itemIDs: [itemID])
        guard baseline.result.templates[itemID] != nil else {
            return ReplayResult(entry: entry, iceCoreSaid: "rejected at baseline: \(baseline.result.rejections[itemID].map(String.init(describing:)) ?? "?")",
                                 agree: false, diagnosis: "Teams never got a template, so the case cannot be exercised; rejections: \(baseline.result.rejections)")
        }
        let image = try context.decode(teardownCapture)
        let samples = [
            ObservationSample(time: 0, before: image, after: image, agentFrames: context.agentBaseline, itemFrames: [:]),
            ObservationSample(time: 0.31, before: image, after: image, agentFrames: context.agentBaseline, itemFrames: [:]),
        ]
        let reading = StripAssessor.observe(baseline: baseline.result, targets: [itemID], references: [], samples: samples, parameters: .preRegistered)
        guard let sighting = reading.sightings.first(where: { $0.id == itemID }) else {
            return ReplayResult(entry: entry, iceCoreSaid: "notObserved", agree: false, diagnosis: "no sighting produced for \(itemID)")
        }
        let detector = MenuBarItemVisibility(maxMismatch: DetectorParameters.preRegistered.maxMismatch)
        let verdict = detector.verdict(for: sighting, captureStable: true)
        let said = describe(verdict)
        let agree = verdict != .notDrawn
        // Always shown, not only on disagreement: which mechanism kept this
        // from reading `.notDrawn` is itself part of what T9 is checking (the
        // plan's pre-registered `weakThreshold`, or something else).
        let mechanism = "match=\(sighting.match), appearance=\(sighting.appearance), placement=\(sighting.placement)"
        return ReplayResult(entry: entry, iceCoreSaid: said, agree: agree, diagnosis: "\(agree ? "agrees" : "disagrees"); \(mechanism)")
    }

    // MARK: - AX pairing shared by every case

    struct AXFacts {
        let ownAX: [String: ItemFrame]
        let newAgentItems: [AgentFrame]
        let wallSeconds: Double
        let gap: Double
    }

    /// If `capture` names an `assess` record itself (guard captures), its own
    /// `ownAX`/`newAgentItems` are exact (gap 0). Otherwise (probes,
    /// rest.check, teardown), borrows the nearest `assess` record's, and
    /// reports how far away it was.
    static func axFacts(_ run: RunEvidence, capture: String) throws -> AXFacts {
        if let assess = run.records(kind: "assess").first(where: { $0.capture == capture }), let wall = assess.wall {
            let seconds = try WallClock.seconds(wall)
            return AXFacts(ownAX: try Frames.ownAX(assess), newAgentItems: try Frames.newAgentItems(assess), wallSeconds: seconds, gap: 0)
        }
        guard let holder = run.records.first(where: { $0.capture == capture }), let wall = holder.wall else {
            throw ReplayError.reconstructionFailed("\(run.runId): no record references capture \(capture)")
        }
        let seconds = try WallClock.seconds(wall)
        let (assess, gap) = try run.nearestAssess(to: seconds)
        return AXFacts(ownAX: try Frames.ownAX(assess), newAgentItems: try Frames.newAgentItems(assess), wallSeconds: seconds, gap: gap)
    }

    // MARK: - Description helpers

    static func describe(_ visibility: Visibility) -> String {
        switch visibility {
        case .drawn(let x): "drawn(x: \(x))"
        case .notDrawn: "notDrawn"
        case .unverifiable(let reason): "unverifiable(\(reason))"
        }
    }

    static func describe(_ fold: Fold) -> String {
        switch fold {
        case .present: "present"
        case .absent: "absent"
        case .unreadable: "unreadable"
        }
    }

    private static func diagnosis(agree: Bool, said: String, match: Match, appearance: Appearance, placement: Placement, captureStable: Bool) -> String {
        guard !agree else { return "agrees" }
        return "IceCore said \(said); match=\(match), appearance=\(appearance), placement=\(placement), captureStable=\(captureStable)"
    }
}
