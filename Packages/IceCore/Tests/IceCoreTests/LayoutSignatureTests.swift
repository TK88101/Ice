import Testing
@testable import IceCore

/// The layout a hiding length was applied in (plan 2026-10-07-icebar-preference-
/// hiding, T3b design): every item a pass read, the roster, and what the bar is
/// shown with. `PreferenceHidingLayoutChange.between` names the difference.
@Suite("LayoutSignature")
struct LayoutSignatureTests {
    func signature(
        items: [String] = ["v1", "h1", "h2"],
        members: [String] = ["h1", "h2"],
        frontmostPID: Int32? = 10,
        menuMaxX: Double? = 400,
        displayID: UInt32? = 1,
        spaceID: UInt64? = 7
    ) -> LayoutSignature {
        fixtureSignature(items: items, members: members, frontmostPID: frontmostPID, menuMaxX: menuMaxX, displayID: displayID, spaceID: spaceID)
    }

    @Test("the same layout gives the same signature")
    func sameLayoutIsEqual() {
        #expect(signature() == signature())
        #expect(signature().hashValue == signature().hashValue)
    }

    @Test("an item added or removed, or a member added or released, changes it")
    func itemSetChanges() {
        #expect(signature(items: ["v1", "h1"]) != signature())
        #expect(signature(items: ["v1", "h1", "h2", "h3"]) != signature())
        #expect(signature(members: ["h1"]) != signature())
    }

    @Test("the roster's order changes it")
    func orderChanges() {
        #expect(signature(members: ["h2", "h1"]) != signature())
    }

    @Test("the frontmost app, the display and the space change it")
    func contextChanges() {
        #expect(signature(frontmostPID: 11) != signature())
        #expect(signature(displayID: 2) != signature())
        #expect(signature(spaceID: 8) != signature())
    }

    @Test("the menu's right edge counts to the whole point")
    func menuEdgeIsRounded() {
        #expect(signature(menuMaxX: 400.3) == signature(menuMaxX: 399.6))
        #expect(signature(menuMaxX: 401) != signature())
        #expect(signature(menuMaxX: 400.3).menuMaxX == 400)
    }

    @Test("an unreadable menu edge is its own value", arguments: [nil, Double.nan, Double.infinity])
    func unreadableMenuEdge(menuMaxX: Double?) {
        #expect(signature(menuMaxX: menuMaxX).menuMaxX == nil)
        #expect(signature(menuMaxX: menuMaxX) != signature())
    }
}
