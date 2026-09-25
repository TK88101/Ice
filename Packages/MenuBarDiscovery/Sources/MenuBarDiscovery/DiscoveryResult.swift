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
    /// Every pid this pass enumerated, read or not -- what tells "read clean,
    /// nothing on the bar" apart from "not asked about at all" (`status(of:)`).
    public let enumeratedPIDs: Set<Int32>

    /// No default for `quarantined` or `enumeratedPIDs`: a site that rebuilds a
    /// result must say what it carries over, or it would silently drop them.
    public init(set: DiscoveredItemSet, duration: Double, origin: DiscoveryOrigin, bounds: BarBounds, nextCursor: Int, quarantined: [ProcessInfoRecord], enumeratedPIDs: Set<Int32>) {
        self.set = set
        self.duration = duration
        self.origin = origin
        self.bounds = bounds
        self.nextCursor = nextCursor
        self.quarantined = quarantined
        self.enumeratedPIDs = enumeratedPIDs
    }

    /// What this pass says about one pid (hardening plan H6). Facts only; each
    /// caller composes the question it asks. A struct, not an enum: a process
    /// entering the quarantine is failed *and* quarantined in the same pass.
    public struct PIDStatus: Equatable, Sendable {
        /// The pass enumerated it.
        public let enumerated: Bool
        /// It owns a listed item, the visible control item included -- a
        /// carried item counts.
        public let listed: Bool
        /// This pass's read of it failed.
        public let failed: Bool
        /// It is under the responsiveness quarantine once this pass settled.
        public let quarantined: Bool
        /// Accessibility was not trusted, so the pass read nothing at all.
        public let permissionDenied: Bool

        public init(enumerated: Bool, listed: Bool, failed: Bool, quarantined: Bool, permissionDenied: Bool) {
            self.enumerated = enumerated
            self.listed = listed
            self.failed = failed
            self.quarantined = quarantined
            self.permissionDenied = permissionDenied
        }
    }

    public func status(of pid: Int32) -> PIDStatus {
        let failed: Bool
        if case .incomplete(let pids) = set.completeness { failed = pids.contains(pid) } else { failed = false }
        return PIDStatus(
            enumerated: enumeratedPIDs.contains(pid),
            listed: set.listedItems.contains { $0.process.pid == pid },
            failed: failed,
            quarantined: quarantined.contains { $0.pid == pid },
            permissionDenied: set.completeness == .permissionDenied
        )
    }
}
