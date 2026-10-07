import Testing
@testable import IceCore

/// The T7 runner's reference gate must answer as Ice's own baseline will
/// (plan 2026-10-07-icebar-menu-frame-fix, section 11; Codex review: Ice's
/// always-hidden divider must not pass for a reference).
@Suite("ExternalReferenceCheck")
struct ExternalReferenceCheckTests {
    let own = OwnIdentifiers(visible: "Ice.ControlItem.Visible", hidden: "Ice.ControlItem.Hidden", alwaysHidden: "Ice.ControlItem.AlwaysHidden")

    func item(_ identifier: String, _ minX: Double, namespace: String = "com.example.a") -> DiscoveredItem {
        fixtureItem(namespace: namespace, identifier: identifier, pid: 600, frame: BarRect(minX: minX, minY: 0, width: 24, height: 33))
    }

    func ice(_ identifier: String, _ minX: Double) -> DiscoveredItem {
        item(identifier, minX, namespace: "com.jordanbaird.Ice")
    }

    @Test("a helper between Ice's divider and icon is the reference; Ice's items are found by identifier")
    func reference() {
        let check = ExternalReferenceCheck(items: [item("vz-t7-hidden2", 1100), ice(own.hidden, 1200), item("vz-t7-ref1", 1250), ice(own.visible, 1300)], own: own)
        #expect(check.dividerMinX == 1200)
        #expect(check.iceIconMidX == 1312)
        #expect(check.references.map(\.key.identifier) == ["vz-t7-ref1"])
        #expect(check.others.map(\.key.identifier) == ["vz-t7-hidden2", "vz-t7-ref1"])
    }

    @Test("Ice's always-hidden divider between them is not a reference")
    func alwaysHiddenIsNotAReference() {
        let check = ExternalReferenceCheck(items: [ice(own.hidden, 1200), ice(own.alwaysHidden, 1250), ice(own.visible, 1300)], own: own)
        #expect(check.references.isEmpty)
        #expect(check.others.isEmpty)
    }

    @Test("without Ice's hidden divider there is no reference")
    func noDivider() {
        let check = ExternalReferenceCheck(items: [item("vz-t7-ref1", 1250), ice(own.visible, 1300)], own: own)
        #expect(check.dividerMinX == nil)
        #expect(check.references.isEmpty)
    }
}
