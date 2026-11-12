import Testing
@testable import IceCore

@Suite("MenuBarPointRule")
struct MenuBarPointRuleTests {
    let item = BarRect(minX: 1078, minY: 4.5, width: 14, height: 24)
    let clock = BarRect(minX: 1584, minY: 0, width: 124, height: 33)

    @Test("a point inside an item's frame is on an item")
    func inside() {
        #expect(MenuBarPointRule.isOnItem(x: 1085, itemFrames: [item], hasReading: true))
        #expect(MenuBarPointRule.isOnItem(x: 1600, itemFrames: [item, clock], hasReading: true))
    }

    @Test("an item is clicked in its window, which is wider than its frame: the margin counts")
    func margin() {
        #expect(MenuBarPointRule.isOnItem(x: 1078 - MenuBarPointRule.margin, itemFrames: [item], hasReading: true))
        #expect(MenuBarPointRule.isOnItem(x: 1092 + MenuBarPointRule.margin, itemFrames: [item], hasReading: true))
        #expect(!MenuBarPointRule.isOnItem(x: 1078 - MenuBarPointRule.margin - 1, itemFrames: [item], hasReading: true))
    }

    @Test("a point beside every item is not on one")
    func empty() {
        #expect(!MenuBarPointRule.isOnItem(x: 992, itemFrames: [item, clock], hasReading: true))
        #expect(!MenuBarPointRule.isOnItem(x: 992, itemFrames: [], hasReading: true))
    }

    @Test("without a reading of the bar every point is taken for an item: nothing is shown on a guess")
    func incomplete() {
        #expect(MenuBarPointRule.isOnItem(x: 992, itemFrames: [item], hasReading: false))
        #expect(MenuBarPointRule.isOnItem(x: 992, itemFrames: [], hasReading: false))
    }
}
