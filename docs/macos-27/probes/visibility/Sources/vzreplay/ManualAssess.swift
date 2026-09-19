import Foundation
import IceCore

/// Drives IceCore's public primitives directly for `target`/`protected`,
/// instead of `StripAssessor.baseline`/`observe`.
///
/// Why: plan 3.1 says replay ink is "the calibrated ink plus the recorded
/// helpers' marker colours, because probes/safewidth's target was drawn in
/// markers, not in ink" — confirmed empirically here (searching the recorded
/// bar's white/black ink at the target's own AX frame finds nothing; the
/// helper items are drawn in swctl's two-colour markers instead, T =
/// `Palette.pairs["T"]`, P = `Palette.pairs["P"]`, both from the b0
/// calibration's `unusedColours`, which is the same for every run in this
/// evidence set — `docs/macos-27/probes/safewidth/Sources/swctl/Experiment.swift`
/// `Palette.init`). But `StripAssessor.baseline`/`observe` compute `Ink`
/// internally (`Ink.calibrated`, called with no hook to add colours) and take
/// no `Ink` parameter — there is no public way to hand them a combined ink.
///
/// So this file recomposes the same public rules `StripAssessor` itself calls
/// — `Ink.calibrated`/`.adding`, `ItemTemplate.cut`, `TemplateMatcher.match`,
/// `CaptureStability.isStable`, `FoldWitness.derive`, `Placement.assess` — all
/// `public` in IceCore, and finishes with a `StripReading` built through its
/// own public initialiser. Nothing here reimplements a *rule*; it reimplements
/// the *composition* `StripAssessor` does not expose an ink hook for. See the
/// final report's "risks" section: this gap is itself a T9 finding.
enum ManualAssess {
    /// swctl's own marker tolerance
    /// (`docs/macos-27/probes/safewidth/Sources/swctl/Calibration.swift:39`).
    static let markerTolerance = 48

    /// `Palette.pairs["T"]` / `["P"]`, from the b0 calibration's
    /// `unusedColours` (`0000FF, FF00FF, 00FFFF, FF0000, ...`), the same list
    /// every run in this evidence set was launched with
    /// (`--calibration .../20260918-190735-b0/calibration.json`).
    static let targetColours = (left: RGBA(0x00, 0x00, 0xFF), right: RGBA(0xFF, 0x00, 0xFF))
    static let protectedColours = (left: RGBA(0x00, 0xFF, 0xFF), right: RGBA(0xFF, 0x00, 0x00))

    struct Baseline {
        let ink: Ink
        let templates: [String: ItemTemplate]
        let agentFrames: [AgentFrame]
        let foldAtBaseline: Fold
        let geometry: BarGeometry
        let rejected: [String: String]
    }

    static func combinedInk(reference: StripImage, geometry: BarGeometry, glyphFrames: [PtSpan], parameters: DetectorParameters) throws -> Ink {
        guard let base = Ink.calibrated(from: reference, geometry: geometry, glyphFrames: glyphFrames, parameters: parameters) else {
            throw ReplayError.reconstructionFailed("ink calibration failed (median in the ambiguous band and the glyph tie-break did not resolve)")
        }
        return base
            .adding(ColorMatch(center: targetColours.left, tolerance: markerTolerance))
            .adding(ColorMatch(center: targetColours.right, tolerance: markerTolerance))
            .adding(ColorMatch(center: protectedColours.left, tolerance: markerTolerance))
            .adding(ColorMatch(center: protectedColours.right, tolerance: markerTolerance))
    }

