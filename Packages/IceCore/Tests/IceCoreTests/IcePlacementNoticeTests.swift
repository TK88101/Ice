import Testing
@testable import IceCore

/// When Ice says that its icon is on the wrong side of its hidden divider
/// (plan 2026-10-07-icebar-preference-hiding, S2 design T2c).
@Suite("IcePlacementNotice")
struct IcePlacementNoticeTests {
    @Test("an icon left of the divider in IceBar mode, with no drag under way, gives the notice")
    func inverted() {
        #expect(IcePlacementNotice.notice(placement: .iconLeftOfDivider, isIceBarMode: true, isDragging: false) == .iconLeftOfDivider)
    }

    @Test("an icon right of the divider gives none")
    func rightOfDivider() {
        #expect(IcePlacementNotice.notice(placement: nil, isIceBarMode: true, isDragging: false) == nil)
    }

    @Test("what Ice could not read is not reported as inverted", arguments: [
        PreferenceHidingIconPlacement.iconUnreadable,
        .dividerUnusable,
    ])
    func unreadable(placement: PreferenceHidingIconPlacement) {
        #expect(IcePlacementNotice.notice(placement: placement, isIceBarMode: true, isDragging: false) == nil)
    }

    @Test("outside IceBar mode the layout is the owner's business: no notice")
    func notIceBarMode() {
        #expect(IcePlacementNotice.notice(placement: .iconLeftOfDivider, isIceBarMode: false, isDragging: false) == nil)
    }

    @Test("during a drag the owner is arranging: no notice until it ends")
    func dragging() {
        #expect(IcePlacementNotice.notice(placement: .iconLeftOfDivider, isIceBarMode: true, isDragging: true) == nil)
    }

    // MARK: - Which pass may say where the icon is

    @Test("with the divider at standard length the pass's reading replaces what Ice held", arguments: [
        PreferenceHidingIconPlacement?.none, .iconLeftOfDivider, .iconUnreadable, .dividerUnusable,
    ])
    func standardLengthPassReplaces(read: PreferenceHidingIconPlacement?) {
        #expect(IcePlacementNotice.placement(held: .iconLeftOfDivider, read: read, dividerAtStandardLength: true) == read)
        #expect(IcePlacementNotice.placement(held: nil, read: read, dividerAtStandardLength: true) == read)
    }

    @Test("while the divider is at a hiding length its left edge is not the boundary: an inversion Ice held is kept (Codex review, T2c)")
    func hidingDividerDoesNotClear() {
        // The expanded divider's minX is far left, so the icon reads right of it, or the divider unusable.
        #expect(IcePlacementNotice.placement(held: .iconLeftOfDivider, read: nil, dividerAtStandardLength: false) == .iconLeftOfDivider)
        #expect(IcePlacementNotice.placement(held: .iconLeftOfDivider, read: .dividerUnusable, dividerAtStandardLength: false) == .iconLeftOfDivider)
    }

    @Test("nor does such a pass report an inversion or an unusable divider Ice did not hold: there the divider always reads so (T3b, G3)")
    func hidingDividerDoesNotSet() {
        #expect(IcePlacementNotice.placement(held: nil, read: .iconLeftOfDivider, dividerAtStandardLength: false) == nil)
        #expect(IcePlacementNotice.placement(held: nil, read: .dividerUnusable, dividerAtStandardLength: false) == nil)
    }

    @Test("an icon read as not on the bar is unreadable at once, at any length: it was carried off with the section (T3b, G3)")
    func iconOffTheBarAtAHidingLength() {
        #expect(IcePlacementNotice.placement(held: nil, read: .iconUnreadable, dividerAtStandardLength: false) == .iconUnreadable)
        #expect(IcePlacementNotice.placement(held: .iconLeftOfDivider, read: .iconUnreadable, dividerAtStandardLength: false) == .iconUnreadable)
    }

    @Test("a divider is at standard length when Ice holds it enabled, collapsed, settled and unchanged during the pass")
    func dividerAtStandardLength() {
        func state(enabled: Bool = true, collapsed: Bool = true, collapsedFor: Double = 5, changed: Bool = false) -> DividerState {
            DividerState(isEnabled: enabled, isCollapsed: collapsed, collapsedFor: collapsedFor, changedDuringPass: changed)
        }
        #expect(state().isAtStandardLength)
        #expect(state(collapsedFor: DiscoveredCachePlan.settleSeconds).isAtStandardLength)
        #expect(!state(enabled: false).isAtStandardLength)
        #expect(!state(collapsed: false).isAtStandardLength)
        #expect(!state(collapsedFor: 0.5).isAtStandardLength)
        #expect(!state(changed: true).isAtStandardLength)
    }

    @Test("the text says what is wrong, what Ice does about it and the repair, and promises nothing about the drag lasting")
    func text() {
        let message = IcePlacementNotice.iconLeftOfDivider.message
        #expect(message == "Ice's icon is left of its hidden-section divider, so Ice hides nothing. "
            + "Hold Command and drag Ice's icon to the right of the divider.")
    }
}
