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
    /// Every enumerated process under the discoverer's responsiveness
    /// quarantine once this pass settled, by pid -- the processes `set`'s
    /// `.complete` does not speak for (`Completeness`; 2026-09-25
    /// responsiveness-quarantine plan, 3.6). Includes any that entered in this
    /// very pass, whose stall `set` also reports as a failure.
    public let quarantined: [ProcessInfoRecord]

    /// No default for `quarantined`: a site that rebuilds a result must say what
    /// it carries over, or it would silently drop the list.
    public init(set: DiscoveredItemSet, duration: Double, origin: DiscoveryOrigin, bounds: BarBounds, nextCursor: Int, quarantined: [ProcessInfoRecord]) {
        self.set = set
        self.duration = duration
        self.origin = origin
        self.bounds = bounds
        self.nextCursor = nextCursor
        self.quarantined = quarantined
    }
}
