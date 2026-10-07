/// What any hiding needs before Ice may change a length at all (plan
/// 2026-10-07-icebar-preference-hiding, D-c "blocked, not attempted" and
/// section 5 O1: "Any hiding, verified or not, first needs D-c's preconditions
/// a, b, c").

/// How Ice's icon failed to be right of its hidden divider (D-c a, S2).
public enum PreferenceHidingIconPlacement: Equatable, Sendable {
    /// The icon's reading is missing or a component of its frame is not finite.
    case iconUnreadable
    /// The hidden divider's reading is missing, unusable or a component of its
    /// frame is not finite.
    case dividerUnusable
    /// Both are readable and the icon's mid-x is not greater than the divider's
    /// minX, the boundary the rest of IceCore uses (`CheckPlan`,
    /// `DiscoveredCachePlan`).
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
    ///     none. Ice's icon is right of it iff `icon.midX > divider.frame.minX`:
    ///     the divider's minX is the section boundary everywhere else in IceCore,
    ///     and a collapsed or expanded divider's width is not a bar position
    ///     (P2: divider minX 1459, icon mid-x 1297.5). Every component of both
    ///     frames must be finite, otherwise the reading is unusable.
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
        if let placement = iconPlacement(icon: iceIcon, divider: hiddenDivider) {
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

    /// `nil` when the icon's mid-x is strictly right of the divider's minX: the
    /// one definition of "Ice's icon is right of its hidden divider".
    public static func iconPlacement(icon: BarRect?, divider: DividerReading?) -> PreferenceHidingIconPlacement? {
        guard let icon, icon.hasFiniteComponents else { return .iconUnreadable }
        guard let divider, divider.isUsable, let dividerFrame = divider.frame, dividerFrame.hasFiniteComponents else {
            return .dividerUnusable
        }
        return icon.midX > dividerFrame.minX ? nil : .iconLeftOfDivider
    }
}

extension BarRect {
    /// Every component finite: a frame with a NaN or infinite minY or height is
    /// not a position even when its mid-x happens to be finite.
    var hasFiniteComponents: Bool {
        minX.isFinite && minY.isFinite && width.isFinite && height.isFinite
    }
}
