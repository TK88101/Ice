/// Who is kept hidden inside Ice (plan 2026-10-07-icebar-preference-hiding,
/// S3 D-a). Everything left of the hidden divider is carried off the bar by a
/// length, so the rule has to say, for each such item, whether Ice can list and
/// press it, whether it only holds the state back, or whether it must stop
/// hiding altogether.

/// Why a listed member cannot be pressed.
public enum PreferenceHidingStaleReason: Equatable, Sendable {
    /// Not uniquely addressable in the current Accessibility read: the process
    /// has no readable children, its identifier now appears on several
    /// children, or `PressTargetRule.index` finds no single child for the key.
    case ambiguousOrUnreadable
    /// A previously known member the current read does not contain at all.
    case missingFromRead
    /// A previously known member whose record is now `.parked`.
    case parked
    /// A previously known member whose record now has no frame.
    case noFrame
}

/// A member's standing in the current read.
public enum PreferenceHidingMemberCondition: Equatable, Sendable {
    /// On the bar and uniquely addressable.
    case ready
    /// Overlapping a neighbour (`ItemPosition.stacked`): listed and pressable,
    /// but the pixel check skips it, so it caps the state (D-a).
    case stacked
    /// Listed, cell disabled, caps the state (D-a).
    case stale(PreferenceHidingStaleReason)
}

/// One entry of the roster.
public struct PreferenceHidingMember: Equatable, Sendable {
    public let tag: TagKey
    /// `nil` exactly for a previously known member the read no longer has.
    public let key: ItemKey?
    public let basis: IdentityBasis?
    public let condition: PreferenceHidingMemberCondition

    public init(tag: TagKey, key: ItemKey?, basis: IdentityBasis?, condition: PreferenceHidingMemberCondition) {
        self.tag = tag
        self.key = key
        self.basis = basis
        self.condition = condition
    }

    /// Only a `ready` or `stacked` member has a cell that may be clicked (D-a,
    /// D-f: unsupported items are marked before a press fails, not after).
    public var isPressable: Bool {
        switch condition {
        case .ready, .stacked: return true
        case .stale: return false
        }
    }

    /// Anything but `ready` keeps the state at "not verified" (D-a).
    public var capsAtNotVerified: Bool {
        condition != .ready
    }
}

/// A `.positional` item left of the divider. It blocks hiding (D-a): its press
/// resolves by child index with only an identifier-at-index recheck, so a
/// reorder between discovery and click can open a sibling's menu. Named so the
/// pane can ask the owner to move it right of the divider.
public struct PreferenceHidingBlocker: Equatable, Sendable {
    public let key: ItemKey
    public let tag: TagKey
    /// `DiscoveredItem.displayTitle`, for the pane's sentence.
    public let name: String?

    public init(key: ItemKey, tag: TagKey, name: String?) {
        self.key = key
        self.tag = tag
        self.name = name
    }
}

/// Why a record was not selected as a member.
public enum PreferenceHidingUnselectedReason: Equatable, Sendable {
    case parked
    case noFrame
}

/// A parked or frameless record that was not known as a member before, so it
/// never becomes one (D-a). Reported rather than dropped silently.
public struct PreferenceHidingUnselected: Equatable, Sendable {
    public let tag: TagKey
    public let reason: PreferenceHidingUnselectedReason

    public init(tag: TagKey, reason: PreferenceHidingUnselectedReason) {
        self.tag = tag
        self.reason = reason
    }
}

public struct PreferenceHidingMembership: Equatable, Sendable {
    public let members: [PreferenceHidingMember]
    public let blockers: [PreferenceHidingBlocker]
    public let unselected: [PreferenceHidingUnselected]

    public init(members: [PreferenceHidingMember], blockers: [PreferenceHidingBlocker], unselected: [PreferenceHidingUnselected]) {
        self.members = members
        self.blockers = blockers
        self.unselected = unselected
    }

    /// True when any member is stale or stacked: the state cannot be
    /// `verifiedHidden` (D-a).
    public var capsAtNotVerified: Bool {
        members.contains(where: \.capsAtNotVerified)
    }

    public var staleMembers: [PreferenceHidingMember] {
        members.filter { if case .stale = $0.condition { return true } else { return false } }
    }

    public var stackedMembers: [PreferenceHidingMember] {
        members.filter { $0.condition == .stacked }
    }

