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
    }

    /// `axOrder`/`pixelOrder`: every rendered item's id, left to right, user
    /// and system alike. `nil` when both conditions hold.
    public static func check(axOrder: [String], pixelOrder: [String], target: String, spacer: String) -> Failure? {
        guard axOrder == pixelOrder else { return .disagree }
        guard axOrder.first == target else { return .targetNotLeftmost }
        guard axOrder.count > 1, axOrder[1] == spacer else { return .targetNotAloneLeftOfSpacer }
        return nil
    }
}
