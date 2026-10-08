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

    @Test("a pass whose hidden boundary is trusted replaces what Ice held", arguments: [
        PreferenceHidingIconPlacement?.none, .iconLeftOfDivider, .iconUnreadable, .dividerUnusable,
    ])
    func trustedPassReplaces(read: PreferenceHidingIconPlacement?) {
        #expect(IcePlacementNotice.placement(held: .iconLeftOfDivider, read: read, hiddenBoundaryTrusted: true) == read)
        #expect(IcePlacementNotice.placement(held: nil, read: read, hiddenBoundaryTrusted: true) == read)
    }

    @Test("while the divider is at a hiding length its left edge is not the boundary: an inversion Ice held is kept (Codex review, T2c)")
    func hidingDividerDoesNotClear() {
        // The expanded divider's minX is far left, so the icon reads right of it, or the divider unusable.
        #expect(IcePlacementNotice.placement(held: .iconLeftOfDivider, read: nil, hiddenBoundaryTrusted: false) == .iconLeftOfDivider)
        #expect(IcePlacementNotice.placement(held: .iconLeftOfDivider, read: .dividerUnusable, hiddenBoundaryTrusted: false) == .iconLeftOfDivider)
    }

    @Test("nor does such a pass report an inversion Ice did not hold")
    func hidingDividerDoesNotSet() {
        #expect(IcePlacementNotice.placement(held: nil, read: .iconLeftOfDivider, hiddenBoundaryTrusted: false) == nil)
    }

    @Test("the text says what is wrong, what Ice does about it and the repair, and promises nothing about the drag lasting")
    func text() {
        let message = IcePlacementNotice.iconLeftOfDivider.message
        #expect(message == "Ice's icon is left of its hidden-section divider, so Ice hides nothing. "
            + "Hold Command and drag Ice's icon to the right of the divider.")
    }
}
