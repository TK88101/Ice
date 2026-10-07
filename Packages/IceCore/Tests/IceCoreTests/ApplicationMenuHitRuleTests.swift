import Testing
@testable import IceCore

/// Whether a click is on the application menu (plan
/// 2026-10-07-icebar-menu-frame-fix, F2b): the containment test of
/// `HIDEventManager.isMouseInsideApplicationMenu`, the menu's frame widened to
/// the screen's left edge. With no frame (the reader's nil before the fix) a
/// click on the menu counted as empty bar space.
@Suite("ApplicationMenuHitRule")
struct ApplicationMenuHitRuleTests {
    /// Terminal's menus on the owner's display: Apple menu from 10, last menu
    /// ending at 420; the bar 0-32.
    let menu = BarRect(minX: 10, minY: 0, width: 410, height: 32)

    func inside(x: Double, y: Double = 12, menu: BarRect?, screenMinX: Double = 0) -> Bool {
        ApplicationMenuHitRule.contains(x: x, y: y, menuFrame: menu, screenMinX: screenMinX)
    }

    @Test("no frame: nothing is on the menu, so a click there is empty bar space")
    func noFrame() {
        #expect(!inside(x: 200, menu: nil))
    }

    @Test("a point on the Shell menu is on the menu")
    func shellMenu() {
        #expect(inside(x: 200, menu: menu))
    }

    /// x = 4 is left of the menu's own minX (10): only the widening to the
    /// screen's left edge puts it on the menu.
    @Test("between the screen's left edge and the menu's minX: on the menu through the widening")
    func widening() {
        #expect(inside(x: 4, menu: menu))
    }

    @Test("the widening follows the screen's own left edge")
    func secondScreen() {
        let right = BarRect(minX: 1738, minY: 0, width: 300, height: 24)
        #expect(inside(x: 1730, menu: right, screenMinX: 1728))
        #expect(!inside(x: 1720, menu: right, screenMinX: 1728))
    }

    @Test("CGRect's half-open edges: maxX and maxY are outside, the left edge and minY inside")
    func edges() {
        #expect(!inside(x: 420, menu: menu))
        #expect(inside(x: 419.5, menu: menu))
        #expect(inside(x: 0, menu: menu))
        #expect(inside(x: 200, y: 0, menu: menu))
        #expect(!inside(x: 200, y: 32, menu: menu))
        #expect(!inside(x: 200, y: -1, menu: menu))
    }
}
