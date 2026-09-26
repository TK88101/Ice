/// Amendment v8, "Placement by the helpers' own preferred position"
/// (option A): the pure geometry behind the write. `StageC1`'s own new
/// pre-launch step (`step1bPlacementPlan`, `StageC1Placement.swift`) feeds
/// this from one fresh discovery pass, before any helper exists -- the
/// on-bar owner items already there (parked items already excluded by the
/// caller filtering to `.onBar`, per Amendment v8's first bullet -- there
/// is no helper yet at that point to filter out either), the bar's own
/// geometry, and each helper's own real *occupied* pitch (Amendment v9,
/// "Real pitch": crosscheck-rework8.json #1 found the plan's old nominal
/// AX widths -- 12/17.5/12 pt -- narrower than the real, packed slots --
/// 28/32/28 pt -- which could insert Target between the spacer and
/// Protected once macOS actually packs the items). The result is only ever
/// numbers recorded to evidence and written into the helpers' own defaults
/// domains -- a plan, never a promise: whether macOS 27 actually honours
/// the write for a freshly created item is unverified (SEAM-AUDIT.md
/// documents it as a modelled assumption), and `step2bPlacementGate`,
/// after the real launches, is what actually decides.
///
/// Amendment v9, "Sort-key values": the written preferred-position values
/// are no longer `barRightEdge - minX` (crosscheck-rework8.json #0/#4). The
/// owner's own recorded stored values contradict that right-edge-distance
/// reading and instead follow the items' own left-to-right order, so a
/// plan built on that assumption can end the run "helpers not leftmost"
/// for a reason the code itself created, even when macOS actually honours
/// the key. The values are now `floor + step` for each helper, where
/// `floor` is the largest of `historicalMaximumStoredValue` and every
/// on-bar owner's own scanned stored value (`PlacementValueScan`, read-only,
/// before any launch): large enough to sort/land leftmost under either
/// reading this fork has evidence for. An owner scan this plan cannot
/// trust (`PlacementValueScan.Issue`) refuses the whole plan before any
/// geometry work, rather than guess.
public enum PlacementPlan {
    /// The gap this plan leaves between the group's own right edge
    /// (Protected's own trailing edge) and the nearest on-bar owner item's
    /// minX -- deliberately larger than `PlacementGate`'s own strict "<"
    /// comparison needs, so a few points of live rendering slop cannot
    /// turn a real PASS into a gate failure.
    public static let marginPt = 6.0

    /// Amendment v9: the largest stored "NSStatusItem Preferred Position"
    /// value this fork has ever recorded on the owner's own bar
    /// (`~/IceReverse-evidence/20260925-092244-icerun/before/app-statusitem-keys.txt`,
    /// one item's own stored value) -- kept as a conservative floor even
    /// when every on-bar owner item's own scan reads lower than this (or
    /// there are no on-bar owner items at all).
    public static let historicalMaximumStoredValue = 5772.0

    /// Amendment v9 / Codex round 9b H1: the gap between each of the three
    /// helpers' own preferred-position values -- "well above one slot"
    /// (the real occupied pitch, 28-32 pt), so the three helpers still
    /// sort/land in the right order relative to each other under either
    /// the sort-key or the right-edge-distance reading.
    public static let sortKeyStepPt = 100.0

    /// Left-to-right minX for each helper (bar-space points, at the real
    /// occupied pitch), and the "NSStatusItem Preferred Position" value to
    /// write for each (`floorValue + step`, Amendment v9).
    public struct Result: Equatable, Sendable {
        public let targetMinX: Double
        public let spacerMinX: Double
        public let protectedMinX: Double
        public let targetPreferredPosition: Double
        public let spacerPreferredPosition: Double
        public let protectedPreferredPosition: Double
        /// `max(historicalMaximumStoredValue, every on-bar owner's own
        /// scanned value)` -- recorded so the evidence can show which floor
        /// a plan actually used.
        public let floorValue: Double

