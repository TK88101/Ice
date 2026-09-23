import IceCore

/// Where a display's origin sits in the global Accessibility coordinate
/// space (plan section 4.2's `DiscoveryResult.origin`), as its own small
/// `Sendable` value rather than a tuple -- a tuple cannot conform to
/// `Equatable`/`Sendable` the way a test assertion or a stored property
/// needs.
public struct DiscoveryOrigin: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// One completed `MenuBarDiscoverer.discover` pass (plan section 4.2):
/// `set` already has `ItemCatalog.carryOver` applied; `nextCursor` is where
/// the next pass should start (D19/4.2's rotation), reported so a caller --
/// or a test -- can see where a deadline truncation left off without
/// depending on `MenuBarDiscoverer`'s private cursor state.
public struct DiscoveryResult: Sendable {
    public let set: DiscoveredItemSet
    public let duration: Double
    public let origin: DiscoveryOrigin
    public let bounds: BarBounds
    public let nextCursor: Int

    public init(set: DiscoveredItemSet, duration: Double, origin: DiscoveryOrigin, bounds: BarBounds, nextCursor: Int) {
        self.set = set
        self.duration = duration
        self.origin = origin
        self.bounds = bounds
        self.nextCursor = nextCursor
    }
}
