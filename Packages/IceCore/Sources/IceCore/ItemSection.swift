/// The three arrangements Ice's layout puts a status item in on macOS 27
/// (plan section 2, "section"): which side of a *collapsed* divider an
/// item's `midX` falls on. `DiscoveredCachePlan.make` is the only place that
/// assigns one; nothing else in this file decides it.
public enum ItemSection: Hashable, Sendable, CaseIterable {
    case visible
    case hidden
    case alwaysHidden
}

/// The identity Ice's existing `MenuBarItemTag` compares (plan section 2,
/// "tag"). Built from an `ItemKey` via `tagTitle(isSelf:)` -- kept as its own
/// type, distinct from `ItemKey`, because a cache-plan's `sectionMap` and a
/// carried-over item are indexed by *tag*, not by the pid-qualified key: the
/// whole point of the tag is that it is what survives a process's read
/// failing (`ItemKey` cannot be recomputed for an item nobody could read this
/// pass).
public struct TagKey: Hashable, Sendable {
    public let namespace: String
    public let title: String

    public init(namespace: String, title: String) {
        self.namespace = namespace
        self.title = title
    }
}

/// Ice's own control-item identifiers (D9), passed in by the caller from
/// `ControlItem.Identifier.allCases` -- never hard-coded here. `ItemCatalog`
/// compares an own-process record's trimmed `AXIdentifier` against these
/// three strings to decide which role, if any, that record plays; a
/// mismatch is `dropped(.ownUnrecognized)`.
public struct OwnIdentifiers: Equatable, Sendable {
    public let visible: String
    public let hidden: String
    public let alwaysHidden: String

    public init(visible: String, hidden: String, alwaysHidden: String) {
        self.visible = visible
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
    }
}
