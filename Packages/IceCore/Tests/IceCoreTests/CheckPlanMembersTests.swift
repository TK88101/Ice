import Testing
@testable import IceCore

/// Section membership is decided once at prepare time (residuals plan R1),
/// and the third-party items plus Ice's icon are named once (R2). R3's D14
/// correction is pinned where it acts, in `HidingVerificationIconBoundTests`.
@Suite("CheckPlan: section members and listed items")
struct CheckPlanMembersTests {
    private func item(identifier: String, pid: Int32, minX: Double, basis: IdentityBasis = .declared, position: ItemPosition = .onBar, isSelf: Bool = false) -> DiscoveredItem {
        fixtureItem(namespace: isSelf ? "IceApp" : "com.example.a", identifier: identifier, pid: pid, childIndex: basis == .positional ? 0 : nil, basis: basis, frame: barFrame(minX: minX, width: 14), position: position, isSelf: isSelf)
    }

    private func set(items: [DiscoveredItem], visibleControlItem: DiscoveredItem? = nil) -> DiscoveredItemSet {
        fixtureSet(items: items, visibleControlItem: visibleControlItem)
    }

    @Test("section members: every item mapped to a requested section, parked, stacked and positional included, in set order")
    func sectionMembersIncludeEveryMappedItem() {
        let parked = item(identifier: "parked", pid: 1, minX: 900, position: .parked)
        let stacked = item(identifier: "stacked", pid: 2, minX: 910, position: .stacked)
        let positional = item(identifier: "pos", pid: 3, minX: 920, basis: .positional)
        let plain = item(identifier: "plain", pid: 4, minX: 930)
        let otherSection = item(identifier: "other", pid: 5, minX: 940)
        let unmapped = item(identifier: "unmapped", pid: 6, minX: 950)
        let s = set(items: [parked, stacked, positional, plain, otherSection, unmapped])
        let map: [TagKey: ItemSection] = [
            parked.tagKey: .hidden, stacked.tagKey: .hidden, positional.tagKey: .hidden,
            plain.tagKey: .alwaysHidden, otherSection.tagKey: .visible,
        ]

        let members = CheckPlan.sectionMembers(set: s, sectionMap: map, sections: [.hidden, .alwaysHidden])

        #expect(members.map(\.key) == [parked.key, stacked.key, positional.key, plain.key])
    }

    @Test("section members: nothing requested -> empty")
    func sectionMembersOfNoSectionsIsEmpty() {
        let plain = item(identifier: "plain", pid: 4, minX: 930)
        #expect(CheckPlan.sectionMembers(set: set(items: [plain]), sectionMap: [plain.tagKey: .hidden], sections: []).isEmpty)
    }

    @Test("listed items: the third-party items, then Ice's icon when the set has it")
    func listedItemsAppendsTheIcon() {
        let a = item(identifier: "a", pid: 1, minX: 900)
        let icon = item(identifier: "gear", pid: 900, minX: 1200, isSelf: true)
        #expect(set(items: [a], visibleControlItem: icon).listedItems.map(\.key) == [a.key, icon.key])
        #expect(set(items: [a]).listedItems.map(\.key) == [a.key])
    }
}
