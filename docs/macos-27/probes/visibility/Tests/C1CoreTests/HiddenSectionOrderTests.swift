// C2 T3 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 1): the preflight
// order check and the placement gate generalized to k hidden items, with
// C1's own k = 1 behaviour unchanged.
import Testing
@testable import C1Core

@Suite("HiddenSectionOrder")
struct HiddenSectionOrderTests {
    let hidden = ["vz-target", "vz-hidden-2", "vz-hidden-3"]
    let spacer = "vz-spacer"

    @Test("the k hidden items in order, then the spacer -> passes")
    func kHiddenPass() {
        let order = hidden + [spacer, "vz-protected"]
        #expect(PreflightOrderCheck.check(axOrder: order, pixelOrder: order, hidden: hidden, spacer: spacer) == nil)
    }

    @Test("readings disagree -> disagree, before anything else")
    func kHiddenDisagree() {
        let order = hidden + [spacer]
        #expect(PreflightOrderCheck.check(axOrder: order, pixelOrder: order.reversed(), hidden: hidden, spacer: spacer) == .disagree)
    }

    @Test("something else leftmost -> targetNotLeftmost")
    func kHiddenNotLeftmost() {
        let order = ["owner"] + hidden + [spacer]
        #expect(PreflightOrderCheck.check(axOrder: order, pixelOrder: order, hidden: hidden, spacer: spacer) == .targetNotLeftmost)
    }

    @Test("Target leftmost but the other hidden items out of order or interleaved -> hiddenOutOfOrder")
    func kHiddenOutOfOrder() {
        let swapped = ["vz-target", "vz-hidden-3", "vz-hidden-2", spacer]
        #expect(PreflightOrderCheck.check(axOrder: swapped, pixelOrder: swapped, hidden: hidden, spacer: spacer) == .hiddenOutOfOrder)
        let interleaved = ["vz-target", "owner", "vz-hidden-2", "vz-hidden-3", spacer]
        #expect(PreflightOrderCheck.check(axOrder: interleaved, pixelOrder: interleaved, hidden: hidden, spacer: spacer) == .hiddenOutOfOrder)
        let short = ["vz-target", "vz-hidden-2"]
        #expect(PreflightOrderCheck.check(axOrder: short, pixelOrder: short, hidden: hidden, spacer: spacer) == .hiddenOutOfOrder)
    }

    @Test("the hidden items in order but something before the spacer -> targetNotAloneLeftOfSpacer")
    func kHiddenExtraBeforeSpacer() {
        let order = hidden + ["owner", spacer]
        #expect(PreflightOrderCheck.check(axOrder: order, pixelOrder: order, hidden: hidden, spacer: spacer) == .targetNotAloneLeftOfSpacer)
    }

    @Test("an empty hidden list is refused as targetNotLeftmost")
    func emptyHidden() {
        #expect(PreflightOrderCheck.check(axOrder: [spacer], pixelOrder: [spacer], hidden: [], spacer: spacer) == .targetNotLeftmost)
    }

    // MARK: - gate

    @Test("gate: extra hidden items strictly between Target and the spacer -> passes")
    func gateExtraHiddenPass() {
        let reading = PlacementGate.Reading(targetMinX: 100, spacerMinX: 190, protectedMinX: 230, onBarOwnerMinXs: [300], extraHiddenMinXs: [130, 160])
        #expect(PlacementGate.check(reading) == nil)
    }

    @Test("gate: an extra hidden item without a frame -> helperOffBarOrFolded")
    func gateExtraHiddenMissing() {
        let reading = PlacementGate.Reading(targetMinX: 100, spacerMinX: 190, protectedMinX: 230, onBarOwnerMinXs: [], extraHiddenMinXs: [130, nil])
        #expect(PlacementGate.check(reading) == .helperOffBarOrFolded)
    }

    @Test("gate: extra hidden items out of order, or right of the spacer -> hiddenMisorder")
    func gateExtraHiddenMisorder() {
        let swapped = PlacementGate.Reading(targetMinX: 100, spacerMinX: 190, protectedMinX: 230, onBarOwnerMinXs: [], extraHiddenMinXs: [160, 130])
        #expect(PlacementGate.check(swapped) == .hiddenMisorder(minXs: [100, 160, 130, 190]))
        let past = PlacementGate.Reading(targetMinX: 100, spacerMinX: 190, protectedMinX: 230, onBarOwnerMinXs: [], extraHiddenMinXs: [200])
        #expect(PlacementGate.check(past) == .hiddenMisorder(minXs: [100, 200, 190]))
    }

    @Test("gate: readings with different extra hidden frames do not materially agree")
    func gateAgreementCoversExtras() {
        let a = PlacementGate.Reading(targetMinX: 100, spacerMinX: 190, protectedMinX: 230, onBarOwnerMinXs: [], extraHiddenMinXs: [130])
        let b = PlacementGate.Reading(targetMinX: 100, spacerMinX: 190, protectedMinX: 230, onBarOwnerMinXs: [], extraHiddenMinXs: [140])
        let c = PlacementGate.Reading(targetMinX: 100, spacerMinX: 190, protectedMinX: 230, onBarOwnerMinXs: [], extraHiddenMinXs: [])
        #expect(!PlacementGate.materiallyAgree(a, b))
        #expect(!PlacementGate.materiallyAgree(a, c))
        #expect(PlacementGate.materiallyAgree(a, a))
    }
}
