/// D10's cache verdict, implemented exactly as v5.1 section 3 writes it: each
/// boundary decided on its own, sections computed only while a divider is
/// collapsed, and an item neither boundary decides keeps its previous
/// section by tag (plan section 4.1.6).

/// Ice's own state for one divider (`ControlItem`): collapsed-ness as of
/// the start of one pass, `isEnabled` as of its end.
public struct DividerState: Equatable, Sendable {
    public let isEnabled: Bool
    public let isCollapsed: Bool
    /// How long the divider has been collapsed, in seconds. Only meaningful
    /// while `isCollapsed`.
    public let collapsedFor: Double
    /// Whether this divider's state changed while the pass was running --
    /// caught with a generation counter on Ice's side (D10).
    public let changedDuringPass: Bool

    public init(isEnabled: Bool, isCollapsed: Bool, collapsedFor: Double, changedDuringPass: Bool) {
        self.isEnabled = isEnabled
        self.isCollapsed = isCollapsed
        self.collapsedFor = collapsedFor
        self.changedDuringPass = changedDuringPass
    }
}

public struct DividerStates: Equatable, Sendable {
    public let hidden: DividerState
    public let alwaysHidden: DividerState

    public init(hidden: DividerState, alwaysHidden: DividerState) {
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
    }
}

/// Why a boundary could not be used to decide an item's section this pass.
public enum BoundaryIssue: Equatable, Sendable {
    /// The divider is not collapsed.
    case expanded
    /// Collapsed for less than `DiscoveredCachePlan.settleSeconds`.
    case settling
    /// The divider's state changed while the pass was running.
    case changedDuringPass
    /// No reading for this divider at all (its own record was not found, or
    /// the own process was never read).
    case missing
    /// A reading exists but failed `DividerReading.isUsable`.
    case unusable
    /// The own process's read outcome was `.failed`.
    case ownReadFailed
    /// The own read succeeded, but the hidden divider's identifier was not
    /// found among the own process's records.
    case identifiersMissing
    /// This divider's section is turned off in Ice's settings
    /// (always-hidden only, in practice).
    case disabled
}

/// One boundary's problem this pass, tagged by which divider it is.
public enum BoundaryNote: Equatable, Sendable {
    case hidden(BoundaryIssue)
    case alwaysHidden(BoundaryIssue)
}

/// What `DiscoveredCachePlan.make` hands Ice to publish into its item cache.
public struct CachePublication: Equatable, Sendable {
    /// Each ordered by frame `minX`, no-frame items last.
    public let visible: [DiscoveredItem]
    public let hidden: [DiscoveredItem]
    public let alwaysHidden: [DiscoveredItem]
    public let sectionMap: [TagKey: ItemSection]
    public let notes: [BoundaryNote]

    public init(visible: [DiscoveredItem], hidden: [DiscoveredItem], alwaysHidden: [DiscoveredItem], sectionMap: [TagKey: ItemSection], notes: [BoundaryNote]) {
        self.visible = visible
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
        self.sectionMap = sectionMap
        self.notes = notes
    }
}

/// Why `DiscoveredCachePlan.make` refused to publish a new arrangement.
public enum KeepPreviousReason: Equatable, Sendable {
    case permissionDenied
}

public enum CachePlanResult: Equatable, Sendable {
    case publish(CachePublication)
    case keepPrevious(KeepPreviousReason)
}

public enum DiscoveredCachePlan {
    /// A divider must be collapsed for at least this long before its
    /// boundary is trusted (D10).
    public static let settleSeconds: Double = 1.0

