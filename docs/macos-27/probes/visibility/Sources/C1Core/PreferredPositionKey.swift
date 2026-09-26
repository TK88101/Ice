/// Restated from `Ice/MenuBar/ControlItem/ControlItem.swift`'s own
/// `ControlItemDefaults.Key<CGFloat>.preferredPosition` (`"NSStatusItem
/// Preferred Position <autosaveName>"`) -- this probe package cannot
/// depend on the `Ice` app target, so the exact string format is restated
/// here, pure and tested, the same way `SpacerIdentifier`/`C1HelperRole`
/// (`C1Stage/StageC1.swift`) restate other Ice-adjacent constants this
/// package cannot import.
public enum PreferredPositionKey {
    public static func stringKey(autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }
}
