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
        return .abort("helpers not leftmost: \(count) owner items left")
    }
}
