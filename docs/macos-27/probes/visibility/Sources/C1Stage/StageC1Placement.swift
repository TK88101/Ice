// Amendment v8's own "Placement gate": section 2's premise -- "each new item
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
//
// Amendment v9 ("Sort-key values" / "Real pitch" / "Gate"): `step1bPlacementPlan`
// now also reads (read-only, bounded) every on-bar owner item's own
// preference domain before computing the plan (`PlacementValueScan`), and
// `step2bPlacementGate` now requires two consecutive, materially identical
// discovery reads before it decides, and reports a misorder or a missing
// helper frame as its own distinct top-level reason (`PlacementGate.check`).
import C1Core
import Foundation
import IceCore
import MenuBarDiscovery

extension StageC1 {
    /// Amendment v9: how many discovery passes `step2bPlacementGate` will
    /// take, at most, while waiting for two consecutive, materially
    /// identical reads -- bounded to a short interval (H2's own "e.g.
    /// 5 s") rather than an unbounded retry.
    static let placementGateAgreementBoundSeconds = 5.0

    /// Amendment v8, "Placement by the helpers' own preferred position"
    /// (option A): one discovery pass, before any helper exists, feeds
    /// `PlacementPlan` (C1Core, pure) -- the on-bar owner items already
    /// there (`.onBar` only; there is no helper yet at this point to
    /// filter out either), each one's own read-only preference-domain scan
    /// (Amendment v9), the bar's own geometry (already known, from
    /// `step1Setup`) and each helper's own real occupied pitch. A refused
    /// plan (no room, or an owner scan this plan cannot trust) ends the run
    /// INCONCLUSIVE here, before any process ever launches -- there is
    /// nothing yet to reap. A valid plan is only ever numbers recorded to
    /// evidence and later written into the helpers' own defaults domains
    /// (`launchAndDiscover`) -- a plan, never a promise:
    /// `step2bPlacementGate`, after the real launches, is what actually
    /// decides whether macOS 27 honoured it.
    func step1bPlacementPlan() -> StepResult {
        guard !isTerminal else { return .abort("terminal before the placement plan") }
        guard let pass = environment.pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }) else {
            return .abort("placement plan: discovery failed")
        }
        guard !isTerminal else { return .abort("terminal during the placement plan's own discovery") }

        let onBarOwners = pass.set.items.filter { $0.position == .onBar }
        let notchRightEdge = geometry.notch?.hi ?? 0

        let classifiedOwners = onBarOwners.compactMap { item -> PlacementValueScan.Classified? in
            guard let minX = item.frame?.minX else { return nil }
            let bundleID = item.process.bundleID
            let rawValues: [String]?
            if let bundleID {
                rawValues = environment.ownerPreferenceScanner.matchingValues(bundleID: bundleID)
            } else {
                rawValues = nil
            }
            return PlacementValueScan.classify(.init(minX: minX, bundleID: bundleID, rawValues: rawValues))
        }

        let outcome = PlacementPlan.plan(
            owners: classifiedOwners,
            barRightEdge: geometry.widthPt,
            notchRightEdge: notchRightEdge,
            targetOccupiedPt: C1HelperWidth.occupiedPitchPt,
            spacerOccupiedPt: C1HelperWidth.spacerOccupiedPitchPt,
            protectedOccupiedPt: C1HelperWidth.occupiedPitchPt
        )

        switch outcome {
        case .refused(let reason):
            // This abort runs in `run()`'s first, pre-launch step loop,
            // whose own generic `.abort` handling already promotes
            // `reason` straight to the top-level verdict (prefixed
            // "setup: step1b.placementPlan: ") -- unlike
            // `step2bPlacementGate`'s own post-launch abort, which goes
            // through `runTeardownAndDecide`/`RunAccounting.decide` and so
            // needs `placementGateFailureReason` threaded explicitly.
            let (reasonText, evidenceKind, evidenceFields) = describeRefusal(reason, onBarOwnerCount: classifiedOwners.count)
            evidence?.record(evidenceKind, evidenceFields)
            return .abort(reasonText)
        case .planned(let plan):
            placementPlan = plan
            evidence?.record("placement.plan", [
                "targetMinX": plan.targetMinX,
                "spacerMinX": plan.spacerMinX,
                "protectedMinX": plan.protectedMinX,
                "targetPreferredPosition": plan.targetPreferredPosition,
                "spacerPreferredPosition": plan.spacerPreferredPosition,
                "protectedPreferredPosition": plan.protectedPreferredPosition,
                "floorValue": plan.floorValue,
                "onBarOwnerMinXs": classifiedOwners.map(\.minX),
            ])
            return .ok
        }
    }

    private func describeRefusal(_ reason: PlacementPlan.RefusalReason, onBarOwnerCount: Int) -> (text: String, evidenceKind: String, evidenceFields: [String: Any]) {
        switch reason {
        case .ownerScanUncertain(let minX, let issue):
            let text = "an on-bar owner item's own preference-domain scan was uncertain (\(issue)) at minX \(minX)"
            return (text, "placement.scanUncertain", ["minX": minX, "issue": "\(issue)"])
        case .noRoom(let count):
            let text = "no room for the helpers left of \(count) owner item(s)"
            return (text, "placement.noRoom", ["onBarOwnerCount": count])
        }
    }

    /// Amendment v9, "Gate": takes discovery reads (through `timedDiscoverer`,
    /// like every other post-launch discovery read -- a hung pass here must
    /// trip like any other) until two consecutive ones agree
    /// (`PlacementGate.materiallyAgree`) or `placementGateAgreementBoundSeconds`
    /// passes, then decides on the last agreeing read
    /// (`PlacementGate.check`). Every pass is recorded -- role-labelled
    /// helper and owner minXs, and the plan's own values (already recorded
    /// by `step1bPlacementPlan`) -- so the evidence can tell "key ignored"
    /// apart from "key honoured but outranked."
    func step2bPlacementGate() -> StepResult {
        // F5: no gate work starts after a stop.
        guard !isTerminal else { return .abort("terminal before the placement gate") }
        guard let targetKey, let spacerKey, let protectedKey else { return .abort("helpers not launched") }

        let deadline = environment.pump.now() + Self.placementGateAgreementBoundSeconds
        var previous: PlacementGate.Reading?
        repeat {
            guard !isTerminal else { return .abort("terminal during the placement gate's own discovery") }
            guard let current = readPlacementGate(targetKey: targetKey, spacerKey: spacerKey, protectedKey: protectedKey) else {
                return .abort("placement gate: discovery failed")
            }
            evidence?.record("placement.gateRead", [
                "targetMinX": current.targetMinX as Any,
                "spacerMinX": current.spacerMinX as Any,
                "protectedMinX": current.protectedMinX as Any,
                "onBarOwnerMinXs": current.onBarOwnerMinXs,
            ])
            if let previous, PlacementGate.materiallyAgree(previous, current) {
                return decidePlacementGate(current)
            }
            previous = current
            environment.pump.sleep(0.5)
        } while environment.pump.now() < deadline
        return .abort("placement gate: readings never agreed within \(Int(Self.placementGateAgreementBoundSeconds)) s")
    }

    private func readPlacementGate(targetKey: ItemKey, spacerKey: ItemKey, protectedKey: ItemKey) -> PlacementGate.Reading? {
        guard let pass = environment.pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }) else {
            return nil
        }
        func minX(for key: ItemKey) -> Double? {
            guard let item = pass.set.items.first(where: { $0.key == key }), item.position == .onBar else { return nil }
            return item.frame?.minX
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
        return PlacementGate.Reading(
            targetMinX: minX(for: targetKey),
            spacerMinX: minX(for: spacerKey),
            protectedMinX: minX(for: protectedKey),
            onBarOwnerMinXs: onBarOwnerMinXs
        )
    }

    private func decidePlacementGate(_ reading: PlacementGate.Reading) -> StepResult {
        guard let failure = PlacementGate.check(reading) else { return .ok }
        // Amendment v8a: this abort runs in `run()`'s second step loop,
        // whose `.abort` handling routes through `runTeardownAndDecide` ->
        // `RunAccounting.decide`, which never saw `reason` at all -- only
        // step evidence did. Threading it here is what makes it the
        // top-level verdict's own reason, verbatim.
        let reason: String
        switch failure {
        case .misorder(let targetMinX, let spacerMinX, let protectedMinX):
            reason = "helpers misordered: target \(targetMinX), spacer \(spacerMinX), protected \(protectedMinX)"
        case .helperOffBarOrFolded:
            reason = "a helper is off the bar or folded"
        case .ownerItemsLeft(let count):
            reason = "helpers not leftmost: \(count) owner items left"
        }
        evidence?.record("placement.gateFailed", ["reason": reason])
        placementGateFailureReason = reason
        return .abort(reason)
    }
}
