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
}
