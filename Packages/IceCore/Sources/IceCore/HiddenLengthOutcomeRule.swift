/// What one length did to the hidden members, for the walk that looks for a
/// length (plan 2026-10-03-icebar-build, section 9.2; re-aimed by plan
/// 2026-10-07-icebar-preference-hiding, D-b and the T3b design): decided from
/// the detector's check of each member against its shown baseline, and from
/// nothing else. Whether `MenuBarAgent` lists a `«` is not an input: it is
/// recorded beside the checks and never changes an outcome.
public enum HiddenLengthOutcomeRule {
    /// - Parameters:
    ///   - checks: one result per member the detector reported on.
    ///   - memberCount: how many members were to be checked.
    public static func outcome(checks: [SectionItemCheck], memberCount: Int) -> HiddenLengthOutcome {
        // A member the pixels saw go under the fold: too short a length
        // (D-d), which is the walk's direction, not a veto by the `«`.
        if checks.contains(.checked(.hidden(folded: true))) { return .folded }
        if checks.contains(.checked(.stillDrawn)) { return .drawn }
        let allHidden = checks.allSatisfy { $0 == .checked(.hidden(folded: false)) }
        guard memberCount > 0, checks.count == memberCount, allHidden else { return .unknown }
        return .hiddenClean
    }
}
