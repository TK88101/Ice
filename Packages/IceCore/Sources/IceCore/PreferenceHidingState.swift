/// The four states preference hiding can honestly be in (plan
/// 2026-10-07-icebar-preference-hiding, S3 D-c), and what changes them without
/// a new pixel check (D-e). The rule that derives a state from facts is
/// `PreferenceHidingStateRule`.

/// An event after which an earlier "verified" no longer describes the bar (D-e).
public enum PreferenceHidingLayoutChange: Equatable, Sendable {
    case frontmostAppChanged
    case menusCrossingNotch
    case itemsAdded
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

    /// D-e. The state after `change`, before any re-check:
    /// - `verifiedHidden` becomes `requestedNotVerified` pending the change;
    /// - `requestedNotVerified` keeps its reasons and carries the change as its
    ///   only pending one (an earlier pending change is replaced);
    /// - `blocked` and `visibleFailed` stay as they are until re-evaluated.
    /// No input produces a "show the section" result: no such state exists,
    /// so a long menu cannot become one.
    public func afterLayoutChange(_ change: PreferenceHidingLayoutChange) -> PreferenceHidingState {
        switch self {
        case .blocked, .visibleFailed:
            return self
        case .verifiedHidden:
            return .requestedNotVerified(reasons: [.layoutChangePending(change)])
        case .requestedNotVerified(let reasons):
            let kept = reasons.filter { if case .layoutChangePending = $0 { return false } else { return true } }
            return .requestedNotVerified(reasons: kept + [.layoutChangePending(change)])
        }
    }
}
