import Testing
@testable import C1Core

/// Restated from `Ice/MenuBar/ControlItem/ControlItem.swift`'s own
/// `ControlItemDefaults.Key<CGFloat>.preferredPosition`
/// (`"NSStatusItem Preferred Position <autosaveName>"`) -- this probe
/// package cannot depend on the `Ice` app target, so the string format is
/// restated here, pure and tested, like `SpacerIdentifier`/`C1HelperRole`
/// elsewhere in this codebase.
@Suite("PreferredPositionKey")
struct PreferredPositionKeyTests {
    @Test("the exact string Ice's own ControlItemDefaults.Key would produce")
    func exactFormat() {
        #expect(PreferredPositionKey.stringKey(autosaveName: "vz-c1-target") == "NSStatusItem Preferred Position vz-c1-target")
    }

    @Test("two different autosave names never collide")
    func distinctNamesDistinctKeys() {
        #expect(PreferredPositionKey.stringKey(autosaveName: "vz-c1-spacer") != PreferredPositionKey.stringKey(autosaveName: "vz-c1-protected"))
    }
}
