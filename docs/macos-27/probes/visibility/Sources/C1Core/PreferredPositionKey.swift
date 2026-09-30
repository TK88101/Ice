/// Restated from `Ice/MenuBar/ControlItem/ControlItem.swift`'s own
/// `ControlItemDefaults.Key<CGFloat>.preferredPosition` (`"NSStatusItem
/// Preferred Position <autosaveName>"`) -- this probe package cannot
/// depend on the `Ice` app target, so the exact string format is restated
/// here, pure and tested, the same way `SpacerIdentifier`/`C1HelperRole`
/// (`C1Stage/StageC1.swift`) restate other Ice-adjacent constants this
/// package cannot import.
public enum PreferredPositionKey {
    /// Amendment v9, "Sort-key values": the prefix a read-only owner-domain
    /// scan matches against (`C1OwnerPreferenceScanning`), rather than one
    /// specific `autosaveName` -- an owner item's own autosave name is
    /// never known ahead of the scan, only that macOS names every such key
    /// this way.
    public static let scanPrefix = "NSStatusItem Preferred Position "

    public static func stringKey(autosaveName: String) -> String {
        scanPrefix + autosaveName
    }
}
