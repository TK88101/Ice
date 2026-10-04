/// D3 (plan 2026-10-03-icebar-build, section 9.2): which child of a process's
/// `AXExtrasMenuBar` an item key names, so Ice can press it. Anything but
/// exactly one answer is no target -- pressing a neighbour is worse than a
/// cell that does nothing.
public enum PressTargetRule {
    /// - Parameter identifiers: each child's `AXIdentifier` as read (`""`
    ///   when it has none), in child order; `nil` for a child that is not an
    ///   `AXMenuBarItem`.
    public static func index(for key: ItemKey, identifiers: [String?]) -> Int? {
        func names(_ index: Int) -> Bool {
            identifiers[index].map(IdentifierText.trimmed) == key.identifier
        }
        if let childIndex = key.childIndex {
            guard identifiers.indices.contains(childIndex), names(childIndex) else { return nil }
            return childIndex
        }
        let matches = identifiers.indices.filter(names)
        return matches.count == 1 ? matches[0] : nil
    }
}

/// What a finished `AXPress` call amounts to (D3, section 9.5). No claim that
/// anything opened: only a failure is acted on (the cell is disabled).
public enum PressOutcome: Equatable, Sendable {
    case accepted
    case failed

    /// A press that opens a menu returns only when the menu closes (T0 spike
    /// B), so a messaging timeout after at least this long is that menu
    /// staying up, not a failure. INFERRED bound: T0's first sign of the menu
    /// came 10.5-14.5 ms after the press.
    public static let minimumMenuSeconds = 1.0

    public static func classify(succeeded: Bool, timedOut: Bool, elapsed: Double) -> PressOutcome {
        if succeeded { return .accepted }
        return timedOut && elapsed >= minimumMenuSeconds ? .accepted : .failed
    }
}