    /// Cuts and accepts `target`/`protected` from the kept baseline samples:
    /// fold absent throughout, each template unique at its own x and stable
    /// (matches within tolerance) across every kept capture. A narrower replay
    /// of plan 3.2's rules 1/5/6 — rules 2-4 are enforced by `ItemTemplate.cut`
    /// itself, which this calls unchanged.
    static func buildBaseline(
        samples: [ObservationSample],
        glyphFrames: [PtSpan],
        geometry: BarGeometry,
        parameters: DetectorParameters = .preRegistered
    ) throws -> Baseline {
        let ordered = samples.sorted { $0.time < $1.time }
        guard ordered.count >= parameters.baselineMinSamples,
              let first = ordered.first, let last = ordered.last,
              last.time - first.time >= parameters.baselineMinSpan
        else {
            throw ReplayError.reconstructionFailed("baseline samples too few or too short a span")
        }
        let kept = Array(ordered.dropFirst(parameters.baselineDroppedSamples))
        guard let reference = kept.first?.before else {
            throw ReplayError.reconstructionFailed("no reference capture")
        }
        let ink = try combinedInk(reference: reference, geometry: geometry, glyphFrames: glyphFrames, parameters: parameters)
        let maps = kept.flatMap { [ink.map($0.before), ink.map($0.after)] }

        let agentFrames = kept.last?.agentFrames ?? []
        // Plan 3.5/StripAssessor.baseline: the fold region runs from the
        // notch's right edge to the leftmost item read, and — since no
        // template exists yet at baseline — every item's own frame counts as
        // "explained" ink, not just the references'.
        let leftmostX = kept.flatMap { $0.itemFrames.values.map(\.minX) }.min()
        let region = PtSpan(lo: geometry.notch?.hi ?? 0, hi: max(geometry.notch?.hi ?? 0, leftmostX ?? geometry.widthPt))
        let readSpans = kept.flatMap { $0.itemFrames.values.map(\.span) }
        let foldSamples = kept.map { sample in
            FoldSample(time: sample.time, before: ink.map(sample.before), after: ink.map(sample.after), agentFrames: sample.agentFrames, referencesStable: true, explained: readSpans)
        }
        let foldAtBaseline = FoldWitness.derive(samples: foldSamples, baselineFrames: nil, region: region, geometry: geometry, parameters: parameters)
        guard foldAtBaseline == .absent else {
            return Baseline(ink: ink, templates: [:], agentFrames: agentFrames, foldAtBaseline: foldAtBaseline, geometry: geometry, rejected: ["*": "foldNotAbsentAtBaseline"])
        }

        var templates: [String: ItemTemplate] = [:]
        var rejected: [String: String] = [:]
        let frameSets = kept.map(\.itemFrames)
        let ids = Set(frameSets.flatMap(\.keys))
        for id in ids {
            guard let frame = frameSets.first?[id], frameSets.allSatisfy({ $0[id] == frame }) else {
                rejected[id] = "readsDisagree (or missing in some kept sample)"
                continue
            }
            let cut = ItemTemplate.cut(frame, from: reference, ink: ink, geometry: geometry, parameters: parameters)
            guard let template = cut.template else {
                rejected[id] = "\(cut.rejection.map(String.init(describing:)) ?? "noTemplate")"
                continue
            }
            var consistent = true
            for map in maps {
                guard case .unique(let x, let mismatch) = TemplateMatcher.match(template, in: map, geometry: geometry, parameters: parameters),
                      abs(x - template.originXPt) <= parameters.sightingTolerancePt, mismatch <= parameters.maxMismatch
                else {
                    consistent = false
                    break
                }
            }
            guard consistent else {
                rejected[id] = "notUniqueAtBaseline (or moved/mismatched across kept captures)"
                continue
            }
            templates[id] = template
        }
        return Baseline(ink: ink, templates: templates, agentFrames: agentFrames, foldAtBaseline: foldAtBaseline, geometry: geometry, rejected: rejected)
    }

