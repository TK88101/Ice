import Testing
@testable import C1Core

/// Amendment v8, "Placement by the helpers' own preferred position"
/// (option A): the pure geometry behind the write -- given the on-bar
/// owner items that already exist (parked items already excluded by the
/// caller, per Amendment v8's first bullet), the bar's right edge and the
/// room right of the notch, and each helper's own width, where Target, the
/// spacer and Protected should sit, left to right, so the group lands left
/// of every on-bar owner item with a margin. `nil` (refuse) when there is
/// no room -- this is a plan, never a promise: whether macOS 27 actually
/// honours the resulting write is what the placement gate (post-launch)
/// and the placement-only dry rehearsal decide, not this function.
@Suite("PlacementPlan")
struct PlacementPlanTests {
    let targetWidth = 12.0
    let spacerWidth = 17.5
    let protectedWidth = 12.0

    @Test("plenty of room, one owner item -- lands left to right, margin left of the owner item")
    func plentyOfRoomOneOwner() throws {
        let result = PlacementPlan.plan(
            onBarOwnerMinXs: [270.0],
            barRightEdge: 320.0,
            notchRightEdge: 0.0,
            targetWidthPt: targetWidth,
            spacerWidthPt: spacerWidth,
            protectedWidthPt: protectedWidth
        )
        let plan = try #require(result)
        // Left to right: Target -> spacer -> Protected, each flush against
        // the next (no gaps between the helpers themselves).
        #expect(plan.spacerMinX == plan.targetMinX + targetWidth)
        #expect(plan.protectedMinX == plan.spacerMinX + spacerWidth)
        // Protected's own trailing edge sits `marginPt` left of the owner
        // item's minX.
        #expect(plan.protectedMinX + protectedWidth == 270.0 - PlacementPlan.marginPt)
        // Every helper strictly left of the owner item.
        #expect(plan.protectedMinX + protectedWidth <= 270.0)
    }

    @Test("no on-bar owner items at all -- anchored `marginPt` left of the bar's own right edge")
    func noOwnerItemsAnchorsAtRightEdge() throws {
        let result = PlacementPlan.plan(
            onBarOwnerMinXs: [],
            barRightEdge: 320.0,
            notchRightEdge: 0.0,
            targetWidthPt: targetWidth,
            spacerWidthPt: spacerWidth,
            protectedWidthPt: protectedWidth
        )
        let plan = try #require(result)
        #expect(plan.protectedMinX + protectedWidth == 320.0 - PlacementPlan.marginPt)
    }

    @Test("only the leftmost owner item constrains the plan -- others further right are irrelevant")
    func onlyLeftmostOwnerConstrains() {
        let withOne = PlacementPlan.plan(onBarOwnerMinXs: [120.0], barRightEdge: 320.0, notchRightEdge: 0.0, targetWidthPt: targetWidth, spacerWidthPt: spacerWidth, protectedWidthPt: protectedWidth)
        let withSeveral = PlacementPlan.plan(onBarOwnerMinXs: [120.0, 200.0, 270.0], barRightEdge: 320.0, notchRightEdge: 0.0, targetWidthPt: targetWidth, spacerWidthPt: spacerWidth, protectedWidthPt: protectedWidth)
        #expect(withOne == withSeveral)
    }

    @Test("exactly enough room (the group's left edge lands exactly on the notch's right edge) -- passes, not refused")
    func exactlyEnoughRoomPasses() throws {
        // groupLeftEdge = (owner - margin) - totalWidth == notchRightEdge.
        let totalWidth = targetWidth + spacerWidth + protectedWidth
        let ownerMinX = PlacementPlan.marginPt + totalWidth
        let result = PlacementPlan.plan(onBarOwnerMinXs: [ownerMinX], barRightEdge: 320.0, notchRightEdge: 0.0, targetWidthPt: targetWidth, spacerWidthPt: spacerWidth, protectedWidthPt: protectedWidth)
        let plan = try #require(result)
        #expect(plan.targetMinX == 0.0)
    }

    @Test("one point short of room -- refused (nil)")
    func onePointShortOfRoomRefuses() {
        let totalWidth = targetWidth + spacerWidth + protectedWidth
        let ownerMinX = PlacementPlan.marginPt + totalWidth - 1.0
        let result = PlacementPlan.plan(onBarOwnerMinXs: [ownerMinX], barRightEdge: 320.0, notchRightEdge: 0.0, targetWidthPt: targetWidth, spacerWidthPt: spacerWidth, protectedWidthPt: protectedWidth)
        #expect(result == nil)
    }

    @Test("a notch that already consumes the whole bar -- refused (nil)")
    func notchConsumingWholeBarRefuses() {
        let result = PlacementPlan.plan(onBarOwnerMinXs: [], barRightEdge: 320.0, notchRightEdge: 320.0, targetWidthPt: targetWidth, spacerWidthPt: spacerWidth, protectedWidthPt: protectedWidth)
        #expect(result == nil)
    }

    @Test("a non-positive helper width is refused (nil) -- defensive, never a zero-width helper in the real geometry")
    func nonPositiveWidthRefuses() {
        #expect(PlacementPlan.plan(onBarOwnerMinXs: [], barRightEdge: 320.0, notchRightEdge: 0.0, targetWidthPt: 0, spacerWidthPt: spacerWidth, protectedWidthPt: protectedWidth) == nil)
        #expect(PlacementPlan.plan(onBarOwnerMinXs: [], barRightEdge: 320.0, notchRightEdge: 0.0, targetWidthPt: targetWidth, spacerWidthPt: -1, protectedWidthPt: protectedWidth) == nil)
    }

    @Test("the preferred-position value written for each helper is the bar's right edge minus its own minX (INFERRED right-edge-distance assumption, SEAM-AUDIT.md)")
    func preferredPositionValueIsDistanceFromRightEdge() throws {
        let result = PlacementPlan.plan(onBarOwnerMinXs: [270.0], barRightEdge: 320.0, notchRightEdge: 0.0, targetWidthPt: targetWidth, spacerWidthPt: spacerWidth, protectedWidthPt: protectedWidth)
        let plan = try #require(result)
        #expect(plan.targetPreferredPosition == 320.0 - plan.targetMinX)
        #expect(plan.spacerPreferredPosition == 320.0 - plan.spacerMinX)
        #expect(plan.protectedPreferredPosition == 320.0 - plan.protectedMinX)
    }
}
