// The safety monitor of plan section 6.2: the user's own static items, cut
// once at the pre-flight baseline, searched in every capture with the same
// matcher IceCore uses for our own items. It decides nothing about the
// helpers and gates no verdict -- it only watches for harm to someone
// else's bar.
import IceCore

/// Thrown when the baseline captured no ink -- nothing to build a monitor
/// from at all, which is itself worth aborting on.
enum SafetyMonitorError: Error {
    case noInk
}

final class SafetyMonitor {
    private let templates: [String: ItemTemplate]
    private let ink: Ink
    private let geometry: BarGeometry
    private let parameters: DetectorParameters
    /// Ids that failed to match uniquely at their baseline x on the
    /// *previous* capture. Two consecutive misses of the same id -> stop
    /// (plan 6.2, "not `.unique` at its x for 2 consecutive captures").
    private var previousMisses: Set<String> = []

    init(baseline: BaselineResult, parameters: DetectorParameters) throws {
        guard let ink = baseline.ink else { throw SafetyMonitorError.noInk }
        self.templates = baseline.templates
        self.ink = ink
        self.geometry = baseline.geometry
        self.parameters = parameters
    }

    /// How many static items the monitor is actually watching -- the ones
    /// TemplateBaseline accepted at the pre-flight baseline.
    var watchedCount: Int { templates.count }

    /// Feeds one capture in. Returns the ids that missed this time; the
    /// caller stops the run when `feed(_:)` returns `true`.
    @discardableResult
    func feed(_ capture: StripImage) -> Bool {
        let map = ink.map(capture)
        var misses = Set<String>()
        for (id, template) in templates {
            let match = TemplateMatcher.match(template, in: map, geometry: geometry, parameters: parameters)
            guard case .unique(let x, let mismatch) = match,
                  mismatch <= parameters.maxMismatch,
                  abs(x - template.originXPt) <= parameters.referenceTolerancePt
            else {
                misses.insert(id)
                continue
            }
        }
        let stop = !misses.isDisjoint(with: previousMisses)
        previousMisses = misses
        return stop
    }
}