    /// The observation half: matches `targets + references` in every sample,
    /// derives stability and the fold, and returns a `StripReading` built
    /// through its own public initialiser — the same shape
    /// `StripAssessor.observe` returns, composed by hand because the ink is
    /// not what `StripAssessor` would have calibrated on its own.
    static func observe(
        baseline: Baseline,
        targets: [String],
        references: [String],
        samples: [ObservationSample],
        parameters: DetectorParameters = .preRegistered
    ) -> StripReading {
        guard samples.count >= parameters.minSamples else {
            return StripReading(sightings: [], fold: .unreadable, foldAtBaseline: baseline.foldAtBaseline, captureStable: false)
        }
        let ordered = samples.sorted { $0.time < $1.time }
        for (previous, next) in zip(ordered, ordered.dropFirst()) where next.time - previous.time < parameters.minSampleSpacing {
            return StripReading(sightings: [], fold: .unreadable, foldAtBaseline: baseline.foldAtBaseline, captureStable: false)
        }

        let wanted = Array(Set(targets + references)).sorted()
        var matchesByCapture: [[String: Match]] = []
        var mapsBySample: [(before: InkMap, after: InkMap)] = []
        for sample in ordered {
            let before = baseline.ink.map(sample.before)
            let after = baseline.ink.map(sample.after)
            mapsBySample.append((before, after))
            for map in [before, after] {
                var matches: [String: Match] = [:]
                for id in wanted {
                    guard let template = baseline.templates[id] else { continue }
                    matches[id] = TemplateMatcher.match(template, in: map, geometry: baseline.geometry, parameters: parameters)
                }
                matchesByCapture.append(matches)
            }
        }

        let referencesStable = CaptureStability.isStable(references: references, templates: baseline.templates, captures: matchesByCapture, parameters: parameters)
        let captureStable = referencesStable && StripAssessor.settled(targets, in: matchesByCapture, parameters: parameters)

        // StripAssessor.observe: the region runs to the leftmost *reference*
        // template's x, not the whole bar.
        let notchHi = baseline.geometry.notch?.hi ?? 0
        let referenceLeftmost = references.compactMap { baseline.templates[$0]?.originXPt }.min()
        let region = PtSpan(lo: notchHi, hi: max(notchHi, referenceLeftmost ?? baseline.geometry.widthPt))
        let foldSamples = ordered.enumerated().map { index, sample -> FoldSample in
            let explained = wanted.compactMap { id -> PtSpan? in
                guard let template = baseline.templates[id], case .unique(let x, _)? = matchesByCapture[index * 2 + 1][id] else { return nil }
                return PtSpan(lo: x, hi: x + template.widthPt)
            }
            let stable = CaptureStability.isStable(references: references, templates: baseline.templates, captures: [matchesByCapture[index * 2], matchesByCapture[index * 2 + 1]], parameters: parameters)
            return FoldSample(time: sample.time, before: mapsBySample[index].before, after: mapsBySample[index].after, agentFrames: sample.agentFrames, referencesStable: stable, explained: explained)
        }
        let fold = FoldWitness.derive(samples: foldSamples, baselineFrames: baseline.agentFrames, region: region, geometry: baseline.geometry, parameters: parameters)

        guard let lastSample = ordered.last else {
            return StripReading(sightings: [], fold: fold, foldAtBaseline: baseline.foldAtBaseline, captureStable: captureStable)
        }
        let lastMatches = matchesByCapture[matchesByCapture.count - 1]
        let sightings: [ItemSighting] = wanted.compactMap { id in
            guard let template = baseline.templates[id], let match = lastMatches[id] else { return nil }
            let placement: Placement
            if case .unique(let x, _) = match {
                placement = Placement.assess(frame: lastSample.itemFrames[id], matchX: x, matchWidthPt: template.widthPt, geometry: baseline.geometry, parameters: parameters)
            } else {
                placement = .unavailable
            }
            return ItemSighting(id: id, appearance: .asBaselined, match: match, placement: placement)
        }
        return StripReading(sightings: sightings, fold: fold, foldAtBaseline: baseline.foldAtBaseline, captureStable: captureStable)
    }

}
