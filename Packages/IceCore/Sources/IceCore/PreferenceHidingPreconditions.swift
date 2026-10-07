/// What any hiding needs before Ice may change a length at all (plan
/// 2026-10-07-icebar-preference-hiding, D-c "blocked, not attempted" and
/// section 5 O1: "Any hiding, verified or not, first needs D-c's preconditions
/// a, b, c").

/// How Ice's icon failed to be right of its hidden divider (D-c a, S2).
public enum PreferenceHidingIconPlacement: Equatable, Sendable {
    /// The icon's reading is missing or not finite.
    case iconUnreadable
    /// The hidden divider's reading is missing, unusable or not finite.
    case dividerUnusable
    /// Both are readable and the icon's mid-x is not greater than the divider's.
    case iconLeftOfDivider
}

/// One failed precondition, with what the pane must name.
public enum PreferenceHidingBlockReason: Equatable, Sendable {
    /// (a) Ice's icon is not right of its hidden divider.
    case iceIconNotRightOfDivider(PreferenceHidingIconPlacement)
    /// (b) `Completeness` is not `.complete`.
    case discoveryIncomplete(Completeness)
    /// (b) `OwnReadStatus` is not `.ok`.
    case ownReadNotOk(OwnReadStatus)
    /// (c) `.positional` items left of the divider: the pane names them and
    /// asks the owner to move them right of it.
    case positionalItemsLeftOfDivider([PreferenceHidingBlocker])
}

public enum PreferenceHidingPreconditionResult: Equatable, Sendable {
    case ok
    /// Never empty: every failing reason, in the fixed order a, b, c.
    case blocked([PreferenceHidingBlockReason])

    public var isOk: Bool {
        self == .ok
    }

    public var reasons: [PreferenceHidingBlockReason] {
        switch self {
        case .ok: return []
        case .blocked(let reasons): return reasons
        }
    }
}

public enum PreferenceHidingPreconditions {
    /// - Parameters:
    ///   - iceIcon: the AX frame of Ice's visible control item; `nil` when it
    ///     could not be read.
    ///   - hiddenDivider: the hidden divider's reading; `nil` when the pass has
    ///     none. Compared by mid-x, as the plan's evidence records them
    ///     (P2: divider 1469, icon 1297.5).
    ///   - completeness, ownRead: the pass's verdicts. "Complete" means exactly
    ///     `Completeness.complete` AND `OwnReadStatus.ok`. `.incomplete` blocks
    ///     because a process whose read failed may own a status item Ice never
    ///     saw; a length would carry it off the bar and Ice could neither list
    ///     nor reach it. `.permissionDenied` blocks because nothing in the pass
    ///     can be trusted. An own read that is not `.ok` blocks because the
    ///     divider's boundary cannot be computed from it (`OwnReadStatus`).
    ///     Quarantined processes are not eligible in a pass, so they do not make
    ///     it incomplete (`Completeness`); that limit is the plan's (D-a:
    ///     "What Ice cannot see at all it cannot protect").
    ///   - blockers: `PreferenceHidingMembership.blockers`.
    public static func evaluate(
        iceIcon: BarRect?,
        hiddenDivider: DividerReading?,
        completeness: Completeness,
        ownRead: OwnReadStatus,
        blockers: [PreferenceHidingBlocker]
    ) -> PreferenceHidingPreconditionResult {
        var reasons = [PreferenceHidingBlockReason]()
        if let placement = misplacement(icon: iceIcon, divider: hiddenDivider) {
            reasons.append(.iceIconNotRightOfDivider(placement))
        }
        if completeness != .complete {
            reasons.append(.discoveryIncomplete(completeness))
        }
        if ownRead != .ok {
            reasons.append(.ownReadNotOk(ownRead))
        }
        if !blockers.isEmpty {
            reasons.append(.positionalItemsLeftOfDivider(blockers))
        }
        return reasons.isEmpty ? .ok : .blocked(reasons)
    }

    /// `nil` when the icon is strictly right of the divider.
    private static func misplacement(icon: BarRect?, divider: DividerReading?) -> PreferenceHidingIconPlacement? {
        guard let icon, icon.midX.isFinite else { return .iconUnreadable }
        guard let divider, divider.isUsable, let dividerFrame = divider.frame, dividerFrame.midX.isFinite else {
            return .dividerUnusable
        }
        return icon.midX > dividerFrame.midX ? nil : .iconLeftOfDivider
    }
}