        public init(
            targetMinX: Double,
            spacerMinX: Double,
            protectedMinX: Double,
            targetPreferredPosition: Double,
            spacerPreferredPosition: Double,
            protectedPreferredPosition: Double,
            floorValue: Double
        ) {
            self.targetMinX = targetMinX
            self.spacerMinX = spacerMinX
            self.protectedMinX = protectedMinX
            self.targetPreferredPosition = targetPreferredPosition
            self.spacerPreferredPosition = spacerPreferredPosition
            self.protectedPreferredPosition = protectedPreferredPosition
            self.floorValue = floorValue
        }
    }

    /// Why this plan refused, rather than compute a `Result`.
    public enum RefusalReason: Equatable, Sendable {
        /// One on-bar owner item's own scan could not be trusted --
        /// unreadable, non-numeric, missing or attribution-unclear
        /// (`PlacementValueScan.Issue`). Refuse before any launch rather
        /// than guess at that owner's own stored value.
        case ownerScanUncertain(minX: Double, issue: PlacementValueScan.Issue)
        /// The three helpers, laid out contiguously left of the nearest
        /// owner item (or the bar's own right edge, when there is no owner
        /// item at all) with `marginPt` to spare, would not fit clear of
        /// the notch -- or a non-positive occupied pitch was given (never a
        /// real geometry).
        case noRoom(onBarOwnerCount: Int)
    }

    public enum Outcome: Equatable, Sendable {
        case planned(Result)
        case refused(RefusalReason)
    }

    /// `owners`: every on-bar owner item's own minX and classified
    /// preference-domain scan (whatever order). `barRightEdge`:
    /// `BarGeometry.widthPt`. `notchRightEdge`: `BarGeometry.notch?.hi`, or
    /// `0` when there is none -- the leftmost room this plan may ever use.
    /// `targetOccupiedPt`/`spacerOccupiedPt`/`protectedOccupiedPt`: each
    /// helper's own real occupied pitch (Amendment v9, "Real pitch").
    public static func plan(
        owners: [PlacementValueScan.Classified],
        barRightEdge: Double,
        notchRightEdge: Double,
        targetOccupiedPt: Double,
        spacerOccupiedPt: Double,
        protectedOccupiedPt: Double
    ) -> Outcome {
        guard targetOccupiedPt > 0, spacerOccupiedPt > 0, protectedOccupiedPt > 0, barRightEdge > notchRightEdge else {
            return .refused(.noRoom(onBarOwnerCount: owners.count))
        }

        // Amendment v9: a scan this plan cannot trust refuses before any
        // geometry work at all -- deterministically, the leftmost such
        // owner first, so the reported reason is stable regardless of
        // `owners`' own incoming order.
        for owner in owners.sorted(by: { $0.minX < $1.minX }) {
            if let issue = owner.issue {
                return .refused(.ownerScanUncertain(minX: owner.minX, issue: issue))
            }
        }

        let totalOccupied = targetOccupiedPt + spacerOccupiedPt + protectedOccupiedPt
        let nearestOwnerMinX = owners.map(\.minX).min() ?? barRightEdge
        let groupRightEdge = min(barRightEdge, nearestOwnerMinX - marginPt)
        let groupLeftEdge = groupRightEdge - totalOccupied
        guard groupLeftEdge >= notchRightEdge else {
            return .refused(.noRoom(onBarOwnerCount: owners.count))
        }

        let targetMinX = groupLeftEdge
        let spacerMinX = targetMinX + targetOccupiedPt
        let protectedMinX = spacerMinX + spacerOccupiedPt

        let scannedMax = owners.flatMap(\.numericValues).max()
        let floor = max(historicalMaximumStoredValue, scannedMax ?? historicalMaximumStoredValue)

        return .planned(Result(
            targetMinX: targetMinX,
            spacerMinX: spacerMinX,
            protectedMinX: protectedMinX,
            targetPreferredPosition: floor + 3 * sortKeyStepPt,
            spacerPreferredPosition: floor + 2 * sortKeyStepPt,
            protectedPreferredPosition: floor + 1 * sortKeyStepPt,
            floorValue: floor
        ))
    }
}
