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
    /// Items came or went, and none of them can be hidden unlisted: every
    /// added item was read right of the visible boundary, none is a member,
    /// and the members did not grow (plan 2026-11-13-flash-on-item-change,
    /// D1). A pure removal is one.
    case visibleItemsChanged
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
        case .visibleItemsChanged, .frontmostAppChanged, .menuWidthChanged, .spaceChanged: false
        }
    }

    /// What changed from `old` to `new`, `nil` when they are equal. With
    /// several differences the first in the order above is named, so a
    /// structural one is never hidden behind a soft one.
    public static func between(_ old: LayoutSignature, _ new: LayoutSignature) -> PreferenceHidingLayoutChange? {
        if old.displayID != new.displayID { return .displayChanged }
        if old.items != new.items || old.members != new.members {
            return itemsChangeIsVisible(old, new) ? .visibleItemsChanged : .itemsChanged
        }
        if old.frontmostPID != new.frontmostPID { return .frontmostAppChanged }
        if old.menuMaxX != new.menuMaxX { return .menuWidthChanged }
        if old.spaceID != new.spaceID { return .spaceChanged }
        return nil
    }

    /// D1: the members are the old ones less some (in their order) whose items
    /// are gone too (a process that exited, `PreferenceHidingMembership.carried`),
    /// no added item is a member, and every added item was read right of the
    /// boundary.
    private static func itemsChangeIsVisible(_ old: LayoutSignature, _ new: LayoutSignature) -> Bool {
        let kept = Set(new.members)
        guard kept.isSubset(of: old.members), new.members == old.members.filter(kept.contains) else {
            return false
        }
        let removed = Set(old.items).subtracting(new.items)
        guard Set(old.members).subtracting(kept).isSubset(of: removed) else {
            return false
        }
        let added = Set(new.items).subtracting(old.items)
        return added.isDisjoint(with: old.members) && added.isDisjoint(with: new.members) && added.isSubset(of: new.visibleItems)
    }
}

/// What the state rule is told of the hidden section's length.
public enum PreferenceHidingLength: Equatable, Sendable {
    /// Standard length: nothing was checked at a length.
    case notApplied
    /// A length is set and seen to hide every member, and is being checked
    /// once more (plan 2026-10-19-verify-in-a-clean-burst, D2).
    case confirming
    /// Ice rests at a length; its checks speak of it.
    case applied
}

/// Why Ice applied (or may apply) a length and could not verify it.
public enum PreferenceHidingNotVerifiedReason: Equatable, Sendable {
    /// No length has been applied yet; nothing was checked.
    case lengthNotApplied
    /// A length is set and was seen to hide every member, in a burst Ice's
    /// own capture indicator may answer: it is checked once more first
    /// (plan 2026-10-19-verify-in-a-clean-burst, D2).
    case confirming
    /// The member set is empty. Nothing can be observed absent, so this is
    /// never `verifiedHidden`.
    case noMembers
    /// The detector found no reference item (`CheckSkipReason.noReference`).
    case noReference
    /// A capture was refused or failed (`SectionItemCheck.refusedAtBaseline`,
    /// `CheckSkipReason.captureFailed`).
    case captureRefused
    /// A member's check was refused because its baseline is older than
    /// `BaselineReuse.maxAge`: a baseline needs the section shown, and Ice
    /// does not show it only to refresh one (T3b design, stale reason).
    case baselineStale
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
