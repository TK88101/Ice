import Testing
@testable import IceCore

/// One length's outcome from what Ice read (plan 2026-10-03-icebar-build,
/// section 9.2). `hiddenClean` is the only answer that lets Ice rest at a
/// length, so every doubt must come out as something else.
@Suite("HiddenLengthOutcomeRule")
struct HiddenLengthOutcomeRuleTests {
    let clean = SectionItemCheck.checked(.hidden(folded: false))

    func outcome(chevron: Bool?, _ checks: [SectionItemCheck], members: Int? = nil) -> HiddenLengthOutcome {
        HiddenLengthOutcomeRule.outcome(chevronListed: chevron, checks: checks, memberCount: members ?? checks.count)
    }

    @Test("every member hidden with no fold is clean")
    func allHiddenIsClean() {
        #expect(outcome(chevron: false, [clean, clean]) == .hiddenClean)
    }

    @Test("an unreadable agent read is unknown, whatever the members say")
    func unreadableChevronIsUnknown() {
        #expect(outcome(chevron: nil, [clean]) == .unknown)
    }

    @Test("a listed chevron is a fold")
    func listedChevronIsFolded() {
        #expect(outcome(chevron: true, [clean]) == .folded)
    }

    @Test("a fold the pixels saw before Accessibility listed it is still a fold")
    func pixelFoldIsFolded() {
        #expect(outcome(chevron: false, [clean, .checked(.hidden(folded: true))]) == .folded)
    }

    @Test("a member still drawn is drawn")
    func stillDrawnIsDrawn() {
        #expect(outcome(chevron: false, [clean, .checked(.stillDrawn)]) == .drawn)
    }

    @Test("a fold outranks a drawn member")
    func foldOutranksDrawn() {
        #expect(outcome(chevron: true, [.checked(.stillDrawn)]) == .folded)
    }

    @Test("a member that could not be assessed makes the length unknown", arguments: [
        SectionItemCheck.checked(.unverifiable(.captureUnstable)),
        SectionItemCheck.refusedAtBaseline(.noInk),
        SectionItemCheck.skipped(.cancelled),
    ])
    func unassessedMemberIsUnknown(check: SectionItemCheck) {
        #expect(outcome(chevron: false, [clean, check]) == .unknown)
    }

    @Test("a member missing from the results is unknown")
    func missingMemberIsUnknown() {
        #expect(outcome(chevron: false, [clean], members: 2) == .unknown)
    }

    @Test("more results than members is unknown")
    func extraResultIsUnknown() {
        #expect(outcome(chevron: false, [clean, clean], members: 1) == .unknown)
    }

    @Test("no members is unknown, never clean")
    func noMembersIsUnknown() {
        #expect(outcome(chevron: false, []) == .unknown)
    }
}
