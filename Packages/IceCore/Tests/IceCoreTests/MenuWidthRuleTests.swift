import Testing
@testable import IceCore

/// The long-menu rule (plan 2026-10-03-icebar-build, D1 and section 8 T2).
/// Notch at 771.5 pt as on the owner's display (T0 geometry).
@Suite("MenuWidthRule")
struct MenuWidthRuleTests {
    let notchMinX = 771.5

    @Test("a short menu fits", arguments: [72.0, 440, 758])
    func shortMenuFits(menuMaxX: Double) {
        #expect(MenuWidthRule.verdict(menuMaxX: menuMaxX, notchMinX: notchMinX) == .fits)
    }

    @Test("a menu ending exactly at the notch's edge fits")
    func edgeFits() {
        #expect(MenuWidthRule.verdict(menuMaxX: notchMinX, notchMinX: notchMinX) == .fits)
    }

    @Test("a menu one point over the edge crosses the notch")
    func overEdgeCrosses() {
        #expect(MenuWidthRule.verdict(menuMaxX: notchMinX + 1, notchMinX: notchMinX) == .crossesNotch)
    }

    @Test("a missing menu or notch is unreadable")
    func missingIsUnreadable() {
        #expect(MenuWidthRule.verdict(menuMaxX: nil, notchMinX: notchMinX) == .unreadable)
        #expect(MenuWidthRule.verdict(menuMaxX: 400, notchMinX: nil) == .unreadable)
        #expect(MenuWidthRule.verdict(menuMaxX: nil, notchMinX: nil) == .unreadable)
    }

    @Test("a non-finite value is unreadable", arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteIsUnreadable(value: Double) {
        #expect(MenuWidthRule.verdict(menuMaxX: value, notchMinX: notchMinX) == .unreadable)
        #expect(MenuWidthRule.verdict(menuMaxX: 400, notchMinX: value) == .unreadable)
    }
}
