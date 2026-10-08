@testable import IceCore

/// The one builder behind the `DiscoveredItem` / `DiscoveredItemSet` fixtures
/// the discovery and check suites share (residuals plan R11). Each suite keeps
/// its own defaults in a short forward, so no test's data changed when the
/// builders were merged.
func fixtureItem(
    namespace: String = "com.example.a",
    identifier: String,
    pid: Int32,
    childIndex: Int? = nil,
    basis: IdentityBasis = .declared,
    frame: BarRect?,
    position: ItemPosition = .onBar,
    isSelf: Bool = false,
    launchTime: Double? = 10,
    startTime: Double? = nil,
    carriedPasses: Int = 0,
    lastConfirmedAt: Double = 0
) -> DiscoveredItem {
    DiscoveredItem(
        key: ItemKey(namespace: namespace, identifier: identifier, pid: pid, childIndex: childIndex), basis: basis,
        process: ProcessInfoRecord(pid: pid, bundleID: namespace, localizedName: nil, executableName: nil, launchTime: launchTime, isSelf: isSelf, startTime: startTime),
        frame: frame, position: position,
        title: nil, description: nil, help: nil, carriedPasses: carriedPasses, lastConfirmedAt: lastConfirmedAt
    )
}

/// An item's frame on the bar, drawn the way every suite draws one: 4.5 pt
/// down, 24 pt high.
func barFrame(minX: Double, width: Double) -> BarRect {
    BarRect(minX: minX, minY: 4.5, width: width, height: 24)
}

func fixtureSet(
    items: [DiscoveredItem],
    visibleControlItem: DiscoveredItem? = nil,
    hiddenDivider: DividerReading? = nil,
    alwaysHiddenDivider: DividerReading? = nil,
    ownRead: OwnReadStatus = .ok,
    dropped: [DroppedItem] = [],
    staleProcesses: [Int32: ProcessInfoRecord] = [:],
    completeness: Completeness = .complete
) -> DiscoveredItemSet {
    DiscoveredItemSet(
        items: items, visibleControlItem: visibleControlItem, hiddenDivider: hiddenDivider, alwaysHiddenDivider: alwaysHiddenDivider,
        ownRead: ownRead, systemElements: [], dropped: dropped, staleProcesses: staleProcesses, completeness: completeness
    )
}

/// A tag from a short name, for signatures and rosters.
func fixtureTag(_ name: String) -> TagKey {
    TagKey(namespace: "com.example.\(name)", title: "\(name)/p1")
}

func fixtureSignature(
    items: [String] = ["v1", "m1", "m2"],
    members: [String] = ["m1", "m2"],
    frontmostPID: Int32? = 10,
    menuMaxX: Double? = 400,
    displayID: UInt32? = 1,
    spaceID: UInt64? = 7
) -> LayoutSignature {
    LayoutSignature(
        items: items.map(fixtureTag), members: members.map(fixtureTag), frontmostPID: frontmostPID,
        menuMaxX: menuMaxX, displayID: displayID, spaceID: spaceID
    )
}