    /// - Parameters:
    ///   - leftOfDivider: the third-party items the current pass reads left of
    ///     Ice's hidden divider; the caller decides "left of" (as
    ///     `DiscoveredCachePlan` does). Non-AX records never get here
    ///     (`ItemCatalog` drops them before keying); not handled again.
    ///   - previousMembers: the tags of the members known before this pass, in
    ///     their listed order. No persistence across restarts is promised (D-a).
    ///   - releasedTags: tags of previously known members the current read
    ///     shows right of the divider (the owner moved them out). They are
    ///     dropped from the roster instead of being kept stale for ever. The
    ///     plan does not name this case; it follows from "missing from the
    ///     read" meaning missing, not moved.
    ///   - childIdentifiersByPID: each process's `AXExtrasMenuBar` children as
    ///     read now (`""` for no identifier, `nil` for a non-item child), the
    ///     input of `PressTargetRule.index`. A pid absent here is unreadable.
    ///     Addressability is derived from this and nothing else.
    ///
    /// The rule, one sentence per case. For an item in the read:
    /// - `.positional` is a blocker and no member, except that one that was a
    ///   member stays listed as stale (it became ambiguous);
    /// - `.parked` or `.noFrame` is never newly selected (`unselected`); a
    ///   previously known member in that state stays listed, stale, disabled;
    /// - one that is not uniquely addressable now is listed, stale, disabled;
    /// - `.stacked` is a listed, pressable member that caps the state;
    /// - an `.onBar` one is a ready member.
    ///
    /// For a previously known member the read does not contain (and that is
    /// not released) it stays listed, stale (`missingFromRead`), disabled.
    ///
    /// Duplicate tags in `leftOfDivider` (never produced by `ItemCatalog`,
    /// which drops collisions) make one stale entry for that tag, built from
    /// the first occurrence; later copies are ignored.
    public static func resolve(
        leftOfDivider: [DiscoveredItem],
        previousMembers: [TagKey],
        releasedTags: Set<TagKey>,
        childIdentifiersByPID: [Int32: [String?]]
    ) -> PreferenceHidingMembership {
        let previous = orderedUnique(previousMembers)
        let wasMember = Set(previous)
        let copies = Dictionary(grouping: leftOfDivider, by: \.tagKey).mapValues(\.count)

        var members = [PreferenceHidingMember]()
        var blockers = [PreferenceHidingBlocker]()
        var unselected = [PreferenceHidingUnselected]()
        var seen = Set<TagKey>()

        for item in leftOfDivider where seen.insert(item.tagKey).inserted {
            let known = wasMember.contains(item.tagKey)
            let unique = copies[item.tagKey] == 1
            let addressable = unique && isAddressable(item, in: childIdentifiersByPID)
            if item.basis == .positional {
                blockers.append(PreferenceHidingBlocker(key: item.key, tag: item.tagKey, name: item.displayTitle))
                if known { members.append(member(item, .stale(.ambiguousOrUnreadable))) }
                continue
            }
            switch condition(of: item, known: known, addressable: addressable) {
            case .member(let condition): members.append(member(item, condition))
            case .unselected(let reason): unselected.append(PreferenceHidingUnselected(tag: item.tagKey, reason: reason))
            }
        }

        let missing = previous.filter { !seen.contains($0) && !releasedTags.contains($0) }
        members += missing.map {
            PreferenceHidingMember(tag: $0, key: nil, basis: nil, condition: .stale(.missingFromRead))
        }
        return PreferenceHidingMembership(members: members, blockers: blockers, unselected: unselected)
    }

    // MARK: - private

    private enum Classification {
        case member(PreferenceHidingMemberCondition)
        case unselected(PreferenceHidingUnselectedReason)
    }

    private static func condition(of item: DiscoveredItem, known: Bool, addressable: Bool) -> Classification {
        switch item.position {
        case .parked: return known ? .member(.stale(.parked)) : .unselected(.parked)
        case .noFrame: return known ? .member(.stale(.noFrame)) : .unselected(.noFrame)
        case .stacked: return .member(addressable ? .stacked : .stale(.ambiguousOrUnreadable))
        case .onBar: return .member(addressable ? .ready : .stale(.ambiguousOrUnreadable))
        }
    }

    private static func member(_ item: DiscoveredItem, _ condition: PreferenceHidingMemberCondition) -> PreferenceHidingMember {
        PreferenceHidingMember(tag: item.tagKey, key: item.key, basis: item.basis, condition: condition)
    }

    private static func isAddressable(_ item: DiscoveredItem, in identifiers: [Int32: [String?]]) -> Bool {
        guard let children = identifiers[item.key.pid] else { return false }
        return PressTargetRule.index(for: item.key, identifiers: children) != nil
    }

    private static func orderedUnique(_ tags: [TagKey]) -> [TagKey] {
        var seen = Set<TagKey>()
        return tags.filter { seen.insert($0).inserted }
    }
}