    public static func make(set: DiscoveredItemSet, dividerStates: DividerStates, previous: [TagKey: ItemSection]) -> CachePlanResult {
        if case .permissionDenied = set.completeness {
            return .keepPrevious(.permissionDenied)
        }

        let hidden = evaluate(reading: set.hiddenDivider, state: dividerStates.hidden, ownRead: set.ownRead)
        var notes = [BoundaryNote]()
        if let issue = hidden.issue { notes.append(.hidden(issue)) }

        let alwaysHiddenEnabled = dividerStates.alwaysHidden.isEnabled
        let alwaysHidden = alwaysHiddenEnabled
            ? evaluate(reading: set.alwaysHiddenDivider, state: dividerStates.alwaysHidden, ownRead: set.ownRead)
            : (minX: nil, issue: .disabled)
        if let issue = alwaysHidden.issue { notes.append(.alwaysHidden(issue)) }

        // The previous section, with always-hidden folded into hidden while
        // that section is disabled.
        func carried(_ item: DiscoveredItem) -> ItemSection? {
            guard let previousSection = previous[item.tagKey] else { return nil }
            if !alwaysHiddenEnabled, previousSection == .alwaysHidden { return .hidden }
            return previousSection
        }

        let alwaysHiddenMinX = alwaysHidden.minX

        func section(for item: DiscoveredItem) -> ItemSection {
            // A frame that could not be read must not move an item the user
            // placed: it keeps its previous section, and only a new one
            // defaults to visible.
            guard let frame = item.frame else { return carried(item) ?? .visible }
            let midX = frame.midX

            if let hiddenMinX = hidden.minX {
                if midX >= hiddenMinX { return .visible }
                // Left of a known hidden boundary is never visible, whatever
                // an earlier pass said: the boundary decides that much alone.
                if let alwaysHiddenMinX { return midX < alwaysHiddenMinX ? .alwaysHidden : .hidden }
                return carried(item) == .alwaysHidden ? .alwaysHidden : .hidden
            }

            // The hidden boundary is unknown: the always-hidden one, if known,
            // decides both ways on its own side of the bar.
            if let alwaysHiddenMinX {
                if midX < alwaysHiddenMinX { return .alwaysHidden }
                let earlier = carried(item)
                return earlier == .alwaysHidden ? .hidden : (earlier ?? .visible)
            }

            return carried(item) ?? .visible
        }

        var sectionMap = [TagKey: ItemSection]()
        var visible = [DiscoveredItem]()
        var hiddenItems = [DiscoveredItem]()
        var alwaysHiddenItems = [DiscoveredItem]()

        let candidates = set.items.filter { $0.position != .parked } + (set.visibleControlItem.map { [$0] } ?? [])
        for item in candidates {
            let assigned = section(for: item)
            sectionMap[item.tagKey] = assigned
            switch assigned {
            case .visible: visible.append(item)
            case .hidden: hiddenItems.append(item)
            case .alwaysHidden: alwaysHiddenItems.append(item)
            }
        }

        let publication = CachePublication(
            visible: ItemCatalog.sortedByFrame(visible),
            hidden: ItemCatalog.sortedByFrame(hiddenItems),
            alwaysHidden: ItemCatalog.sortedByFrame(alwaysHiddenItems),
            sectionMap: sectionMap,
            notes: notes
        )
        return .publish(publication)
    }

    /// One boundary's verdict: a `minX` iff the own read is trustworthy, a
    /// usable divider reading exists, it is enabled, collapsed for at least
    /// `settleSeconds`, and unchanged during the pass. `issue` names the
    /// first reason it is not, checked in this order because own-read
    /// problems and a missing/unusable reading make every later check
    /// meaningless.
    private static func evaluate(reading: DividerReading?, state: DividerState, ownRead: OwnReadStatus) -> (minX: Double?, issue: BoundaryIssue?) {
        if ownRead == .failed { return (nil, .ownReadFailed) }
        if ownRead == .identifiersMissing { return (nil, .identifiersMissing) }

        guard let reading else { return (nil, .missing) }
        guard reading.isUsable, let frame = reading.frame else { return (nil, .unusable) }
        guard state.isEnabled else { return (nil, .disabled) }
        guard state.isCollapsed else { return (nil, .expanded) }
        guard state.collapsedFor >= settleSeconds else { return (nil, .settling) }
        guard !state.changedDuringPass else { return (nil, .changedDuringPass) }
        return (frame.minX, nil)
    }
}
