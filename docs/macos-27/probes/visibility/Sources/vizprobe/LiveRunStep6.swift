// Plan 6.1 step 6: the three controls, once each.
//   (a) an id with no template -> notObserved
//   (b) with the target hidden, a fresh baseline must reject it (parked frame)
//   (c) a third instance with the target's own glyph -> target reads ambiguous
import Foundation
import IceCore
import MenuBarCapture

extension LiveRun {
    func step6Controls() -> StepResult {
        guard let target, let reference else { return .abort("helpers not launched") }
        let items: [String: pid_t] = ["target": target.pid, "reference": reference.pid]

        if case .abort(let reason) = controlA(items: items) { return .abort(reason) }
        if case .abort(let reason) = controlB(target: target, items: items) { return .abort(reason) }
        if case .abort(let reason) = controlC(items: items) { return .abort(reason) }
        return .ok
    }

    /// (a) An id nothing ever observed must read `notObserved`, never
    /// silently `hidden`: this is the one failure that would let an item
    /// disappear unnoticed (`MenuBarItemVisibility.hiding`'s own doc
    /// comment, Packages/IceCore/Sources/IceCore/MenuBarItemVisibility.swift).
    private func controlA(items: [String: pid_t]) -> StepResult {
        switch observeChecked(items: items, label: "control.a") {
        case .failure(let reason): return .abort(reason)
        case .success(let result):
            let hiding = decision.hiding(of: "no-such-item", in: result.reading)
            guard hiding == .unverifiable(.notObserved) else {
                return .abort("control (a): expected notObserved for an unknown id -- got \(hiding)")
            }
            return .ok
        }
    }

    /// (b) A hidden item's own Accessibility frame parks below the bar
    /// (plan 3.2 rule 2, `.offBar`); a fresh baseline taken while it is
    /// hidden must reject it, not accept a stale template from a slot the
    /// item no longer draws in.
    private func controlB(target: HelperControl, items: [String: pid_t]) -> StepResult {
        target.hide()
        Thread.sleep(forTimeInterval: 1.0)
        guard let freshBaseline = observer.baseline(items: items, geometry: geometry) else {
            return .abort("control (b): a fresh baseline failed while the target was hidden")
        }
        evidence.record("control.b.baseline", ["accepted": freshBaseline.acceptedIDs, "rejections": freshBaseline.rejections.mapValues { "\($0)" }])
        // MEASURED 2026-09-19: an item hidden by its own app with
        // `isVisible = false` leaves `AXExtrasMenuBar` altogether on macOS 27 —
        // it is not parked at x 7, y 1104 the way FINDINGS records for other
        // ways of hiding. So the control passes either way: what matters is
        // that no template is cut from a hidden item.
        guard !freshBaseline.acceptedIDs.contains("target") else {
            return .abort("control (b): a hidden target was accepted -- accepted=\(freshBaseline.acceptedIDs)")
        }
        evidence.record("control.b.outcome", [
            "rejected": freshBaseline.rejections["target"].map { "\($0)" } ?? "absent from Accessibility entirely",
        ])

        target.show()
        Thread.sleep(forTimeInterval: 1.0)
        if let reason = safetyCapture(label: "control.b") {
            return .abort(reason)
        }
        return .ok
    }

    /// (c) The twin draws the exact same glyph as the target (vzhelper's
    /// own rule); with it up, the target's template must find two matches.
    private func controlC(items: [String: pid_t]) -> StepResult {
        let twinHelper: HelperControl
        do {
            twinHelper = try HelperControl(appURL: apps.twin, bundleID: HelperRole.twin, role: "twin", controllerPID: getpid())
        } catch {
            return .abort("control (c): could not launch the twin: \(error)")
        }
        twin = twinHelper
        Thread.sleep(forTimeInterval: 1.0)

        let outcome = observeChecked(items: items, label: "control.c")
        twinHelper.quit()
        twin = nil
        HelperDefaults.forget(HelperRole.twin)

        switch outcome {
        case .failure(let reason):
            return .abort(reason)
        case .success(let result):
            let match = result.reading.sightings.first(where: { $0.id == "target" })?.match
            guard case .ambiguous? = match else {
                return .abort("control (c): expected the target's match to read ambiguous with the twin present -- got \(String(describing: match))")
            }
            return .ok
        }
    }
}
