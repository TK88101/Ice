/// Amendment v8, "Placement gate": section 2's premise -- "each new item
/// lands at the left end" -- is false on the owner's bar (a fourth
/// cross-check found 1-3 owner items drawn left of the helpers in every
/// recorded run there). Right after the launches, before any baseline and
/// before any `length`, discovery must show Target, the spacer and
/// Protected each left of every on-bar owner item; otherwise the run ends
/// INCONCLUSIVE ("helpers not leftmost: N owner items left"), never a
/// safety stop -- this is not a C1 failure, it is this bar not supporting
/// C1's own geometry yet (Amendment v8's own wording).
///
/// Amendment v9, "Gate": the old gate only ever compared the *rightmost*
/// helper's own minX against the owner items, trusting `C1Discoverer`/
/// `PreflightOrderCheck` to keep the three helpers themselves in order.
/// crosscheck-rework8.json #1 found that under the plan's own old (nominal,
/// not occupied-pitch) widths, a real, packed layout could insert Target
/// between the spacer and Protected -- passing this gate, then failing
/// later with an unrelated, generic reason. `check` now requires the
/// internal order explicitly (`Target < spacer < Protected`), and reports
/// a helper missing its own frame (off the bar, or folded) as its own
/// distinct reason, never folded into "owner items left." `materiallyAgree`
/// is the "two consecutive, materially identical passes within a short
/// bound" the amendment also requires before the gate decides at all.
public enum PlacementGate {
    /// Why the gate refused. Amendment v9: three distinct top-level
    /// reasons, never conflated.
    public enum FailureReason: Equatable, Sendable {
        /// The internal order is wrong -- Target is not strictly left of
        /// the spacer, or the spacer is not strictly left of Protected.
        case misorder(targetMinX: Double, spacerMinX: Double, protectedMinX: Double)
        /// At least one helper has no AX frame at all -- off the bar
        /// entirely, or folded.
        case helperOffBarOrFolded
        /// The internal order is correct, but at least one on-bar owner
        /// item still sits left of Protected (the rightmost helper, once
        /// the order holds).
        case ownerItemsLeft(count: Int)
    }

    /// One discovery pass's own reading, as the gate needs it: each
    /// helper's own minX (`nil` when that helper has no AX frame at all --
    /// off the bar, or folded), and every *on-bar* owner item's minX
    /// (parked items already excluded by the caller, per Amendment v8's
    /// own first bullet).
    public struct Reading: Equatable, Sendable {
        public let targetMinX: Double?
        public let spacerMinX: Double?
        public let protectedMinX: Double?
        public let onBarOwnerMinXs: [Double]

        public init(targetMinX: Double?, spacerMinX: Double?, protectedMinX: Double?, onBarOwnerMinXs: [Double]) {
            self.targetMinX = targetMinX
            self.spacerMinX = spacerMinX
            self.protectedMinX = protectedMinX
            self.onBarOwnerMinXs = onBarOwnerMinXs
        }
    }

    /// Amendment v9: the default bound `materiallyAgree` compares within --
    /// generous enough to absorb a point or two of live rendering slop
    /// between two reads a few hundred milliseconds apart, tight enough
    /// that a real misorder or a real owner item never agrees with a
    /// corrected read by accident.
    public static let agreementTolerancePt = 1.0

    /// `nil` when the order holds (Target < spacer < Protected) and every
    /// on-bar owner item sits at or right of Protected; the first
    /// applicable `FailureReason` otherwise, checked in the order a caller
    /// needs to report a stable, specific reason: a missing helper frame
    /// first (nothing else can be decided without one), then the internal
    /// order, then owner items left.
    public static func check(_ reading: Reading) -> FailureReason? {
        guard let targetMinX = reading.targetMinX, let spacerMinX = reading.spacerMinX, let protectedMinX = reading.protectedMinX else {
            return .helperOffBarOrFolded
        }
        guard targetMinX < spacerMinX, spacerMinX < protectedMinX else {
            return .misorder(targetMinX: targetMinX, spacerMinX: spacerMinX, protectedMinX: protectedMinX)
        }
        let leftOfHelpers = reading.onBarOwnerMinXs.filter { $0 < protectedMinX }
        guard !leftOfHelpers.isEmpty else { return nil }
        return .ownerItemsLeft(count: leftOfHelpers.count)
    }

    /// Amendment v9: whether two readings, taken a short time apart, are
    /// close enough to call "the same layout" -- every helper's own minX
    /// agrees (or both are absent), and the on-bar owner minXs agree as
    /// sets (order-independent: a discovery pass makes no promise about
    /// listing order), each within `tolerancePt`.
    public static func materiallyAgree(_ a: Reading, _ b: Reading, tolerancePt: Double = agreementTolerancePt) -> Bool {
        guard closeOrBothNil(a.targetMinX, b.targetMinX, tolerancePt),
              closeOrBothNil(a.spacerMinX, b.spacerMinX, tolerancePt),
              closeOrBothNil(a.protectedMinX, b.protectedMinX, tolerancePt)
        else { return false }
        guard a.onBarOwnerMinXs.count == b.onBarOwnerMinXs.count else { return false }
        return zip(a.onBarOwnerMinXs.sorted(), b.onBarOwnerMinXs.sorted()).allSatisfy { abs($0 - $1) <= tolerancePt }
    }

    private static func closeOrBothNil(_ x: Double?, _ y: Double?, _ tolerancePt: Double) -> Bool {
        switch (x, y) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return abs(lhs - rhs) <= tolerancePt
        default: return false
        }
    }
}
