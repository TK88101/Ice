import Testing
@testable import IceCore

@Suite("IceBarArrangingRule")
struct IceBarArrangingRuleTests {
    @Test("a Command-drag is arranging, wherever the pointer and the key are")
    func dragIsArranging() {
        #expect(IceBarArrangingRule.isArranging(isDragging: true, isCommandDown: false, isPointerOnBar: false))
    }

    @Test("Command held with the pointer on the bar is arranging: the hidden items are given back")
    func commandOnTheBar() {
        #expect(IceBarArrangingRule.isArranging(isDragging: false, isCommandDown: true, isPointerOnBar: true))
    }

    @Test("Command held elsewhere, or the pointer on the bar without it, is not")
    func neitherAlone() {
        #expect(!IceBarArrangingRule.isArranging(isDragging: false, isCommandDown: true, isPointerOnBar: false))
        #expect(!IceBarArrangingRule.isArranging(isDragging: false, isCommandDown: false, isPointerOnBar: true))
        #expect(!IceBarArrangingRule.isArranging(isDragging: false, isCommandDown: false, isPointerOnBar: false))
    }

    @Test("after the arranging ended, the bar is still the owner's until it was read again")
    func rereadOwed() {
        #expect(IceBarArrangingRule.holdsBarForOwner(isArranging: false, arrangingEndedAt: 10, rereadAt: nil, now: 10.4))
        #expect(IceBarArrangingRule.holdsBarForOwner(isArranging: false, arrangingEndedAt: 10, rereadAt: 9.9, now: 11.5))
    }

    @Test("a pass that began after the arranging ended gives the bar back to Ice")
    func rereadDone() {
        #expect(!IceBarArrangingRule.holdsBarForOwner(isArranging: false, arrangingEndedAt: 10, rereadAt: 11.2, now: 11.3))
    }

    @Test("arranging itself always holds the bar; never arranged, nothing is owed")
    func arrangingAndNever() {
        #expect(IceBarArrangingRule.holdsBarForOwner(isArranging: true, arrangingEndedAt: nil, rereadAt: nil, now: 3))
        #expect(IceBarArrangingRule.holdsBarForOwner(isArranging: true, arrangingEndedAt: 1, rereadAt: 2, now: 3))
        #expect(!IceBarArrangingRule.holdsBarForOwner(isArranging: false, arrangingEndedAt: nil, rereadAt: nil, now: 3))
    }

    @Test("a re-read that never comes does not hold the bar for ever")
    func rereadLimit() {
        let end = 10.0
        #expect(IceBarArrangingRule.holdsBarForOwner(isArranging: false, arrangingEndedAt: end, rereadAt: nil, now: end + IceBarArrangingRule.rereadLimit - 0.1))
        #expect(!IceBarArrangingRule.holdsBarForOwner(isArranging: false, arrangingEndedAt: end, rereadAt: nil, now: end + IceBarArrangingRule.rereadLimit))
    }
}
