import Testing
@testable import IceCore

/// Which child of an `AXExtrasMenuBar` an item key names (plan
/// 2026-10-03-icebar-build, section 9.2). A wrong answer presses another
/// item, so anything but exactly one match is no target.
@Suite("PressTargetRule")
struct PressTargetRuleTests {
    func key(_ identifier: String, childIndex: Int? = nil) -> ItemKey {
        ItemKey(namespace: "com.example.app", identifier: identifier, pid: 42, childIndex: childIndex)
    }

    @Test("a declared key names the one child with its identifier")
    func declaredKeyMatchesOneChild() {
        #expect(PressTargetRule.index(for: key("clock"), identifiers: ["wifi", "clock", "battery"]) == 1)
    }

    @Test("identifiers are trimmed as they were when the key was made")
    func identifiersAreTrimmed() {
        #expect(PressTargetRule.index(for: key("clock"), identifiers: ["  clock \n"]) == 0)
    }

    @Test("an unnamed key names the one child with an empty identifier")
    func unnamedKeyMatchesEmptyIdentifier() {
        #expect(PressTargetRule.index(for: key(""), identifiers: ["wifi", ""]) == 1)
    }

    @Test("no child with the identifier is no target")
    func noMatchIsNil() {
        #expect(PressTargetRule.index(for: key("clock"), identifiers: ["wifi"]) == nil)
    }

    @Test("several children with the identifier are no target for a declared key")
    func severalMatchesIsNil() {
        #expect(PressTargetRule.index(for: key("clock"), identifiers: ["clock", "clock"]) == nil)
    }

    @Test("a child that is not a menu bar item is never a target")
    func nonItemChildIsSkipped() {
        #expect(PressTargetRule.index(for: key("clock"), identifiers: [nil, "clock"]) == 1)
        #expect(PressTargetRule.index(for: key(""), identifiers: [nil]) == nil)
    }

    @Test("a positional key names its child index when the identifier still matches")
    func positionalKeyUsesChildIndex() {
        #expect(PressTargetRule.index(for: key("clock", childIndex: 1), identifiers: ["clock", "clock"]) == 1)
    }

    @Test("a positional key out of range, or on a child that changed, is no target", arguments: [
        ["clock"],
        ["clock", "wifi"],
        ["clock", nil],
    ])
    func positionalKeyMismatchIsNil(identifiers: [String?]) {
        #expect(PressTargetRule.index(for: key("clock", childIndex: 1), identifiers: identifiers) == nil)
    }

    @Test("a negative child index is no target")
    func negativeChildIndexIsNil() {
        #expect(PressTargetRule.index(for: key("clock", childIndex: -1), identifiers: ["clock"]) == nil)
    }
}

/// What a finished `AXPress` call says (plan 2026-10-03-icebar-build, 9.5):
/// only a failure disables the cell, and a call that ran into its messaging
/// timeout after holding a menu open is not one.
@Suite("PressOutcome")
struct PressOutcomeTests {
    @Test("a successful press is accepted, however long it took", arguments: [0.01, 5.0])
    func successIsAccepted(elapsed: Double) {
        #expect(PressOutcome.classify(succeeded: true, timedOut: false, elapsed: elapsed) == .accepted)
    }

    @Test("a timeout after a menu was up long enough is accepted")
    func slowTimeoutIsAccepted() {
        #expect(PressOutcome.classify(succeeded: false, timedOut: true, elapsed: PressOutcome.minimumMenuSeconds) == .accepted)
    }

    @Test("a quick timeout is a failure")
    func quickTimeoutFails() {
        #expect(PressOutcome.classify(succeeded: false, timedOut: true, elapsed: 0.2) == .failed)
    }

    @Test("any other error is a failure, quick or slow", arguments: [0.01, 5.0])
    func otherErrorFails(elapsed: Double) {
        #expect(PressOutcome.classify(succeeded: false, timedOut: false, elapsed: elapsed) == .failed)
    }
}
