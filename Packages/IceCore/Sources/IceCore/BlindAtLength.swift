/// macOS 27.2 lists no status item that is pushed off the bar, Ice's own
/// lengthened divider included (plan 2026-11-15-blind-at-length, F2-F4;
/// MEASURED on 27.2.1, 26B131). A pass taken while Ice rests at a hiding
/// length then reads Ice's icon, no hidden divider and none of the members.
/// That is the system's normal answer, not an own read that failed, and it
/// says nothing of anything left of the divider.
public enum BlindAtLength {
    /// D1: whether `set` is such a pass. All of:
    /// - the pass is complete;
    /// - the own read lists Ice's icon and no hidden divider
    ///   (`.identifiersMissing` is exactly "no hidden divider", `ItemCatalog`);
    /// - `hasMembers`: the roster has members, so a trusted pass came before;
    /// - the hidden divider is enabled, and either it was at a hiding length
    ///   when the pass began and `holdsWrittenLength` (Ice's own state, not
    ///   Accessibility, says the hidden control item is in the bar at the
    ///   length the coordinator last wrote), or its state changed while the
    ///   pass ran. A pass that straddles a change (a length applied or
    ///   retired, or the states assigned again as the IceBar opens) read the
    ///   bar at two lengths: its missing divider says nothing, and blocking
    ///   on it retired the length each time the IceBar opened over a pass
    ///   (run 20261116-blind-5).
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
        guard hasMembers, hiddenDividerState.isEnabled else { return false }
        guard set.completeness == .complete, set.ownRead == .identifiersMissing, set.visibleControlItem != nil else {
            return false
        }
        if hiddenDividerState.changedDuringPass { return true }
        return !hiddenDividerState.isCollapsed && holdsWrittenLength
    }
}
