import Testing
@testable import IceCore

/// `PositionRule` reports what a frame *claims*, never what a capture proved
/// was drawn -- section 4.1.4 is explicit that position is diagnostic, not
/// drawn-ness. Every number below is measured (plan section 0 and the
/// 2026-09-18 overflow runs), not invented, so a rule that silently drifts
/// from the census breaks these tests, not just a live run months later.
@Suite("PositionRule")
struct ItemPositionTests {
    let censusBounds = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)

    // MARK: - No frame at all

    @Test("an item with no frame reads noFrame, never onBar by default")
    func noFrameReadsNoFrame() {
        #expect(PositionRule.position(of: nil, in: censusBounds, obstacles: []) == .noFrame)
    }

    // MARK: - The census bar: 9 drawn items, 2 parked

    @Test("the census bar: every drawn app item reads onBar against its neighbours and the agent items")
    func censusBarItemsReadOnBar() {
        let agentFrames = [
            BarRect(minX: 1438, minY: 0, width: 26, height: 33),
            BarRect(minX: 1480, minY: 0, width: 22, height: 33),
            BarRect(minX: 1550, minY: 0, width: 26, height: 33),
            BarRect(minX: 1592, minY: 0, width: 116, height: 33),
        ]
        let appFrames = [
            BarRect(minX: 1509, minY: 4.5, width: 34, height: 24),
            BarRect(minX: 1385, minY: 4.5, width: 46, height: 24),
            BarRect(minX: 1247, minY: 4.5, width: 24, height: 24),
            BarRect(minX: 1353, minY: 4.5, width: 34, height: 24),
            BarRect(minX: 1176, minY: 4.5, width: 33, height: 24),
            BarRect(minX: 1286, minY: 5.5, width: 22, height: 22),
            BarRect(minX: 1142, minY: 4.5, width: 36, height: 24),
            BarRect(minX: 1323, minY: 4.5, width: 24, height: 24),
            BarRect(minX: 1207, minY: 4.5, width: 34, height: 24),
        ]

        for index in appFrames.indices {
            var others = appFrames
            others.remove(at: index)
            let obstacles = others + agentFrames
            #expect(PositionRule.position(of: appFrames[index], in: censusBounds, obstacles: obstacles) == .onBar)
        }
    }

    @Test("the census bar: no drawn item overlaps a MenuBarAgent frame enough to stack")
    func censusAppItemsDoNotStackAgainstAgentFrames() {
        let agentFrame = BarRect(minX: 1438, minY: 0, width: 26, height: 33)
        let neighbour = BarRect(minX: 1385, minY: 4.5, width: 46, height: 24)
        #expect(PositionRule.position(of: neighbour, in: censusBounds, obstacles: [agentFrame]) == .onBar)
    }

    @Test("the census bar: an item parked off the bar reads parked")
    func censusParkedItemReadsParked() {
        let parked = BarRect(minX: 7, minY: 1105, width: 24, height: 24)
        #expect(PositionRule.position(of: parked, in: censusBounds, obstacles: []) == .parked)
    }

    // MARK: - Recorded overflow (2026-09-18)

    @Test("recorded overflow: an item under the chevron by more than 25% of its own width is stacked")
    func recordedOverflowItemsAreStacked() {
        let item1 = BarRect(minX: 1008, minY: 4.5, width: 14, height: 24)
        let chevron1 = BarRect(minX: 1012.5, minY: 0, width: 17.5, height: 33)
        #expect(PositionRule.position(of: item1, in: censusBounds, obstacles: [chevron1]) == .stacked)

        let item2 = BarRect(minX: 972, minY: 4.5, width: 14, height: 24)
        let chevron2 = BarRect(minX: 976.5, minY: 0, width: 17.5, height: 33)
        #expect(PositionRule.position(of: item2, in: censusBounds, obstacles: [chevron2]) == .stacked)
    }

    @Test("recorded overflow: two identical probes read stacked against each other")
    func identicalProbesAreStacked() {
        let probeA = BarRect(minX: 967, minY: 4.5, width: 26, height: 24)
        let probeB = BarRect(minX: 967, minY: 4.5, width: 26, height: 24)
        #expect(PositionRule.position(of: probeA, in: censusBounds, obstacles: [probeB]) == .stacked)
    }

    // MARK: - Position is not drawn-ness

    @Test("a hidden helper with no obstacle overlap reads onBar even though it was not drawn that run")
    func positionDoesNotClaimDrawnness() {
        // 2026-09-18: this frame belonged to an item that was not actually
        // drawn in that run. The rule only ever looks at frames, so it has no
        // way to know that -- and must not pretend to.
        let hiddenHelper = BarRect(minX: 984, minY: 4.5, width: 14, height: 24)
        #expect(PositionRule.position(of: hiddenHelper, in: censusBounds, obstacles: []) == .onBar)
    }

    @Test("a drawn item under an expanded spacer's frame reads stacked")
    func drawnItemUnderExpandedSpacerIsStacked() {
        let drawnItem = BarRect(minX: 1044, minY: 4.5, width: 14, height: 24)
        let expandedSpacer = BarRect(minX: 1012, minY: 0, width: 5002, height: 33)
        #expect(PositionRule.position(of: drawnItem, in: censusBounds, obstacles: [expandedSpacer]) == .stacked)
    }

    @Test("the expanded frame itself is not parked -- parked is judged by minX alone, never maxX")
    func expandedFrameIsNotParked() {
        let expandedSpacer = BarRect(minX: 1012, minY: 0, width: 5002, height: 33)
        #expect(PositionRule.position(of: expandedSpacer, in: censusBounds, obstacles: []) == .onBar)
    }

    // MARK: - Ice's own items are never obstacles (caller contract)

    @Test("Ice's own divider is never passed as an obstacle, so an item beside it is not marked stacked")
    func iceOwnItemsAreNeverObstacles() {
        // PositionRule has no notion of "Ice's own item" -- the contract that
        // obstacles never include one lives entirely in the caller. This pins
        // both halves: honouring the contract keeps the item onBar, and shows
        // by contrast what breaking it would do (never the caller's choice).
        let item = BarRect(minX: 1000, minY: 4.5, width: 20, height: 24)
        let iceDivider = BarRect(minX: 995, minY: 0, width: 30, height: 33)
        #expect(PositionRule.position(of: item, in: censusBounds, obstacles: []) == .onBar)
        #expect(PositionRule.position(of: item, in: censusBounds, obstacles: [iceDivider]) == .stacked)
    }

    // MARK: - The 25% boundary, exactly and just past

    @Test("an overlap of exactly 25% of the narrower frame is not stacked")
    func exactlyTwentyFivePercentIsNotStacked() {
        let bounds = BarBounds(minX: 1728, maxX: 3456, minY: 0, barHeight: 33)
        let item = BarRect(minX: 1728, minY: 4.5, width: 100, height: 24)
        let obstacle = BarRect(minX: 1728 + 75, minY: 0, width: 100, height: 33) // overlap = 25, narrower = 100
        #expect(PositionRule.position(of: item, in: bounds, obstacles: [obstacle]) == .onBar)
    }

    @Test("an overlap just past 25% of the narrower frame is stacked")
    func justPastTwentyFivePercentIsStacked() {
        let bounds = BarBounds(minX: 1728, maxX: 3456, minY: 0, barHeight: 33)
        let item = BarRect(minX: 1728, minY: 4.5, width: 100, height: 24)
        let obstacle = BarRect(minX: 1728 + 74.9, minY: 0, width: 100, height: 33) // overlap = 25.1
        #expect(PositionRule.position(of: item, in: bounds, obstacles: [obstacle]) == .stacked)
    }

    // MARK: - A second display's own local origin

    @Test("position is judged against the bounds' own origin, not zero")
    func positionRespectsNonZeroOrigin() {
        let bounds = BarBounds(minX: 1728, maxX: 3456, minY: 0, barHeight: 33)

        let onBarItem = BarRect(minX: 1728, minY: 4.5, width: 20, height: 24) // starts exactly at bounds.minX
        #expect(PositionRule.position(of: onBarItem, in: bounds, obstacles: []) == .onBar)

        let justLeftOfBar = BarRect(minX: 1727.9, minY: 4.5, width: 20, height: 24)
        #expect(PositionRule.position(of: justLeftOfBar, in: bounds, obstacles: []) == .parked)

        let atRightEdge = BarRect(minX: 3456, minY: 4.5, width: 20, height: 24) // minX == bounds.maxX
        #expect(PositionRule.position(of: atRightEdge, in: bounds, obstacles: []) == .parked)
    }

    // MARK: - Below the bar

    @Test("a frame below the bar's height reads parked")
    func belowBarHeightReadsParked() {
        let below = BarRect(minX: 100, minY: 33, width: 20, height: 24) // minY == bounds.minY + barHeight
        #expect(PositionRule.position(of: below, in: censusBounds, obstacles: []) == .parked)
    }
}
