/// Amendment v8, "Placement by the helpers' own preferred position"
/// (option A): the pure geometry behind the write. `StageC1`'s own new
/// pre-launch step (`step1bPlacementPlan`, `StageC1Placement.swift`) feeds
/// this from one fresh discovery pass, before any helper exists -- the
/// on-bar owner items already there (parked items already excluded by the
/// caller filtering to `.onBar`, per Amendment v8's first bullet -- there
/// is no helper yet at that point to filter out either), the bar's own
/// geometry, and each helper's own width. The result is only ever numbers
/// recorded to evidence and written into the helpers' own defaults
/// domains -- a plan, never a promise: whether macOS 27 actually honours
/// the write for a freshly created item is unverified (SEAM-AUDIT.md
/// documents it as a modelled assumption), and `step2bPlacementGate`,
/// after the real launches, is what actually decides.
public enum PlacementPlan {
    /// The gap this plan leaves between the group's own right edge
    /// (Protected's own trailing edge) and the nearest on-bar owner item's
    /// minX -- deliberately larger than `PlacementGate`'s own strict "<"
    /// comparison needs, so a few points of live rendering slop cannot
    /// turn a real PASS into a gate failure.
    public static let marginPt = 6.0

    /// Left-to-right minX for each helper (bar-space points), and the
    /// "NSStatusItem Preferred Position" value to write for each --
    /// `barRightEdge - minX`, per the INFERRED right-edge-distance
    /// assumption (SEAM-AUDIT.md): unverified whether macOS 27 honours it
    /// for a newly created item at all, only that this is what Ice's own
    /// `ControlItemDefaults` key is named and shaped like.
    public struct Result: Equatable, Sendable {
        public let targetMinX: Double
        public let spacerMinX: Double
        public let protectedMinX: Double
        public let targetPreferredPosition: Double
        public let spacerPreferredPosition: Double
        public let protectedPreferredPosition: Double

        public init(
            targetMinX: Double,
            spacerMinX: Double,
            protectedMinX: Double,
            targetPreferredPosition: Double,
            spacerPreferredPosition: Double,
            protectedPreferredPosition: Double
        ) {
            self.targetMinX = targetMinX
            self.spacerMinX = spacerMinX
            self.protectedMinX = protectedMinX
            self.targetPreferredPosition = targetPreferredPosition
            self.spacerPreferredPosition = spacerPreferredPosition
            self.protectedPreferredPosition = protectedPreferredPosition
        }
    }

    /// `onBarOwnerMinXs`: every on-bar owner item's minX already on the
    /// bar (whatever order). `barRightEdge`: the bar's own width in points
    /// (`BarGeometry.widthPt`). `notchRightEdge`: the camera housing's own
    /// right edge in bar-space points (`BarGeometry.notch?.hi`), or `0`
    /// when there is none -- the leftmost room this plan may ever use.
    /// `nil` (refuse) when the three helpers, laid out contiguously left
    /// of the nearest owner item (or the bar's own right edge, when there
    /// is no owner item at all) with `marginPt` to spare, would not fit
    /// clear of the notch.
    public static func plan(
        onBarOwnerMinXs: [Double],
        barRightEdge: Double,
        notchRightEdge: Double,
        targetWidthPt: Double,
        spacerWidthPt: Double,
        protectedWidthPt: Double
    ) -> Result? {
        guard targetWidthPt > 0, spacerWidthPt > 0, protectedWidthPt > 0 else { return nil }
        guard barRightEdge > notchRightEdge else { return nil }

        let totalWidth = targetWidthPt + spacerWidthPt + protectedWidthPt
        let nearestOwnerMinX = onBarOwnerMinXs.min() ?? barRightEdge
        let groupRightEdge = min(barRightEdge, nearestOwnerMinX - marginPt)
        let groupLeftEdge = groupRightEdge - totalWidth
        guard groupLeftEdge >= notchRightEdge else { return nil }

        let targetMinX = groupLeftEdge
        let spacerMinX = targetMinX + targetWidthPt
        let protectedMinX = spacerMinX + spacerWidthPt
        return Result(
            targetMinX: targetMinX,
            spacerMinX: spacerMinX,
            protectedMinX: protectedMinX,
            targetPreferredPosition: barRightEdge - targetMinX,
            spacerPreferredPosition: barRightEdge - spacerMinX,
            protectedPreferredPosition: barRightEdge - protectedMinX
        )
    }
}
