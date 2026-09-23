import Foundation
import IceCore

/// A `StripAssessor.baseline` result, plus its reconstruction diagnostics.
/// Real user items are drawn in the bar's own calibrated ink, so this path
/// goes through `StripAssessor` unchanged — unlike `HelperBuiltBaseline`,
/// which needs `ManualAssess`'s marker-ink recomposition.
struct BuiltBaseline {
    let result: BaselineResult
    let diagnostics: [SampleDiagnostic]
}

/// Builds a baseline for real user items (Teams, the pill's calibration
/// neighbours, ...) from swctl's own pre-helper baseline captures
/// (`NNNNN-baseline.png`, `Experiment.runBaseline`) — these items were already
/// on the bar before any helper existed.
///
/// Every item in the run's `baseline` record is tracked, not only the one(s)
/// the caller cares about: `StripAssessor.baseline`'s fold-region check runs
/// from the notch to the *leftmost tracked item*, and counts every tracked
/// item's own ink as "explained". Tracking only the item under test leaves
/// every real item to its left (an ordinary icon, or `194520-c-mid`/
/// `202302-o1`'s microphone pill) both outside the leftmost boundary — so
/// inside the fold region — and unexplained, and the baseline comes back
/// `foldNotAbsentAtBaseline` for a reason that has nothing to do with the
/// item under test. A rejected extra item (most will reject as
/// `.overlapsAgentItem`, since `com.apple.MenuBarAgent#0..N` are already
/// tracked as `agentFrames`) still keeps its span in `StripAssessor`'s
/// "explained" set — rejection and explanation are independent, by design
/// (`StripAssessor.baseline`'s own comment: "their ink is still theirs").
///
/// Per-capture time comes from the PNG file's own modification time, not a
/// wall field: swctl records only the *aggregate* `baseline` record's wall
/// time, never each of the 8 individual captures'. Filesystem mtimes have only
/// one-second resolution, but that is enough to see the real span (measured:
/// 3-4 s across the 8 captures of every run this tool uses, matching the
/// plan's own citation of swctl's baseline protocol, "8 captures over >= 3 s")
/// — closer to the truth than assuming the nominal 0.4 s spin interval, which
/// alone would only span 2.8 s and undershoot IceCore's pre-registered 3 s
/// `baselineMinSpan`.
enum AmbientBaseline {
    static let captureCount = 8

    static func build(_ context: RunContext, itemIDs: [String], parameters: DetectorParameters = .preRegistered) throws -> BuiltBaseline {
        let names = (1...captureCount).map { String(format: "%05d-baseline.png", $0) }
        let baseline = try context.run.swctlBaseline()
        let allBaselineIDs = try baseline.recordArray("items", context: "baseline").map { try $0.string("id", context: "baseline item") }

        var frames: [String: ItemFrame] = [:]
        for id in Set(itemIDs + allBaselineIDs) {
            frames[id] = try Frames.userItemFrame(id: id, in: baseline)
        }

        var samples: [ObservationSample] = []
        var diagnostics: [SampleDiagnostic] = []
        for name in names {
            let url = context.run.captureURL(name)
            guard let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date else {
                throw ReplayError.reconstructionFailed("\(context.run.runId): no modification time for \(name)")
            }
            let time = modified.timeIntervalSinceReferenceDate
            let image = try context.decode(name)
            samples.append(ObservationSample(
                time: time,
                before: image,
                after: image,
                agentFrames: context.agentBaseline,
                itemFrames: frames
            ))
            diagnostics.append(SampleDiagnostic(label: name, wallSeconds: time, axGapSeconds: 0))
        }

        let result = StripAssessor.baseline(samples: samples, geometry: context.geometry, parameters: parameters)
        return BuiltBaseline(result: result, diagnostics: diagnostics)
    }
}
