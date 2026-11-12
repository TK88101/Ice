import Testing
@testable import IceCore

@Suite("MenuBarPointRule")
struct MenuBarPointRuleTests {
    let item = BarRect(minX: 1078, minY: 4.5, width: 14, height: 24)
    let clock = BarRect(minX: 1584, minY: 0, width: 124, height: 33)

    @Test("a point inside an item's frame is on an item")
    func inside() {
        #expect(MenuBarPointRule.isOnItem(x: 1085, y: 16, itemFrames: [item], hasReading: true))
        #expect(MenuBarPointRule.isOnItem(x: 1600, y: 16, itemFrames: [item, clock], hasReading: true))
    }

    @Test("an item is clicked in its window, which is wider than its frame: the margin counts")
    func margin() {
        #expect(MenuBarPointRule.isOnItem(x: 1078 - MenuBarPointRule.margin, y: 16, itemFrames: [item], hasReading: true))
        #expect(MenuBarPointRule.isOnItem(x: 1092 + MenuBarPointRule.margin, y: 16, itemFrames: [item], hasReading: true))
        #expect(!MenuBarPointRule.isOnItem(x: 1078 - MenuBarPointRule.margin - 1, y: 16, itemFrames: [item], hasReading: true))
    }

    @Test("the bar's whole height counts, also above and below the frame")
    func height() {
        #expect(MenuBarPointRule.isOnItem(x: 1085, y: 1, itemFrames: [item], hasReading: true))
        #expect(MenuBarPointRule.isOnItem(x: 1085, y: 32, itemFrames: [item], hasReading: true))
    }

    @Test("a point beside every item is not on one")
    func empty() {
        #expect(!MenuBarPointRule.isOnItem(x: 992, y: 16, itemFrames: [item, clock], hasReading: true))
        #expect(!MenuBarPointRule.isOnItem(x: 992, y: 16, itemFrames: [], hasReading: true))
    }

    @Test("without a reading of the bar every point is taken for an item: nothing is shown on a guess")
    func incomplete() {
        #expect(MenuBarPointRule.isOnItem(x: 992, y: 16, itemFrames: [item], hasReading: false))
        #expect(MenuBarPointRule.isOnItem(x: 992, y: 16, itemFrames: [], hasReading: false))
    }
}
