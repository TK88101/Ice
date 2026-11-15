/// Plan 2026-11-15-secondary-display, T2d. One status item length is shared
/// by every display's bar, and the hiding band differs between displays
/// (MEASURED on the owner's two, 2026-11-14): while more than one display is
/// connected, unless the topology is a measured one, Ice does not hide and
/// offers no IceBar, so no item is both drawn on a bar and listed in it.

/// The connected, non-mirrored displays, as the coordinator reads them.
public struct DisplayTopology: Equatable, Sendable {
    /// Display ids, frames, scale and mirroring, as one comparable string.
    public let fingerprint: String
    public let count: Int

    public init(fingerprint: String, count: Int) {
        self.fingerprint = fingerprint
        self.count = count
    }
}

/// Tracks topology changes: a change blocks at once, bumps the generation
/// (work begun before it is dropped), and is decided once it has held
/// `settleSeconds`.
public struct TopologyTracker: Equatable, Sendable {
    public static let settleSeconds = 2.0

    public private(set) var generation = 0
    private var topology: DisplayTopology?
    private var changedAt: Double?

    public init() {}

    public mutating func observe(_ next: DisplayTopology, now: Double) {
        guard let current = topology else {
            topology = next
            return
        }
        guard current != next else { return }
        topology = next
        changedAt = now
        generation += 1
    }

    /// Whether work begun under `generation` may still act.
    public func accepts(_ generation: Int) -> Bool {
        generation == self.generation
    }

    /// - Parameter supported: the topology is a measured one (or a single display).
    public func blockReason(now: Double, supported: Bool) -> PreferenceHidingBlockReason? {
        guard let topology else { return nil }
        if let changedAt, now - changedAt < Self.settleSeconds { return .displaysSettling }
        if topology.count > 1, !supported { return .multipleDisplays(topology.count) }
        return nil
    }
}
