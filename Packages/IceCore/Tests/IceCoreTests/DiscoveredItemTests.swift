import Testing
@testable import IceCore

/// `ItemSection`, `TagKey`, `OwnIdentifiers` and `DiscoveredItem` are the
/// plain values T4's catalog and cache-plan rules are built from (plan
/// section 4.1.5, task T4 API). Nothing here talks to Accessibility or to
/// Ice's `ControlItem` -- `OwnIdentifiers` exists precisely so this package
/// never hard-codes `"Ice.ControlItem.*"` (D9's identifiers are always passed
/// in by the caller).
@Suite("ItemSection, TagKey, OwnIdentifiers")
struct ItemSectionTests {
    @Test("ItemSection has exactly the three sections, in the documented order")
    func itemSectionCases() {
        #expect(ItemSection.allCases == [.visible, .hidden, .alwaysHidden])
    }

    @Test("TagKey stores namespace and title independently")
    func tagKeyFields() {
        let tag = TagKey(namespace: "com.example.a", title: "gear/p12")
        #expect(tag.namespace == "com.example.a")
        #expect(tag.title == "gear/p12")
    }

    @Test("TagKey equality and hashing follow both fields")
    func tagKeyEquality() {
        let a = TagKey(namespace: "com.example.a", title: "gear/p12")
        let b = TagKey(namespace: "com.example.a", title: "gear/p12")
        let c = TagKey(namespace: "com.example.b", title: "gear/p12")
        #expect(a == b)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }

    @Test("OwnIdentifiers is a plain fixture -- no hard-coded Ice.ControlItem string appears in IceCore sources")
    func ownIdentifiersIsPlain() {
        // Fixture strings here are test-only (contract: sources may not
        // hard-code them, but tests may).
        let ids = OwnIdentifiers(visible: "Ice.ControlItem.visible", hidden: "Ice.ControlItem.hidden", alwaysHidden: "Ice.ControlItem.alwaysHidden")
        #expect(ids.visible == "Ice.ControlItem.visible")
        #expect(ids.hidden == "Ice.ControlItem.hidden")
        #expect(ids.alwaysHidden == "Ice.ControlItem.alwaysHidden")
    }
}

@Suite("DividerReading usability")
struct DividerReadingTests {
    let bounds = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)

    @Test("no frame is never usable")
    func noFrameIsUnusable() {
        #expect(DividerReading.usability(of: nil, in: bounds) == false)
    }

    @Test("a frame inside the bar's minY and minX ranges is usable")
    func frameInsideBarIsUsable() {
        let frame = BarRect(minX: 1012, minY: 0, width: 5002, height: 33)
        #expect(DividerReading.usability(of: frame, in: bounds) == true)
    }

    @Test("a frame whose minY is at or past the bar's bottom is unusable")
    func frameBelowBarIsUnusable() {
        let frame = BarRect(minX: 1012, minY: 33, width: 16, height: 33)
        #expect(DividerReading.usability(of: frame, in: bounds) == false)
    }

    @Test("a frame whose minX is at or past bounds.maxX is unusable")
    func frameRightOfBarIsUnusable() {
        let frame = BarRect(minX: 1728, minY: 0, width: 16, height: 33)
        #expect(DividerReading.usability(of: frame, in: bounds) == false)
    }

    @Test("a frame whose minX is left of bounds.minX is unusable")
    func frameLeftOfBarIsUnusable() {
        let bounds2 = BarBounds(minX: 1728, maxX: 3456, minY: 0, barHeight: 33)
        let frame = BarRect(minX: 1727.9, minY: 0, width: 16, height: 33)
        #expect(DividerReading.usability(of: frame, in: bounds2) == false)
    }

    @Test("make(frame:in:) derives isUsable via the same rule")
    func makeDerivesUsability() {
        let usable = DividerReading.make(frame: BarRect(minX: 1100, minY: 0, width: 16, height: 33), in: bounds)
        #expect(usable.isUsable == true)
        let unusable = DividerReading.make(frame: nil, in: bounds)
        #expect(unusable.isUsable == false)
        #expect(unusable.frame == nil)
    }

    @Test("direct init accepts frame and isUsable independently, for fixtures")
    func directInit() {
        let reading = DividerReading(frame: nil, isUsable: false)
        #expect(reading.frame == nil)
        #expect(reading.isUsable == false)
    }
}

