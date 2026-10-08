/// The roster IceBar keeps across discovery passes on macOS 27 (plan
/// 2026-10-07-icebar-preference-hiding, D-a, D-c and the T3b design): who is
/// hidden, whether Ice may hide at all, and what the layout signature is made
/// of. Pure; Ice feeds it each completed pass.
public struct PreferenceHidingRoster: Equatable, Sendable {
    public private(set) var membership = PreferenceHidingMembership(members: [], blockers: [])
    public private(set) var preconditions = PreferenceHidingPreconditionResult.ok
    /// Every third-party item tag of the last readable pass, in a stable order.
    public private(set) var itemTags = [TagKey]()
    /// The key each member was last read with (G1 asks its process).
    public private(set) var lastKeys = [TagKey: ItemKey]()

    public init() {}

    /// The roster after one completed pass. A pass without permission read
    /// nothing: the roster stays and the preconditions block (review round 2).
    /// Otherwise members of exited processes go first (G1), then
    /// `PreferenceHidingMembership.resolve` advances the rest.
    /// - Parameters:
    ///   - iconPlacement: the placement Ice holds
    ///     (`IcePlacementNotice.placement(held:read:dividerAtStandardLength:)`).
    ///   - hasExited: whether no process has this pid any more.
    public func advanced(
        set: DiscoveredItemSet,
        hiddenDividerState: DividerState,
        childIdentifiersByPID: [Int32: [String?]],
        iconPlacement: PreferenceHidingIconPlacement?,
        hasExited: (Int32) -> Bool
    ) -> PreferenceHidingRoster {
        var next = self
        if set.completeness != .permissionDenied {
            let previous = PreferenceHidingMembership.carried(
                previous: membership.members.map(\.tag), lastKeys: lastKeys, hasExited: hasExited
            )
            next.membership = PreferenceHidingMembership.resolve(
                set: set, hiddenDividerState: hiddenDividerState,
                previousMembers: previous, childIdentifiersByPID: childIdentifiersByPID
            )
            next.itemTags = set.items.map(\.tagKey).sorted { ($0.namespace, $0.title) < ($1.namespace, $1.title) }
            let tags = Set(next.membership.members.map(\.tag))
            var keys = lastKeys.filter { tags.contains($0.key) }
            for member in next.membership.members {
                if let key = member.key { keys[member.tag] = key }
            }
            next.lastKeys = keys
        }
        next.preconditions = PreferenceHidingPreconditions.evaluate(
            iconPlacement: iconPlacement, completeness: set.completeness, ownRead: set.ownRead,
            blockers: next.membership.blockers
        )
        return next
    }

    /// The layout signature for this roster and what the bar is shown with.
    public func signature(frontmostPID: Int32?, menuMaxX: Double?, displayID: UInt32?, spaceID: UInt64?) -> LayoutSignature {
        LayoutSignature(
            items: itemTags, members: membership.members.map(\.tag), frontmostPID: frontmostPID,
            menuMaxX: menuMaxX, displayID: displayID, spaceID: spaceID
        )
    }
}
