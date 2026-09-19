// Plan 6.1 step 5: five cycles of observe / hide / observe / show /
// observe, each against the expected verdict named there.
import Foundation
import IceCore
import MenuBarCapture

extension LiveRun {
    func step5Cycles() -> StepResult {
        guard let target, let reference else { return .abort("helpers not launched") }
        let items: [String: pid_t] = ["target": target.pid, "reference": reference.pid]

        for cycle in 1...5 {
            switch observeChecked(items: items, label: "cycle\(cycle).drawn") {
            case .failure(let reason): return .abort(reason)
            case .success(let result):
                guard case .drawn = result.visibility["target"], result.reading.captureStable, result.reading.fold == .absent else {
                    return .abort("cycle \(cycle): expected target drawn, stable, fold absent -- got \(describe(result))")
                }
            }

            target.hide()
            settleAfterToggle()
            switch observeChecked(items: items, label: "cycle\(cycle).hidden") {
            case .failure(let reason): return .abort(reason)
            case .success(let result):
                let hiding = decision.hiding(of: "target", in: result.reading)
                guard hiding == .hidden(folded: false) else {
                    return .abort("cycle \(cycle): expected hidden(folded: false) -- got \(hiding)")
                }
            }

            target.show()
            settleAfterToggle()
            switch observeChecked(items: items, label: "cycle\(cycle).restored") {
            case .failure(let reason): return .abort(reason)
            case .success(let result):
                let restoration = decision.restoration(of: "target", in: result.reading)
                guard case .restored = restoration else {
                    return .abort("cycle \(cycle): expected restored -- got \(restoration)")
                }
            }
        }
        return .ok
    }

    /// The bar needs a moment after a toggle: an observation started
    /// immediately catches one sample before the change and one after, and the
    /// settle rule (rightly) calls that unstable — MEASURED on the first live
    /// run, where `hide` and the observation were 0.47 s apart.
    func settleAfterToggle() {
        Thread.sleep(forTimeInterval: 1.0)
    }

    func describe(_ result: ObservationResult) -> String {
        let visibility = result.visibility["target"].map { "\($0)" } ?? "nil"
        return "visibility=\(visibility) stable=\(result.reading.captureStable) fold=\(result.reading.fold)"
    }
}
