/// macOS 27.2 lists no status item that is pushed off the bar, Ice's own
/// lengthened divider included (plan 2026-11-15-blind-at-length, F2-F4;
/// MEASURED on 27.2.1, 26B131). A pass taken while Ice rests at a hiding
/// length then reads Ice's icon, no hidden divider and none of the members.
/// That is the system's normal answer, not an own read that failed, and it
/// says nothing of anything left of the divider.
public enum BlindAtLength {
    /// D1: whether `set` is such a pass. All of:
    /// - `holdsWrittenLength`: Ice's own state, not Accessibility, says the
    ///   hidden control item exists, is visible and has the length the
    ///   coordinator last wrote;
    /// - the hidden divider's state is enabled, not collapsed, and did not
    ///   change during the pass;
    /// - the pass is complete;
    /// - the own read lists Ice's icon and no hidden divider
    ///   (`.identifiersMissing` is exactly "no hidden divider", `ItemCatalog`);
    /// - `hasMembers`: the roster has members, so a trusted pass came before.
    ///
    /// Decided by what is read, never by a system version: where the divider
    /// stays listed at a length (27.0, 27.1) the own read is `.ok` and no
    /// pass is blind.
    public static func holds(
        set: DiscoveredItemSet,
        hiddenDividerState: DividerState,
        holdsWrittenLength: Bool,
        hasMembers: Bool
    ) -> Bool {
        guard holdsWrittenLength, hasMembers else { return false }
        guard hiddenDividerState.isEnabled, !hiddenDividerState.isCollapsed, !hiddenDividerState.changedDuringPass else {
            return false
        }
        return set.completeness == .complete && set.ownRead == .identifiersMissing && set.visibleControlItem != nil
    }
}
