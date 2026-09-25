/// One status item as `ItemCatalog.build` recognised it, and the values
/// around it -- Ice's own dividers, why an item was dropped, how far the
/// pass can be trusted (plan section 4.1.5, task T4 API).

/// One reading of Ice's own hidden or always-hidden control item, recognised
/// by its `AXIdentifier` (D9; plan section 2, "divider"). A divider is never
/// listed as a status item -- it only ever appears here, or folded into
/// `DiscoveredCachePlan`'s notes.
public struct DividerReading: Equatable, Sendable {
    public let frame: BarRect?
    public let isUsable: Bool

    public init(frame: BarRect?, isUsable: Bool) {
        self.frame = frame
        self.isUsable = isUsable
    }

    /// Usable iff a frame exists, its `minY` falls inside the bar's height,
    /// and its `minX` falls inside `[bounds.minX, bounds.maxX)` -- exactly
    /// plan section 2's "divider" boundary. A separate function from
    /// `PositionRule.position` on purpose: a divider is judged by *both*
    /// axes (an obstacle only ever needs `minX`), because a divider that
    /// slipped off the bar vertically must never be read as a boundary.
    public static func usability(of frame: BarRect?, in bounds: BarBounds) -> Bool {
        guard let frame else { return false }
        let verticallyInBar = bounds.minY <= frame.minY && frame.minY < bounds.minY + bounds.barHeight
        let horizontallyInBar = bounds.minX <= frame.minX && frame.minX < bounds.maxX
        return verticallyInBar && horizontallyInBar
    }

    /// Builds a reading with `isUsable` derived by `usability(of:in:)`, for
    /// callers (`ItemCatalog.build`) that always want the two kept in sync.
    public static func make(frame: BarRect?, in bounds: BarBounds) -> DividerReading {
        DividerReading(frame: frame, isUsable: usability(of: frame, in: bounds))
    }
}

/// How the reader's own process's read went, distinct from `ReadOutcome`
/// because a caller downstream (`DiscoveredCachePlan.make`) needs a verdict
/// about the *whole own pass*, not about one attribute read.
public enum OwnReadStatus: Equatable, Sendable {
    /// The own read succeeded and every `OwnIdentifiers` string it needed
    /// was found among the own process's records.
    case ok
    /// The own process's read outcome was `.failed` (plan section 4.1.2).
    case failed
    /// The own read succeeded, but the hidden divider's identifier was not
    /// among the own process's records -- D10's boundaries cannot be
    /// computed without it.
    case identifiersMissing
    /// The own process did not appear among `reads` at all.
    case notRead
}

/// Whether a pass produced a trustworthy, complete picture (plan section
/// 4.1.5).
///
/// Complete means complete for every process that was **eligible** in the pass
/// (2026-09-25 responsiveness-quarantine plan, 3.6). A process under the
/// discoverer's `ResponsivenessQuarantine` is not eligible, and is not read in
/// ordinary passes: it entered only after one of its reads stalled on the extras
/// bar in an earlier pass -- which that pass reported as a failure -- while it
/// had never shown a non-empty extras snapshot, was at least a minute old, was
/// absent from the caller's previous items, and fast answers outnumbered stalls.
/// It is re-probed on a bounded backoff and listed in `DiscoveryResult.
/// quarantined` for as long as it is skipped. A process that has shown a
/// non-empty snapshot, or owned an item in the previous set, is never
/// quarantined, so its failures always make a pass `incomplete`.
public enum Completeness: Equatable, Sendable {
    /// Every eligible process was read conclusively.
    case complete
    /// At least one process's read was `.failed` (own or third-party). The
    /// pids that failed, so a caller can carry exactly those forward.
    case incomplete(failedPIDs: [Int32])
    /// `AXIsProcessTrusted()` was false; nothing here can be trusted at all.
    case permissionDenied
}

