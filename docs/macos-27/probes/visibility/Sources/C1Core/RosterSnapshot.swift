/// Section 3: "the roster snapshot -- the set of listed items, their order
/// and the capture indicator's frame, recorded at the end of the previous
/// passing reset check (for the first preflight: at the end of the
/// baseline)." `indicatorFrame` is carried here because that is where the
/// snapshot is defined; `BaselineEquivalence` reads it for its own
/// indicator-frame comparison, and section 3 condition 3 (the indicator
/// "has not moved since the previous read") compares against it too --
/// neither of those is itself one of the four roster outcomes below, which
/// section 3 condition 4 states purely in terms of the item list.
public struct RosterSnapshot: Equatable, Sendable {
    /// Every listed item's id, left to right.
    public let items: [String]
    public let indicatorFrame: BarFrame?

    public init(items: [String], indicatorFrame: BarFrame?) {
        self.items = items
        self.indicatorFrame = indicatorFrame
    }
}

/// Section 3 condition 4's four outcomes, plus the fail-closed fifth for no
/// snapshot at all.
public enum RosterComparison: Equatable, Sendable {
    case equal
    case appeared([String])
    case left([String])
    case reordered
    case missingSnapshot
}

public enum RosterSnapshotCheck {
    /// `nil` previous -> `.missingSnapshot` (section 3: "a missing snapshot
    /// fails closed"). Item-set changes are checked before order: an item
    /// that appeared or left is a more specific finding than "reordered",
    /// which only ever describes the same set in a new sequence. Appeared
    /// is checked before left when both happen in the same capture, since
    /// an appearance is the more surprising of the two to report first.
    public static func compare(current: RosterSnapshot, previous: RosterSnapshot?) -> RosterComparison {
        guard let previous else { return .missingSnapshot }
        guard current.items != previous.items else { return .equal }

        let previousSet = Set(previous.items)
        let appeared = current.items.filter { !previousSet.contains($0) }
        guard appeared.isEmpty else { return .appeared(appeared) }

        let currentSet = Set(current.items)
        let left = previous.items.filter { !currentSet.contains($0) }
        guard left.isEmpty else { return .left(left) }

        return .reordered
    }
}
