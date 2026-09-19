import Foundation
import IceCore

/// A secondary reconstruction, used only for the fold-present check on
/// `204150-m-mid`.
///
/// The plan's own reference for the fold bracket is `protected` (3.4), but
/// `protected` cannot be cut as an IceCore template at all here — see
/// `ManualAssess`'s header and the final report's primary finding: a
/// two-colour edge marker is nearly 100% "ink" by construction, so
/// `ItemTemplate.cut`'s core-background-minimum invariant (3.0/3.2 rule 4)
/// rejects it unconditionally, for any adapter, not just this one. Since
/// `FoldWitness` still needs *some* stable reference to gate a verdict at all
/// (`FoldSample.referencesStable`), this path substitutes two real, ordinary
/// static icons already on the bar (`com.google.Chrome#0`,
/// `com.openai.codex#0`) — a deviation from 3.4's letter ("our own static
/// items only"), made only because the prescribed reference is uncuttable,
/// and reported as such. It exercises the same `FoldWitness` rule
/// (`StripAssessor.baseline`/`observe`, plain calibrated ink, no markers) on
/// the same real captures and real 17.5 pt `newAgentItems` evidence.
///
/// The spacer (`IceSpike4-spacer`) is also tracked, per-sample, from `ownAX`:
/// at rest it renders a plain body (real, plain-ink pixels, unlike target/
/// protected's saturated markers, which this run's calibrated white/black ink
/// never matches). Left untracked, its ink sits inside the fold region
/// (between the notch and `com.google.Chrome#0`) unexplained, and the
/// baseline never gets past `foldNotAbsentAtBaseline` — see `AmbientBaseline`'s
/// header for the general shape of this problem.
enum FoldOnlyBaseline {
    static let referenceIDs = ["com.google.Chrome#0", "com.openai.codex#0"]

    static func build(_ context: RunContext, parameters: DetectorParameters = .preRegistered) throws -> BuiltBaseline {
        let restChecks = context.run.records(kind: "rest.check").filter { ($0["ok"] as? Bool) == true && $0.capture != nil }
        guard !restChecks.isEmpty else {
            throw ReplayError.reconstructionFailed("\(context.run.runId): no clean rest.check capture to baseline from")
        }
        let swctlBaseline = try context.run.swctlBaseline()
        var staticFrames: [String: ItemFrame] = [:]
        for id in referenceIDs {
            staticFrames[id] = try Frames.userItemFrame(id: id, in: swctlBaseline)
        }

        var samples: [ObservationSample] = []
        var diagnostics: [SampleDiagnostic] = []
        for record in restChecks {
            guard let capture = record.capture, let wall = record.wall else { continue }
            let time = try WallClock.seconds(wall)
            let (assess, gap) = try context.run.nearestAssess(to: time)
            let image = try context.decode(capture)
            let agentFrames = context.agentBaseline + (try Frames.newAgentItems(assess))
            var itemFrames = staticFrames
            if let spacer = try Frames.ownAX(assess)["spacer"] { itemFrames["spacer"] = spacer }
            samples.append(ObservationSample(time: time, before: image, after: image, agentFrames: agentFrames, itemFrames: itemFrames))
            diagnostics.append(SampleDiagnostic(label: capture, wallSeconds: time, axGapSeconds: gap))
            if samples.count >= 8 { break }
        }
        guard samples.count >= parameters.baselineMinSamples else {
            throw ReplayError.reconstructionFailed("\(context.run.runId): only \(samples.count) usable rest-check samples")
        }

        let result = StripAssessor.baseline(samples: samples, geometry: context.geometry, parameters: parameters)
        return BuiltBaseline(result: result, diagnostics: diagnostics)
    }
}
