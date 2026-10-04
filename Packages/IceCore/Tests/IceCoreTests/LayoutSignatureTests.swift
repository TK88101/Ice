import Testing
@testable import IceCore

/// What a calibrated length is valid for (plan 2026-10-03-icebar-build, D1 and
/// section 9.2): any difference here sends the hidden section back to the bar.
@Suite("LayoutSignature")
struct LayoutSignatureTests {
    func signature(
        visible: [String] = ["v1"],
        hidden: [String] = ["h1", "h2"],
        alwaysHidden: [String] = [],
        frontmostPID: Int32? = 10,
        menuMaxX: Double? = 400,
        displayID: UInt32? = 1,
        spaceID: UInt64? = 7
    ) -> LayoutSignature {
        LayoutSignature(
            visible: visible,
            hidden: hidden,
            alwaysHidden: alwaysHidden,
            frontmostPID: frontmostPID,
            menuMaxX: menuMaxX,
            displayID: displayID,
            spaceID: spaceID
        )
    }

    @Test("the same layout gives the same signature")
    func sameLayoutIsEqual() {
        #expect(signature() == signature())
        #expect(signature().hashValue == signature().hashValue)
    }

    @Test("an item added, removed or moved to another section changes it")
    func itemSetChanges() {
        #expect(signature(hidden: ["h1"]) != signature())
        #expect(signature(hidden: ["h1", "h2", "h3"]) != signature())
        #expect(signature(visible: ["v1", "h2"], hidden: ["h1"]) != signature())
        #expect(signature(hidden: ["h1"], alwaysHidden: ["h2"]) != signature())
    }

    @Test("the order of items changes it")
    func orderChanges() {
        #expect(signature(hidden: ["h2", "h1"]) != signature())
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
