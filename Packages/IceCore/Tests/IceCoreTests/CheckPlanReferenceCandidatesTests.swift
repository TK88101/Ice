import Testing
@testable import IceCore

/// D14's geometric filter on its own (plan 2026-10-07-icebar-menu-frame-fix,
/// section 11): what `CheckPlan.make` accepts as a reference candidate, so
/// that the T7 runner can ask the same question of a live bar.
@Suite("CheckPlan.geometricReferenceCandidates")
struct CheckPlanReferenceCandidatesTests {
    func item(_ identifier: String, _ minX: Double, basis: IdentityBasis = .declared, position: ItemPosition = .onBar) -> DiscoveredItem {
        fixtureItem(identifier: identifier, pid: 600, basis: basis, frame: BarRect(minX: minX, minY: 0, width: 24, height: 33), position: position)
    }

    func candidates(_ items: [DiscoveredItem], iceIconMidX: Double? = 1300) -> [String] {
        CheckPlan.geometricReferenceCandidates(items: items, dividerMinX: 1200, iceIconMidX: iceIconMidX).map(\.key.identifier)
    }

    @Test("an item between the divider and Ice's icon is a candidate, left to right")
    func between() {
        #expect(candidates([item("b", 1260), item("a", 1220)]) == ["a", "b"])
    }

    @Test("left of the divider (a hidden member) or right of Ice's icon is not")
    func outside() {
        #expect(candidates([item("member", 1100), item("right", 1320)]).isEmpty)
    }

    @Test("a positional or off-bar item is not")
    func unusable() {
        #expect(candidates([item("p", 1240, basis: .positional), item("parked", 1240, position: .parked)]).isEmpty)
    }

    @Test("without Ice's icon everything right of the divider is a candidate")
    func noIcon() {
        #expect(candidates([item("a", 1240), item("far", 1500)], iceIconMidX: nil) == ["a", "far"])
    }

    @Test("an item with no frame is not")
    func noFrame() {
        let frameless = fixtureItem(identifier: "x", pid: 600, frame: nil, position: .onBar)
        #expect(candidates([frameless]).isEmpty)
    }
}
