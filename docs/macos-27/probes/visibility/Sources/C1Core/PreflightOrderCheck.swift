/// Section 3 condition 1, taken immediately before every `length L`: "the
/// order from AX and from pixels agree: Target, then the spacer, leftmost
/// of every rendered item (user and system); Target is the only item left
/// of the spacer."
public enum PreflightOrderCheck {
    public enum Failure: Equatable, Sendable {
        /// The two readings of left-to-right order do not match -- an item
        /// moved, appeared or left between the two reads, or one reading
        /// simply saw a different bar than the other.
        case disagree
        case targetNotLeftmost
        /// Nothing else is left of the spacer -- but that also means the
        /// spacer itself must be found, immediately after Target.
        case targetNotAloneLeftOfSpacer
        /// C2 (k > 1): Target is leftmost, but the other hidden items are
        /// not the next ones, in order.
        case hiddenOutOfOrder
    }

    /// `axOrder`/`pixelOrder`: every rendered item's id, left to right, user
    /// and system alike. `nil` when both conditions hold.
    public static func check(axOrder: [String], pixelOrder: [String], target: String, spacer: String) -> Failure? {
        check(axOrder: axOrder, pixelOrder: pixelOrder, hidden: [target], spacer: spacer)
    }

    /// C2 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 1): `hidden` is the
    /// hidden section left to right, Target first; they must be the first
    /// `hidden.count` items, in order, then the spacer.
    public static func check(axOrder: [String], pixelOrder: [String], hidden: [String], spacer: String) -> Failure? {
        guard axOrder == pixelOrder else { return .disagree }
        guard let target = hidden.first, axOrder.first == target else { return .targetNotLeftmost }
        guard Array(axOrder.prefix(hidden.count)) == hidden else { return .hiddenOutOfOrder }
        guard axOrder.count > hidden.count, axOrder[hidden.count] == spacer else { return .targetNotAloneLeftOfSpacer }
        return nil
    }
}
