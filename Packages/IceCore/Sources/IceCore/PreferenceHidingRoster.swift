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
    /// The hidden divider's right edge as the last trusted pass read it, on
    /// that pass's display; `nil` before one, after a pass on another display,
    /// and after any pass that read an item gone (plan
    /// 2026-11-13-flash-on-item-change, D2, D2a: a removal may move the
    /// divider, and nothing estimates by how much).
    public var visibleBoundary: Double? { boundary?.maxX }
    private var boundary: VisibleBoundary?
    /// The item tags of the last readable pass on the bar at or right of
    /// `visibleBoundary` (D3); empty without a boundary.
    public private(set) var visibleTags = Set<TagKey>()
    /// The last pass was blind at length (`BlindAtLength`): on this system a
    /// pushed-off item is in no read, so a press must show the section first
    /// and an arrival is read only at standard length (plan
    /// 2026-11-15-blind-at-length, D3, D4).
    public private(set) var isBlindAtLength = false

    public init() {}

    /// The roster after one completed pass. A pass without permission read
    /// nothing: the roster stays and the preconditions block (review round 2).
    /// Otherwise members of exited processes go first (G1), then
    /// `PreferenceHidingMembership.resolve` advances the rest.
    /// - Parameters:
    ///   - iconPlacement: the placement Ice holds
    ///     (`IcePlacementNotice.placement(held:read:dividerAtStandardLength:)`).
    ///   - hasExited: whether no process has this pid any more.
    ///   - display: the display the pass read (D2a).
    ///   - holdsWrittenLength: Ice's own state, not Accessibility, says the
    ///     hidden control item holds the length the coordinator last wrote
    ///     (`BlindAtLength`, D1).
    ///
    /// A blind pass (plan 2026-11-15-blind-at-length, D2) read nothing left
    /// of the divider: the members stay as they were, less the exited; the
    /// item tags lose only what is positively gone, a tag seen right of the
    /// divider and not read now, or an exited member's; its missing divider
    /// blocks nothing. The boundary follows the rule of any untrusted pass.
    public func advanced(
        set: DiscoveredItemSet,
        hiddenDividerState: DividerState,
        childIdentifiersByPID: [Int32: [String?]],
        iconPlacement: PreferenceHidingIconPlacement?,
        hasExited: (Int32) -> Bool,
        display: BarDisplay,
        holdsWrittenLength: Bool = false
    ) -> PreferenceHidingRoster {
        var next = self
        next.isBlindAtLength = BlindAtLength.holds(
            set: set, hiddenDividerState: hiddenDividerState, holdsWrittenLength: holdsWrittenLength,
            hasMembers: !membership.members.isEmpty
        )
        if set.completeness != .permissionDenied {
            let previous = PreferenceHidingMembership.carried(
                previous: membership.members.map(\.tag), lastKeys: lastKeys, hasExited: hasExited
            )
            let read = set.items.map(\.tagKey)
            if next.isBlindAtLength {
                let alive = Set(previous)
                let exited = membership.members.map(\.tag).filter { !alive.contains($0) }
                next.membership = PreferenceHidingMembership(
                    members: membership.members.filter { alive.contains($0.tag) }, blockers: membership.blockers
                )
                let gone = visibleTags.subtracting(read).union(exited)
                next.itemTags = Self.ordered(Array(Set(itemTags).union(read).subtracting(gone)))
            } else {
                next.membership = PreferenceHidingMembership.resolve(
                    set: set, hiddenDividerState: hiddenDividerState,
                    previousMembers: previous, childIdentifiersByPID: childIdentifiersByPID
                )
                next.itemTags = Self.ordered(read)
            }
            next.boundary = Self.boundary(
                after: boundary, set: set, hiddenDividerState: hiddenDividerState, display: display,
                removed: !Set(itemTags).isSubset(of: next.itemTags)
            )
            next.visibleTags = Self.visibleTags(of: set, boundary: next.boundary?.maxX)
            let tags = Set(next.membership.members.map(\.tag))
            var keys = lastKeys.filter { tags.contains($0.key) }
            for member in next.membership.members {
                if let key = member.key { keys[member.tag] = key }
            }
            next.lastKeys = keys
        }
        next.preconditions = PreferenceHidingPreconditions.evaluate(
            iconPlacement: iconPlacement, completeness: set.completeness, ownRead: set.ownRead,
            blockers: next.membership.blockers, isBlindAtLength: next.isBlindAtLength
        )
        return next
    }

    /// The item tags' one order, whatever order a pass read them in.
    private static func ordered(_ tags: [TagKey]) -> [TagKey] {
        tags.sorted { ($0.namespace, $0.title) < ($1.namespace, $1.title) }
    }

    /// The layout signature for this roster and what the bar is shown with.
    public func signature(frontmostPID: Int32?, menuMaxX: Double?, displayID: UInt32?, spaceID: UInt64?) -> LayoutSignature {
        LayoutSignature(
            items: itemTags, members: membership.members.map(\.tag), frontmostPID: frontmostPID,
            menuMaxX: menuMaxX, displayID: displayID, spaceID: spaceID, visibleItems: visibleTags
        )
    }

    /// D2: a trusted pass sets the boundary; any other keeps it only on the
    /// same display and when nothing was read gone.
    private static func boundary(
        after previous: VisibleBoundary?,
        set: DiscoveredItemSet,
        hiddenDividerState: DividerState,
        display: BarDisplay,
        removed: Bool
    ) -> VisibleBoundary? {
        let trusted = DiscoveredCachePlan.evaluate(
            reading: set.hiddenDivider, state: hiddenDividerState, ownRead: set.ownRead
        ).minX != nil
        if trusted, let frame = set.hiddenDivider?.frame, frame.hasFiniteComponents {
            return VisibleBoundary(maxX: frame.maxX, display: display)
        }
        guard let previous, previous.display == display, !removed else { return nil }
        return previous
    }

    /// D3: on the bar, a finite frame, its left edge at or right of the boundary.
    private static func visibleTags(of set: DiscoveredItemSet, boundary: Double?) -> Set<TagKey> {
        guard let boundary else { return [] }
        return Set(set.items.compactMap { item in
            guard item.position == .onBar, let frame = item.frame, frame.hasFiniteComponents, frame.minX >= boundary else {
                return nil
            }
            return item.tagKey
        })
    }
}

/// The hidden divider's right edge and the display it was read on.
private struct VisibleBoundary: Equatable, Sendable {
    let maxX: Double
    let display: BarDisplay
}
