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
    /// `nil` exactly for a previously known member the read no longer has
    /// (`key == nil` is what "missing from the read" means).
    public let key: ItemKey?
    public let condition: PreferenceHidingMemberCondition

    public init(tag: TagKey, key: ItemKey?, condition: PreferenceHidingMemberCondition) {
        self.tag = tag
        self.key = key
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

public struct PreferenceHidingMembership: Equatable, Sendable {
    public let members: [PreferenceHidingMember]
    public let blockers: [PreferenceHidingBlocker]

    public init(members: [PreferenceHidingMember], blockers: [PreferenceHidingBlocker]) {
        self.members = members
        self.blockers = blockers
    }

    public var staleMembers: [PreferenceHidingMember] {
        members.filter { if case .stale = $0.condition { return true } else { return false } }
    }

    public var stackedMembers: [PreferenceHidingMember] {
        members.filter { $0.condition == .stacked }
    }

    /// The one sanctioned geometry for membership (D-a): everything of `set`
    /// left of its hidden divider, so a caller cannot feed `resolve` the wrong
    /// set. It derives, from `set.items` (third-party items, parked ones
    /// included -- unlike `DiscoveredCachePlan`, which filters them) and
    /// `set.hiddenDivider`:
    /// - left of the divider: an item with a frame whose `midX` is less than the
    ///   divider frame's `minX` (the section boundary of `CheckPlan` and
    ///   `DiscoveredCachePlan`); also an item with no frame whose base tag is a
    ///   previous member, so it becomes `stale(.noFrame)` rather than missing. A
    ///   frameless item that was not a member is ignored;
    /// - released: the base tags of previous members whose item in the set is on
    ///   the bar (not parked) with `midX` at or right of the divider's `minX`
    ///   (the owner moved them out); a parked member is never released, it
    ///   stays `stale(.parked)` wherever its frame points;
    /// - when the divider reading is `nil`, not usable, or has a non-finite frame
    ///   component, no item is left of it and nothing is released: previous
    ///   members become `stale(.missingFromRead)`. The preconditions block in
    ///   that case anyway (D-c a).
    ///
    /// Previous members and released tags are compared by base tag (see
    /// `resolve(leftOfDivider:previousMembers:releasedTags:childIdentifiersByPID:)`).
    ///
    /// The roster changes only on a boundary `DiscoveredCachePlan` trusts
    /// (`hiddenDividerState` collapsed, settled, unchanged during the pass, own
    /// read ok): a released member is dropped for good, so on any other pass the
    /// roster is frozen -- previous members stay (wherever they read), nothing
    /// is released and no new member is added (Codex review round 3).
    public static func resolve(
        set: DiscoveredItemSet,
        hiddenDividerState: DividerState,
        previousMembers: [TagKey],
        childIdentifiersByPID: [Int32: [String?]]
    ) -> PreferenceHidingMembership {
        guard let boundary = set.hiddenDivider?.boundaryMinX else {
            return resolve(
                leftOfDivider: [], previousMembers: previousMembers, releasedTags: [],
                childIdentifiersByPID: childIdentifiersByPID
            )
        }
        let wasMember = Set(previousMembers)
        let trusted = DiscoveredCachePlan.evaluate(
            reading: set.hiddenDivider, state: hiddenDividerState, ownRead: set.ownRead
        ).minX != nil
        var left = [DiscoveredItem]()
        var released = Set<TagKey>()
        for item in set.items {
            let known = wasMember.contains(baseTag(of: item))
            // A parked or frameless member is off the bar, not moved by the
            // owner: it stays listed, stale, wherever its frame points.
            guard let frame = item.frame, item.position != .parked, trusted else {
                if known { left.append(item) }
                continue
            }
            if frame.midX < boundary {
                left.append(item)
            } else if known, frame.midX.isFinite {
                released.insert(baseTag(of: item))
            }
        }
        return resolve(
            leftOfDivider: left, previousMembers: previousMembers, releasedTags: released,
            childIdentifiersByPID: childIdentifiersByPID
        )
    }

    /// - Parameters:
    ///   - leftOfDivider: the third-party items the current pass reads left of
    ///     Ice's hidden divider; the caller decides "left of" (the public entry
    ///     point `resolve(set:...)` is the sanctioned way). Non-AX records never
    ///     get here (`ItemCatalog` drops them before keying); not handled again.
    ///   - previousMembers: the tags of the members known before this pass, in
    ///     their listed order. No persistence across restarts is promised (D-a).
    ///   - releasedTags: base tags of previously known members the current read
    ///     shows right of the divider (the owner moved them out). They are
    ///     dropped from the roster instead of being kept stale for ever. The
    ///     plan does not name this case; it follows from "missing from the
    ///     read" meaning missing, not moved.
    ///   - childIdentifiersByPID: each process's `AXExtrasMenuBar` children as
    ///     read now (`""` for no identifier, `nil` for a non-item child), the
    ///     input of `PressTargetRule.index`. A pid absent here is unreadable.
    ///     Addressability is derived from this and nothing else.
    ///
    /// Previous members and released tags are compared by base tag: the tag of
    /// the item's key without a child index. For a `.declared` or `.unnamed`
    /// item that is its `tagKey`; a previous member that has since become
    /// `.positional` is thereby still recognised as known, and listed under its
    /// previous tag.
    ///
    /// The rule, one sentence per case. For an item in the read:
    /// - `.positional` is a blocker and no member, except that one that was a
    ///   member stays listed (under its previous tag) as stale (it became
    ///   ambiguous);
    /// - `.parked` or `.noFrame` that was not a member is not selected, and
    ///   nothing is reported for it; a previously known member in that state
    ///   stays listed, stale, disabled;
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
    static func resolve(
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
        var seen = Set<TagKey>()
        var listedPositional = Set<TagKey>()

        for item in leftOfDivider where seen.insert(item.tagKey).inserted {
            let known = wasMember.contains(baseTag(of: item))
            let addressable = copies[item.tagKey] == 1 && isAddressable(item, in: childIdentifiersByPID)
            if item.basis == .positional {
                blockers.append(PreferenceHidingBlocker(key: item.key, tag: item.tagKey, name: item.displayTitle))
                if known, listedPositional.insert(baseTag(of: item)).inserted {
                    members.append(member(item, .stale(.ambiguousOrUnreadable)))
                }
            } else if let condition = condition(of: item, known: known, addressable: addressable) {
                members.append(member(item, condition))
            }
        }

        let covered = Set(leftOfDivider.map(baseTag(of:)))
        let missing = previous.filter { !covered.contains($0) && !releasedTags.contains($0) }
        members += missing.map { PreferenceHidingMember(tag: $0, key: nil, condition: .stale(.missingFromRead)) }
        return PreferenceHidingMembership(members: members, blockers: blockers)
    }

    // MARK: - private

    /// The item's tag with no child index: what a previous member is matched by,
    /// so a basis change (`.declared` to `.positional`) does not lose it.
    private static func baseTag(of item: DiscoveredItem) -> TagKey {
        item.key.baseTagKey(isSelf: item.process.isSelf)
    }

    /// `nil`: never newly selected (a parked or frameless record that was not a
    /// member).
    private static func condition(of item: DiscoveredItem, known: Bool, addressable: Bool) -> PreferenceHidingMemberCondition? {
        switch item.position {
        case .parked: return known ? .stale(.parked) : nil
        case .noFrame: return known ? .stale(.noFrame) : nil
        case .stacked: return addressable ? .stacked : .stale(.ambiguousOrUnreadable)
        case .onBar: return addressable ? .ready : .stale(.ambiguousOrUnreadable)
        }
    }

    private static func member(_ item: DiscoveredItem, _ condition: PreferenceHidingMemberCondition) -> PreferenceHidingMember {
        let tag = item.basis == .positional ? baseTag(of: item) : item.tagKey
        return PreferenceHidingMember(tag: tag, key: item.key, condition: condition)
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