/// Why one record never became, or stopped being, a listed item.
///
/// No case names an item dropped for having been carried "too long":
/// `ItemCatalog.carryOver` carries an item for as long as its process keeps
/// failing to read and its identity (`bundleID`, `launchTime`) stays
/// unchanged -- bounded not by a pass count but by how long ago the item was
/// last actually confirmed present (`ItemCatalog.carryOver`'s `freshness`;
/// contract amendments from Codex's plan review, adopted 2026-09-23: round 1
/// removed the pass cap so a hung app's items would not vanish on a timer
/// while the app itself never quit; round 2 replaced the now-unbounded carry
/// with a time bound, because an unbounded carry would let a process that
/// keeps failing forever leave ghost items on screen forever too).
public enum DropReason: Equatable, Sendable {
    /// Shared its `(namespace, tagTitle)` with another item after keying (or
    /// after carry-over) -- neither survives picking one arbitrarily.
    case identityCollision
    /// Carried past `ItemCatalog.carryOver`'s `freshness` bound: too long
    /// since this item's process was last read with it present.
    case stale
    /// An own-process record whose trimmed identifier matched none of
    /// `OwnIdentifiers`.
    case ownUnrecognized
    /// A third-party extra whose `role` was not `"AXMenuBarItem"` -- named,
    /// because a caller diagnosing a bad pass needs to know which role
    /// showed up (plan 4.1.5, "FILTER role before keying").
    case unrecognizedRole(String)
}

/// One dropped record. `key` is `nil` exactly when the record was dropped
/// *before* keying (an unrecognized role, or an own-process record with no
/// role in D9's set) -- there is nothing to key it with.
public struct DroppedItem: Equatable, Sendable {
    public let key: ItemKey?
    public let pid: Int32
    public let reason: DropReason

    public init(key: ItemKey?, pid: Int32, reason: DropReason) {
        self.key = key
        self.pid = pid
        self.reason = reason
    }
}

/// One status item, third-party or Ice's own visible control item, as one
/// pass recognised it (plan section 4.1.5).
public struct DiscoveredItem: Equatable, Sendable {
    public let key: ItemKey
    public let basis: IdentityBasis
    public let process: ProcessInfoRecord
    public let frame: BarRect?
    public let position: ItemPosition
    public let title: String?
    public let description: String?
    public let help: String?
    /// How many passes in a row this item has been carried rather than
    /// freshly read. `0` means it was read this pass (plan section 4.1.3,
    /// "carry-over"). Diagnostic only -- `ItemCatalog.carryOver` does not
    /// consult this number to decide whether to keep carrying (`freshness`
    /// does); only a successful read that lacks the item, a changed
    /// `bundleID`/`launchTime`, or the `freshness` bound removes it.
    public let carriedPasses: Int
    /// The pass time (`ItemCatalog.build`'s `now`) at which this item's
    /// process was last read successfully *with this item present*.
    /// Carrying never advances it -- a carried item was not reconfirmed, so
    /// its clock keeps running from the last real sighting, which is what
    /// lets `ItemCatalog.carryOver`'s `freshness` bound measure real
    /// elapsed time rather than a pass count.
    public let lastConfirmedAt: Double

    public init(
        key: ItemKey,
        basis: IdentityBasis,
        process: ProcessInfoRecord,
        frame: BarRect?,
        position: ItemPosition,
        title: String?,
        description: String?,
        help: String?,
        carriedPasses: Int,
        lastConfirmedAt: Double
    ) {
        self.key = key
        self.basis = basis
        self.process = process
        self.frame = frame
        self.position = position
        self.title = title
        self.description = description
        self.help = help
        self.carriedPasses = carriedPasses
        self.lastConfirmedAt = lastConfirmedAt
    }

    /// The tag Ice's existing `MenuBarItemTag` machinery compares (plan
    /// section 2, "tag"): for the reader's own item, the identifier alone
    /// (D9); for everything else, the full pid-qualified title.
    public var tagKey: TagKey {
        key.tagKey(isSelf: process.isSelf)
    }

    /// The first non-empty of `title`, `description`, `help` -- what a
    /// caller shows the user when no icon can be drawn for this item (plan
    /// section 4.1.1: `ExtrasRecord` carries all three because AX splits an
    /// item's label across them unpredictably).
    public var displayTitle: String? {
        for candidate in [title, description, help] {
            if let candidate, !candidate.isEmpty {
                return candidate
            }
        }
        return nil
    }
}
