/// The four states preference hiding can honestly be in (plan
/// 2026-10-07-icebar-preference-hiding, S3 D-c), and what changes them without
/// a new pixel check (D-e, documented on `PreferenceHidingStateRule.evaluate`).
/// The rule that derives a state from facts is `PreferenceHidingStateRule`.

/// A difference after which an earlier "verified" no longer describes the bar
/// (D-e). Derived from two layout signatures by `between`, never classified by
/// hand; the cases are the signature's fields (it has no notch, and cannot
/// tell an item added from one removed).
public enum PreferenceHidingLayoutChange: Equatable, Sendable {
    case displayChanged
    case itemsChanged
    case frontmostAppChanged
    case menuWidthChanged
    case spaceChanged

    /// Whether the roster itself may be wrong after it: another display, or
    /// another set of items. The roster advances only at standard length, so
    /// such a change retires an applied length; after any other the length
    /// stays and only the checks are owed again. A Space that shows other
    /// items differs in the item lists; its id alone says nothing of them.
    public var isStructural: Bool {
        switch self {
        case .displayChanged, .itemsChanged: true
        case .frontmostAppChanged, .menuWidthChanged, .spaceChanged: false
        }
    }

    /// What changed from `old` to `new`, `nil` when they are equal. With
    /// several differences the first in the order above is named, so a
    /// structural one is never hidden behind a soft one.
    public static func between(_ old: LayoutSignature, _ new: LayoutSignature) -> PreferenceHidingLayoutChange? {
        if old.displayID != new.displayID { return .displayChanged }
        if old.visible != new.visible || old.hidden != new.hidden || old.alwaysHidden != new.alwaysHidden { return .itemsChanged }
        if old.frontmostPID != new.frontmostPID { return .frontmostAppChanged }
        if old.menuMaxX != new.menuMaxX { return .menuWidthChanged }
        if old.spaceID != new.spaceID { return .spaceChanged }
        return nil
    }
}

/// Why Ice applied (or may apply) a length and could not verify it.
public enum PreferenceHidingNotVerifiedReason: Equatable, Sendable {
    /// No length has been applied yet; nothing was checked.
    case lengthNotApplied
    /// The member set is empty. Nothing can be observed absent, so this is
    /// never `verifiedHidden`.
    case noMembers
    /// The detector found no reference item (`CheckSkipReason.noReference`).
    case noReference
    /// A capture was refused or failed (`SectionItemCheck.refusedAtBaseline`,
    /// `CheckSkipReason.captureFailed`).
    case captureRefused
    /// Members that are stale (D-a).
    case staleMembers([TagKey])
    /// Members that are stacked; the pixel check skips them (D-a).
    case stackedMembers([TagKey])
    /// Members whose check saw the fold go up with them. D-d: not a failure,
    /// not proof of absence either.
    case foldSeen([TagKey])
    /// Ready members without a conclusive "absent" check: no check at all, or
    /// one that is `unverifiable`, skipped for another reason, or refused.
    case membersUnchecked([TagKey])
    /// A layout change happened since the last check (D-e).
    case layoutChangePending(PreferenceHidingLayoutChange)
}

public enum PreferenceHidingState: Equatable, Sendable {
    /// Ice changed no length and offers no IceBar (D-c; scenarios 10 and 13).
    case blocked(reasons: [PreferenceHidingBlockReason])
    /// Every member was observed absent and nothing caps the state.
    case verifiedHidden
    /// Ice applied, or may apply, a length and could not check (O1).
    case requestedNotVerified(reasons: [PreferenceHidingNotVerifiedReason])
    /// A member was observed drawn; Ice does not claim to hide.
    case visibleFailed(drawn: [TagKey])

    /// False only when blocked (D-c).
    public var isIceBarOffered: Bool {
        if case .blocked = self { return false }
        return true
    }

    /// True only for `verifiedHidden`: "never a lab success" for the rest (O1).
    public var countsAsLabSuccess: Bool {
        self == .verifiedHidden
    }
}
