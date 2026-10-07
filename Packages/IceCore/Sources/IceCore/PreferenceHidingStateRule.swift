/// Derives the four states of plan 2026-10-07-icebar-preference-hiding D-c
/// from the preconditions, the membership, whether a length was applied and
/// the per-member pixel checks.

public enum PreferenceHidingStateRule {
    /// Order of decision:
    /// 1. A failed precondition is `blocked`, whatever else is true. `blocked`
    ///    means "Ice changed no length" (D-c), so when it comes with
    ///    `lengthApplied` true the caller must first retire the length (back to
    ///    standard) and only then present `blocked`; the rule itself cannot
    ///    revert anything.
    /// 2. With a length applied, a member whose check is `.stillDrawn` is
    ///    `visibleFailed`, regardless of caps and pending changes.
    /// 3. Otherwise every reason that stops short of proof is collected, and
    ///    none at all means `verifiedHidden`: a length applied, a non-empty
    ///    member set, every member ready and observed `hidden(folded: false)`,
    ///    no pending layout change.
    ///
    /// With no length applied, `checks` are not consulted: whatever they say
    /// describes a bar Ice has not changed. An empty member set is
    /// `requestedNotVerified([.noMembers])`: there is nothing to observe, and
    /// the plan has no fifth state for it.
    ///
    /// `checks` are matched to members by key. A check for a key that is not a
    /// member is ignored (a non-member's pixels say nothing about the roster),
    /// as is a check for a member with no key (one missing from the read).
    /// D-b ("`«` is recorded, never a trigger") holds by construction: the rule
    /// has no chevron input, so the reading cannot change the state. The state
    /// machine records it (T3b). Lengths are not an input either: this rule
    /// neither knows nor ships one (D-d).
    ///
    /// D-e (layout changes: frontmost app, menus crossing the notch, items
    /// added): the caller keeps the requested member set and calls this again
    /// with `pendingLayoutChange:`. A would-be `verifiedHidden` then drops to
    /// `requestedNotVerified` carrying `layoutChangePending(change)` among its
    /// reasons until the re-check clears it; `blocked` and `visibleFailed` stay
    /// what their own inputs say. There is no state that means "show the
    /// section", so a long menu cannot become one: nothing is shown merely
    /// because a menu is long.
    public static func evaluate(
        preconditions: PreferenceHidingPreconditionResult,
        membership: PreferenceHidingMembership,
        lengthApplied: Bool,
        checks: [ItemKey: SectionItemCheck],
        pendingLayoutChange: PreferenceHidingLayoutChange?
    ) -> PreferenceHidingState {
        if case .blocked(let reasons) = preconditions {
            return .blocked(reasons: reasons)
        }
        let memberChecks = membership.members.map { member in (member: member, check: member.key.flatMap { checks[$0] }) }
        let drawn = lengthApplied ? memberChecks.filter { $0.check == .checked(.stillDrawn) }.map(\.member.tag) : []
        if !drawn.isEmpty {
            return .visibleFailed(drawn: drawn)
        }
        let reasons = notVerifiedReasons(
            membership: membership, lengthApplied: lengthApplied,
            memberChecks: memberChecks, pendingLayoutChange: pendingLayoutChange
        )
        return reasons.isEmpty ? .verifiedHidden : .requestedNotVerified(reasons: reasons)
    }

    private static func notVerifiedReasons(
        membership: PreferenceHidingMembership,
        lengthApplied: Bool,
        memberChecks: [(member: PreferenceHidingMember, check: SectionItemCheck?)],
        pendingLayoutChange: PreferenceHidingLayoutChange?
    ) -> [PreferenceHidingNotVerifiedReason] {
        var reasons = [PreferenceHidingNotVerifiedReason]()
        if !lengthApplied { reasons.append(.lengthNotApplied) }
        if membership.members.isEmpty { reasons.append(.noMembers) }
        if lengthApplied {
            reasons += checkReasons(memberChecks)
        }
        let stale = membership.staleMembers.map(\.tag)
        if !stale.isEmpty { reasons.append(.staleMembers(stale)) }
        let stacked = membership.stackedMembers.map(\.tag)
        if !stacked.isEmpty { reasons.append(.stackedMembers(stacked)) }
        if let pendingLayoutChange { reasons.append(.layoutChangePending(pendingLayoutChange)) }
        return reasons
    }

    /// Reasons that come from the checks themselves. A fold is its own reason,
    /// not an unchecked member; stale and stacked members are named by their own
    /// reasons and never counted as unchecked.
    private static func checkReasons(
        _ memberChecks: [(member: PreferenceHidingMember, check: SectionItemCheck?)]
    ) -> [PreferenceHidingNotVerifiedReason] {
        var reasons = [PreferenceHidingNotVerifiedReason]()
        let checks = memberChecks.compactMap(\.check)
        if checks.contains(.skipped(.noReference)) { reasons.append(.noReference) }
        if checks.contains(where: isCaptureRefusal) { reasons.append(.captureRefused) }
        let folded = memberChecks.filter { $0.check == .checked(.hidden(folded: true)) }.map(\.member.tag)
        if !folded.isEmpty { reasons.append(.foldSeen(folded)) }
        let concluded: [SectionItemCheck] = [.checked(.hidden(folded: false)), .checked(.hidden(folded: true))]
        let unchecked = memberChecks
            .filter { $0.member.condition == .ready && !($0.check.map(concluded.contains) ?? false) }
            .map(\.member.tag)
        if !unchecked.isEmpty { reasons.append(.membersUnchecked(unchecked)) }
        return reasons
    }

    private static func isCaptureRefusal(_ check: SectionItemCheck) -> Bool {
        switch check {
        case .refusedAtBaseline, .skipped(.captureFailed): return true
        default: return false
        }
    }
}
