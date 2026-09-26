// Amendment v8's "Placement gate": section 2's premise -- "each new item
// lands at the left end" -- is false on the owner's bar (a fourth
// cross-check found 1-3 owner items drawn left of the helpers in every
// recorded run there, crosscheck-rework7.json finding #1). Right after the
// launches, before `step3Baseline` takes any baseline and before any
// `length` is ever sent, one discovery pass must show Target, the spacer
// and Protected each left of every on-bar owner item. The pure decision is
// `C1Core.PlacementGate`; this file only gathers the minXs from one
// discovery pass and acts on the answer -- reap, verify the helper domains
// are empty, and end INCONCLUSIVE, never a safety stop (this is not a C1
// failure; it is this bar not supporting C1's own geometry).
import C1Core
import Foundation
import IceCore
import MenuBarDiscovery

extension StageC1 {
    /// Amendment v8, "Placement by the helpers' own preferred position"
    /// (option A): one discovery pass, before any helper exists, feeds
    /// `PlacementPlan` (C1Core, pure) -- the on-bar owner items already
    /// there (`.onBar` only; there is no helper yet at this point to
    /// filter out either), the bar's own geometry (already known, from
    /// `step1Setup`) and each helper's own width. A `nil` plan (no room)
    /// ends the run INCONCLUSIVE here, before any process ever launches --
    /// there is nothing yet to reap. A valid plan is only ever numbers
    /// recorded to evidence and later written into the helpers' own
    /// defaults domains (`launchAndDiscover`) -- a plan, never a promise:
    /// `step2bPlacementGate`, after the real launches, is what actually
    /// decides whether macOS 27 honoured it.
    func step1bPlacementPlan() -> StepResult {
        guard !isTerminal else { return .abort("terminal before the placement plan") }
        guard let pass = environment.pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }) else {
            return .abort("placement plan: discovery failed")
        }
        guard !isTerminal else { return .abort("terminal during the placement plan's own discovery") }

        let onBarOwnerMinXs = pass.set.items
            .filter { $0.position == .onBar }
            .compactMap(\.frame?.minX)
        let notchRightEdge = geometry.notch?.hi ?? 0

        guard let plan = PlacementPlan.plan(
            onBarOwnerMinXs: onBarOwnerMinXs,
            barRightEdge: geometry.widthPt,
            notchRightEdge: notchRightEdge,
            targetWidthPt: C1HelperWidth.plainItemPt,
            spacerWidthPt: parameters.chevronWidthPt,
            protectedWidthPt: C1HelperWidth.plainItemPt
        ) else {
            // This abort runs in `run()`'s first, pre-launch step loop,
            // whose own generic `.abort` handling already promotes
            // `reason` straight to the top-level verdict (prefixed
            // "setup: step1b.placementPlan: ") -- unlike
            // `step2bPlacementGate`'s own post-launch abort, which goes
            // through `runTeardownAndDecide`/`RunAccounting.decide` and so
            // needs `placementGateFailureReason` threaded explicitly.
            let reason = "no room for the helpers left of \(onBarOwnerMinXs.count) owner item(s)"
            evidence?.record("placement.noRoom", ["onBarOwnerCount": onBarOwnerMinXs.count])
            return .abort(reason)
        }

        placementPlan = plan
        evidence?.record("placement.plan", [
            "targetMinX": plan.targetMinX,
            "spacerMinX": plan.spacerMinX,
            "protectedMinX": plan.protectedMinX,
            "targetPreferredPosition": plan.targetPreferredPosition,
            "spacerPreferredPosition": plan.spacerPreferredPosition,
            "protectedPreferredPosition": plan.protectedPreferredPosition,
        ])
        return .ok
    }

    func step2bPlacementGate() -> StepResult {
        // F5: no gate work starts after a stop.
        guard !isTerminal else { return .abort("terminal before the placement gate") }
        guard let targetKey, let spacerKey, let protectedKey else { return .abort("helpers not launched") }

        // F6: through `timedDiscoverer`, like every other post-launch
        // discovery read -- a hung pass here must trip like any other.
        guard let pass = environment.pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }) else {
            return .abort("placement gate: discovery failed")
        }
        guard !isTerminal else { return .abort("terminal during the placement gate's own discovery") }

        let helperMinXs = [targetKey, spacerKey, protectedKey].compactMap { key in
            pass.set.items.first(where: { $0.key == key })?.frame?.minX
        }
        guard helperMinXs.count == 3 else {
            return .abort("placement gate: a helper has no AX frame")
        }

        // Only `.onBar` items count here (Amendment v8's own wording,
        // "every on-bar owner item") -- a parked item is never an owner
        // item at all (the first bullet), and a stacked/frameless one is
        // this gate's business only insofar as it is genuinely drawn on
        // the bar; `PreflightOrderCheck`/`C1Discoverer` are what actually
        // reject a real obstruction once cycles begin.
        let onBarOwnerMinXs = pass.set.items
            .filter { $0.position == .onBar && ![targetKey, spacerKey, protectedKey].contains($0.key) }
            .compactMap(\.frame?.minX)

        guard let count = PlacementGate.check(helperMinXs: helperMinXs, onBarOwnerMinXs: onBarOwnerMinXs) else {
            return .ok
        }

        evidence?.record("placement.notLeftmost", ["count": count])
        // Amendment v8a: this abort runs in `run()`'s second step loop,
        // whose `.abort` handling routes through `runTeardownAndDecide` ->
        // `RunAccounting.decide`, which never saw `reason` at all -- only
        // step evidence did. Threading it here is what makes it the
        // top-level verdict's own reason, verbatim.
        let reason = "helpers not leftmost: \(count) owner items left"
        placementGateFailureReason = reason
        return .abort(reason)
    }
}
