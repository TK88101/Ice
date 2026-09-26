/// Amendment v8, "Placement gate": section 2's premise -- "each new item
/// lands at the left end" -- is false on the owner's bar (a fourth
/// cross-check found 1-3 owner items drawn left of the helpers in every
/// recorded run there). Right after the launches, before any baseline and
/// before any `length`, discovery must show Target, the spacer and
/// Protected each left of every on-bar owner item; otherwise the run ends
/// INCONCLUSIVE ("helpers not leftmost: N owner items left"), never a
/// safety stop -- this is not a C1 failure, it is this bar not supporting
/// C1's own geometry yet (Amendment v8's own wording).
public enum PlacementGate {
    /// `helperMinXs`: Target's, the spacer's and Protected's own AX-frame
    /// minX (whatever order; only their rightmost extent matters here --
    /// the internal Target/spacer/Protected order is `C1Discoverer`'s and
    /// `PreflightOrderCheck`'s own job, not this gate's). `onBarOwnerMinXs`:
    /// every *on-bar* owner item's minX (parked items already excluded by
    /// the caller, per Amendment v8's own first bullet -- this gate only
    /// ever sees items that count).
    ///
    /// `nil` when every on-bar owner item sits at or right of the
    /// rightmost helper (or there are no on-bar owner items, or no owner
    /// items are left of a helper set that is present); otherwise the
    /// count of on-bar owner items strictly left of it. No helpers at all
    /// (none launched, or none with a frame) fails closed: every on-bar
    /// owner item counts as left of an absent rightmost helper.
    public static func check(helperMinXs: [Double], onBarOwnerMinXs: [Double]) -> Int? {
        guard let rightmostHelper = helperMinXs.max() else {
            return onBarOwnerMinXs.isEmpty ? nil : onBarOwnerMinXs.count
        }
        let leftOfHelpers = onBarOwnerMinXs.filter { $0 < rightmostHelper }
        return leftOfHelpers.isEmpty ? nil : leftOfHelpers.count
    }
}
