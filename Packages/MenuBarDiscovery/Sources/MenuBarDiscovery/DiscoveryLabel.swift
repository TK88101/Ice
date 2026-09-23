import IceCore

/// One human-written expectation about a single discovered item (plan
/// section 4.2, T6's comparator): "the item owned by `owner`, at
/// `childIndex` among that owner's items, should have this `position` and
/// `basis` and, if it belongs in the visible section's plan order, this
/// `planIndex`." `Codable` so a frozen set of labels can round-trip through
/// `labels.json` for `mbdiscover --check`.
public struct DiscoveryLabel: Codable, Equatable, Sendable {
    /// The item's namespace (`ItemKey.namespace`) -- a process identity
    /// string, not a full key: two items of one process share it.
    public let owner: String
    /// The item's 0-based position among every item sharing `owner`, in the
    /// same order `DiscoveryLabels.indexed` and `mbdiscover`'s plain listing
    /// both use -- not `ItemKey.childIndex`, which is `nil` for every
    /// non-`.positional` item and so cannot disambiguate two declared items
    /// of one process on its own.
    public let childIndex: Int
    /// `ItemPosition`'s case name (`"onBar"`, `"parked"`, `"stacked"`,
    /// `"noFrame"`).
    public let position: String
    /// `IdentityBasis`'s case name (`"declared"`, `"unnamed"`,
    /// `"positional"`).
    public let basis: String
    /// This item's expected 0-based position in `--plan`'s visible section,
    /// ascending by x. `nil` for a label that only pins position/basis.
    public let planIndex: Int?

    public init(owner: String, childIndex: Int, position: String, basis: String, planIndex: Int?) {
        self.owner = owner
        self.childIndex = childIndex
        self.position = position
        self.basis = basis
        self.planIndex = planIndex
    }
}

/// Compares a frozen set of `DiscoveryLabel`s against a fresh
/// `DiscoveredItemSet` (T6's comparator, plan section 4.2). Pure and fully
/// unit-tested here; `mbdiscover --check` is the thin CLI wrapper around it.
public enum DiscoveryLabels {
    /// One discovered item, together with the `(owner, childIndex)` a label
    /// would name it by.
    public struct IndexedItem: Sendable {
        public let owner: String
        public let childIndex: Int
        public let item: DiscoveredItem
    }

    private struct IndexKey: Hashable {
        let owner: String
        let childIndex: Int
    }

    /// Every listed item (`set.items`, plus `set.visibleControlItem` when
    /// present) with a stable `(owner, childIndex)`: `owner` is the item's
    /// namespace, `childIndex` its 0-based position among every item sharing
    /// that owner, assigned in `set.items`'s own order (frame `minX`, then
    /// pid, then child index -- `ItemCatalog.sortedByFrame`'s order) with the
    /// visible control item numbered last within its own namespace. This is
    /// the one place that order is decided; `mbdiscover`'s plain listing and
    /// `compare` both call it, so a label written from one always finds its
    /// item in the other.
    public static func indexed(_ set: DiscoveredItemSet) -> [IndexedItem] {
        let all = set.items + (set.visibleControlItem.map { [$0] } ?? [])
        var perOwner = [String: Int]()
        return all.map { item in
            let owner = item.key.namespace
            let index = perOwner[owner, default: 0]
            perOwner[owner] = index + 1
            return IndexedItem(owner: owner, childIndex: index, item: item)
        }
    }

    /// Human-readable mismatches; empty means every label agreed. Checks, in
    /// order: every label names an item that exists (`"missing item"`), that
    /// item's `position` matches, that item's `basis` matches; then, if
    /// `planVisible` was handed in, that its order matches the order implied
    /// by the labels' `planIndex`es.
    public static func compare(labels: [DiscoveryLabel], set: DiscoveredItemSet, planVisible: [DiscoveredItem]?) -> [String] {
        let observed = indexed(set)
        var itemsByKey = [IndexKey: DiscoveredItem]()
        var keyByItemKey = [ItemKey: IndexKey]()
        for entry in observed {
            let key = IndexKey(owner: entry.owner, childIndex: entry.childIndex)
            itemsByKey[key] = entry.item
            keyByItemKey[entry.item.key] = key
        }

        var mismatches = [String]()

        // A labels check must not pass on a partial read: an item that was
        // never looked at cannot be counted as agreeing.
        switch set.completeness {
        case .complete:
            break
        case .incomplete(let failedPIDs):
            mismatches.append("incomplete pass: \(failedPIDs.count) process(es) not conclusively read")
        case .permissionDenied:
            mismatches.append("incomplete pass: Accessibility permission denied")
        }

        // Every discovered item must be named by a label; an extra item is as
        // much a disagreement as a missing one.
        let labelled = Set(labels.map { IndexKey(owner: $0.owner, childIndex: $0.childIndex) })
        for entry in observed where !labelled.contains(IndexKey(owner: entry.owner, childIndex: entry.childIndex)) {
            mismatches.append("unexpected item: owner=\(entry.owner) childIndex=\(entry.childIndex)")
        }

        for label in labels {
            let key = IndexKey(owner: label.owner, childIndex: label.childIndex)
            guard let item = itemsByKey[key] else {
                mismatches.append("missing item: owner=\(label.owner) childIndex=\(label.childIndex)")
                continue
            }
            let actualPosition = positionName(item.position)
            if actualPosition != label.position {
                mismatches.append("wrong position: owner=\(label.owner) childIndex=\(label.childIndex) expected=\(label.position) actual=\(actualPosition)")
            }
            let actualBasis = basisName(item.basis)
            if actualBasis != label.basis {
                mismatches.append("wrong basis: owner=\(label.owner) childIndex=\(label.childIndex) expected=\(label.basis) actual=\(actualBasis)")
            }
        }

        if let planVisible {
            let expected = labels
                .filter { $0.planIndex != nil }
                .sorted { $0.planIndex! < $1.planIndex! }
                .map { "\($0.owner)#\($0.childIndex)" }
            let actual = planVisible.map { item -> String in
                guard let key = keyByItemKey[item.key] else { return "?#?" }
                return "\(key.owner)#\(key.childIndex)"
            }
            if expected != actual {
                mismatches.append("wrong plan order: expected=\(expected) actual=\(actual)")
            }
        }

        return mismatches
    }

    /// Public so `mbdiscover`'s plain listing (a separate target in this
    /// package) prints exactly the strings a `DiscoveryLabel.position` is
    /// compared against.
    public static func positionName(_ position: ItemPosition) -> String {
        switch position {
        case .onBar: return "onBar"
        case .parked: return "parked"
        case .stacked: return "stacked"
        case .noFrame: return "noFrame"
        }
    }

    /// Public for the same reason as `positionName`.
    public static func basisName(_ basis: IdentityBasis) -> String {
        switch basis {
        case .declared: return "declared"
        case .unnamed: return "unnamed"
        case .positional: return "positional"
        }
    }
}
