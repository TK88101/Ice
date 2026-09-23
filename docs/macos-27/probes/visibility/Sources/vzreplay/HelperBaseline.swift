import Foundation
import IceCore

/// One reconstructed input to `ManualAssess.buildBaseline`/`observe`, plus how
/// far its Accessibility facts were borrowed from in time — reported so a
/// large gap is visible rather than silently trusted.
struct SampleDiagnostic {
    let label: String
    let wallSeconds: Double
    let axGapSeconds: Double
}

/// A baseline built through `ManualAssess` (the marker-ink pipeline), plus its
/// reconstruction diagnostics.
struct HelperBuiltBaseline {
    let result: ManualAssess.Baseline
    let diagnostics: [SampleDiagnostic]
}

/// Builds the `target` / `protected` baseline: swctl's helper items,
/// `com.icespike4.target` and `com.icespike4.protected`, cut from the run's own
/// rest-state captures once they exist (plan section 0: "at a settled baseline
/// taken just before the action").
///
/// This goes through `ManualAssess`, not `StripAssessor.baseline`: the helper
/// items are drawn in swctl's two-colour markers, not the bar's calibrated
/// ink (see `ManualAssess`'s header), and `StripAssessor` has no hook to add
/// colours to the ink it calibrates internally.
///
/// Reconstruction limits, stated once here rather than at every call site:
/// - `rest.check` captures are single frames; a bracket wants a
///   capture-AX-capture pair. `before` and `after` are the same decoded
///   image, so the cross-capture check *inside* one sample is trivially
///   satisfied rather than genuinely exercised there — the cross-*sample*
///   checks (position agreement across the four kept samples) are still real,
///   because the four rest checks are four distinct real captures.
/// - Accessibility frames come from the nearest `assess` record in wall time,
///   not from the `rest.check` record itself (which carries marker spans, not
///   AX frames). The gap is recorded per sample.
enum HelperBaseline {
    /// Real static icons, only to give ink calibration's white/black tie-break
    /// (deviation 1: this bar's median luma sits inside the ambiguous band)
    /// something to count. Not part of the target/protected pair itself.
    static let glyphItemIDs = ["com.google.Chrome#0", "com.openai.codex#0"]

    static func build(_ context: RunContext, parameters: DetectorParameters = .preRegistered) throws -> HelperBuiltBaseline {
        let restChecks = context.run.records(kind: "rest.check").filter { ($0["ok"] as? Bool) == true && $0.capture != nil }
        guard !restChecks.isEmpty else {
            throw ReplayError.reconstructionFailed("\(context.run.runId): no clean rest.check capture to baseline from")
        }
        let swctlBaseline = try context.run.swctlBaseline()
        let glyphFrames = try glyphItemIDs.map { try Frames.userItemFrame(id: $0, in: swctlBaseline).span }

        var samples: [ObservationSample] = []
        var diagnostics: [SampleDiagnostic] = []
        for record in restChecks {
            guard let capture = record.capture, let wall = record.wall else { continue }
            let time = try WallClock.seconds(wall)
            let (assess, gap) = try context.run.nearestAssess(to: time)
            let ax = try Frames.ownAX(assess)
            guard let target = ax["target"], let protected = ax["protected"] else {
                // The helper does not exist yet at this rest check (still swctl's
                // own pre-launch settling); skip it rather than fabricate a frame.
                continue
            }
            let image = try context.decode(capture)
            let agentFrames = context.agentBaseline + (try Frames.newAgentItems(assess))
            samples.append(ObservationSample(
                time: time,
                before: image,
                after: image,
                agentFrames: agentFrames,
                itemFrames: ["target": target, "protected": protected]
            ))
            diagnostics.append(SampleDiagnostic(label: capture, wallSeconds: time, axGapSeconds: gap))
            if samples.count >= 8 { break }
        }

        guard samples.count >= parameters.baselineMinSamples else {
            throw ReplayError.reconstructionFailed(
                "\(context.run.runId): only \(samples.count) usable rest-check samples with both helpers present (need \(parameters.baselineMinSamples))"
            )
        }
        let span = (samples.map(\.time).max() ?? 0) - (samples.map(\.time).min() ?? 0)
        guard span >= parameters.baselineMinSpan else {
            throw ReplayError.reconstructionFailed(
                "\(context.run.runId): usable rest-check samples span only \(span)s (need \(parameters.baselineMinSpan)s)"
            )
        }

        let result = try ManualAssess.buildBaseline(samples: samples, glyphFrames: glyphFrames, geometry: context.geometry, parameters: parameters)
        return HelperBuiltBaseline(result: result, diagnostics: diagnostics)
    }
}
