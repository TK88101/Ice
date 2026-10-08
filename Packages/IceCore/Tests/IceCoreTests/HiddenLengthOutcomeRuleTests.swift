import Testing
@testable import IceCore

/// One length's outcome for the walk, from the members' checks alone (plan
/// 2026-10-07-icebar-preference-hiding, D-b and the T3b design): a listed `«`
/// is not an input. `hiddenClean` is the only answer that verifies a length,
/// so every doubt must come out as something else.
@Suite("HiddenLengthOutcomeRule")
struct HiddenLengthOutcomeRuleTests {
    let clean = SectionItemCheck.checked(.hidden(folded: false))

    func outcome(_ checks: [SectionItemCheck], members: Int? = nil) -> HiddenLengthOutcome {
        HiddenLengthOutcomeRule.outcome(checks: checks, memberCount: members ?? checks.count)
    }

    @Test("every member hidden with no fold is clean")
    func allHiddenIsClean() {
        #expect(outcome([clean, clean]) == .hiddenClean)
    }

    @Test("a member whose check saw the fold go up with it is a fold")
    func pixelFoldIsFolded() {
        #expect(outcome([clean, .checked(.hidden(folded: true))]) == .folded)
    }

    @Test("a member still drawn is drawn")
    func stillDrawnIsDrawn() {
        #expect(outcome([clean, .checked(.stillDrawn)]) == .drawn)
    }

    @Test("a fold outranks a drawn member")
    func foldOutranksDrawn() {
        #expect(outcome([.checked(.hidden(folded: true)), .checked(.stillDrawn)]) == .folded)
    }

    @Test("a member that could not be assessed makes the length unknown", arguments: [
        SectionItemCheck.checked(.unverifiable(.captureUnstable)),
        SectionItemCheck.refusedAtBaseline(.noInk),
        SectionItemCheck.skipped(.cancelled),
        SectionItemCheck.skipped(.baselineStale),
    ])
    func unassessedMemberIsUnknown(check: SectionItemCheck) {
        #expect(outcome([clean, check]) == .unknown)
    }

    @Test("a member missing from the results is unknown")
    func missingMemberIsUnknown() {
        #expect(outcome([clean], members: 2) == .unknown)
    }

    @Test("more results than members is unknown")
    func extraResultIsUnknown() {
        #expect(outcome([clean, clean], members: 1) == .unknown)
    }

    @Test("no members is unknown, never clean")
    func noMembersIsUnknown() {
        #expect(outcome([]) == .unknown)
    }
}
