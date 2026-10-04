/// D1's observation source, the deciding half (plan 2026-10-03-icebar-build,
/// section 9.2): what one length did to the bar, from the two things Ice read
/// at that length -- whether `MenuBarAgent` lists a `«`, and the detector's
/// check of every hidden-section member against its shown baseline.
public enum HiddenLengthOutcomeRule {
    /// - Parameters:
    ///   - chevronListed: whether an on-bar `MenuBarAgent` frame is the
    ///     chevron; `nil` when the agent could not be read.
    ///   - checks: one result per member the detector reported on.
    ///   - memberCount: how many members the hidden section has.
    public static func outcome(chevronListed: Bool?, checks: [SectionItemCheck], memberCount: Int) -> HiddenLengthOutcome {
        guard let chevronListed else { return .unknown }
        // A fold the pixels saw counts even before Accessibility lists it.
        if chevronListed || checks.contains(.checked(.hidden(folded: true))) { return .folded }
        if checks.contains(.checked(.stillDrawn)) { return .drawn }
        let allHidden = checks.allSatisfy { $0 == .checked(.hidden(folded: false)) }
        guard memberCount > 0, checks.count == memberCount, allHidden else { return .unknown }
        return .hiddenClean
    }
}