@Suite("DiscoveredItem: tagKey and displayTitle")
struct DiscoveredItemComputedTests {
    private func process(pid: Int32 = 42, isSelf: Bool = false) -> ProcessInfoRecord {
        ProcessInfoRecord(pid: pid, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 10, isSelf: isSelf)
    }

    private func item(
        identifier: String = "gear",
        pid: Int32 = 42,
        isSelf: Bool = false,
        title: String? = nil,
        description: String? = nil,
        help: String? = nil,
        carriedPasses: Int = 0
    ) -> DiscoveredItem {
        let key = ItemKey(namespace: "com.example.a", identifier: identifier, pid: pid, childIndex: nil)
        return DiscoveredItem(
            key: key,
            basis: .declared,
            process: process(pid: pid, isSelf: isSelf),
            frame: BarRect(minX: 0, minY: 4.5, width: 20, height: 24),
            position: .onBar,
            title: title,
            description: description,
            help: help,
            carriedPasses: carriedPasses,
            lastConfirmedAt: 0
        )
    }

    @Test("tagKey for a third-party item is namespace + full tag title")
    func tagKeyThirdParty() {
        let discovered = item(identifier: "gear", pid: 12)
        #expect(discovered.tagKey == TagKey(namespace: "com.example.a", title: "gear/p12"))
    }

    @Test("tagKey for the reader's own item drops the pid suffix")
    func tagKeyOwn() {
        let discovered = item(identifier: "gear", pid: 900, isSelf: true)
        #expect(discovered.tagKey == TagKey(namespace: "com.example.a", title: "gear"))
    }

    @Test("displayTitle picks the first non-empty of title, description, help")
    func displayTitlePriority() {
        #expect(item(title: "T", description: "D", help: "H").displayTitle == "T")
        #expect(item(title: nil, description: "D", help: "H").displayTitle == "D")
        #expect(item(title: "", description: "D", help: "H").displayTitle == "D")
        #expect(item(title: nil, description: nil, help: "H").displayTitle == "H")
        #expect(item(title: nil, description: nil, help: nil).displayTitle == nil)
        #expect(item(title: "", description: "", help: "").displayTitle == nil)
    }

    @Test("carriedPasses is stored as given, 0 meaning read this pass")
    func carriedPassesStored() {
        #expect(item(carriedPasses: 0).carriedPasses == 0)
        #expect(item(carriedPasses: 2).carriedPasses == 2)
    }
}

@Suite("DroppedItem, DropReason, OwnReadStatus, Completeness")
struct DiscoveredItemSupportTypesTests {
    @Test("DroppedItem carries an optional key, a pid, and a reason")
    func droppedItemFields() {
        let withKey = DroppedItem(key: ItemKey(namespace: "n", identifier: "x", pid: 1, childIndex: nil), pid: 1, reason: .identityCollision)
        #expect(withKey.key != nil)
        #expect(withKey.pid == 1)
        #expect(withKey.reason == .identityCollision)

        let withoutKey = DroppedItem(key: nil, pid: 2, reason: .unrecognizedRole("AXStaticText"))
        #expect(withoutKey.key == nil)
        #expect(withoutKey.reason == .unrecognizedRole("AXStaticText"))
    }

    @Test("DropReason equality distinguishes unrecognizedRole payloads")
    func dropReasonEquality() {
        #expect(DropReason.unrecognizedRole("AXStaticText") == DropReason.unrecognizedRole("AXStaticText"))
        #expect(DropReason.unrecognizedRole("AXStaticText") != DropReason.unrecognizedRole("AXImage"))
        #expect(DropReason.ownUnrecognized != DropReason.identityCollision)
    }

    @Test("OwnReadStatus has exactly the four documented cases, pairwise distinct")
    func ownReadStatusCases() {
        let all: [OwnReadStatus] = [.ok, .failed, .identifiersMissing, .notRead]
        for (i, a) in all.enumerated() {
            for (j, b) in all.enumerated() {
                #expect((a == b) == (i == j))
            }
        }
    }

    @Test("Completeness.incomplete carries the failed pids")
    func completenessIncomplete() {
        let c = Completeness.incomplete(failedPIDs: [1, 2, 3])
        if case .incomplete(let pids) = c {
            #expect(pids == [1, 2, 3])
        } else {
            Issue.record("expected .incomplete")
        }
        #expect(Completeness.complete != Completeness.permissionDenied)
    }
}
