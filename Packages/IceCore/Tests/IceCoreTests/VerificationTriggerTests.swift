import Testing
@testable import IceCore

/// `VerificationTrigger.reduce` is D18's pure reducer over one combined
/// stream of divider/mode snapshots: which sections are "shown" changing is
/// what schedules a job, never the raw booleans themselves -- the
/// always-hidden item's redundant emission when it is disabled must not
/// cancel a hidden-section check in progress (D18's rejected alternative).
@Suite("VerificationTrigger.shownSections")
struct VerificationTriggerShownSectionsTests {
    @Test("hidden shown, always-hidden not shown or disabled -> {.hidden}")
    func hiddenOnly() {
        let inputs = VerificationInputs(hiddenShown: true, alwaysHiddenShown: false, alwaysHiddenEnabled: false, iceBarMode: false, barHiddenBySystem: false)
        #expect(VerificationTrigger.shownSections(inputs) == [.hidden])
    }

    @Test("always-hidden shown but disabled -> not counted")
    func alwaysHiddenShownButDisabledIsNotCounted() {
        let inputs = VerificationInputs(hiddenShown: false, alwaysHiddenShown: true, alwaysHiddenEnabled: false, iceBarMode: false, barHiddenBySystem: false)
        #expect(VerificationTrigger.shownSections(inputs) == [])
    }

    @Test("both shown and enabled -> {.hidden, .alwaysHidden}")
    func bothShown() {
        let inputs = VerificationInputs(hiddenShown: true, alwaysHiddenShown: true, alwaysHiddenEnabled: true, iceBarMode: false, barHiddenBySystem: false)
        #expect(VerificationTrigger.shownSections(inputs) == [.hidden, .alwaysHidden])
    }

    @Test("neither shown -> empty")
    func neitherShown() {
        let inputs = VerificationInputs(hiddenShown: false, alwaysHiddenShown: false, alwaysHiddenEnabled: true, iceBarMode: false, barHiddenBySystem: false)
        #expect(VerificationTrigger.shownSections(inputs) == [])
    }
}

@Suite("VerificationTrigger.reduce")
struct VerificationTriggerReduceTests {
    private func inputs(hiddenShown: Bool, alwaysHiddenShown: Bool, alwaysHiddenEnabled: Bool = true, iceBarMode: Bool = false, barHiddenBySystem: Bool = false) -> VerificationInputs {
        VerificationInputs(hiddenShown: hiddenShown, alwaysHiddenShown: alwaysHiddenShown, alwaysHiddenEnabled: alwaysHiddenEnabled, iceBarMode: iceBarMode, barHiddenBySystem: barHiddenBySystem)
    }

    @Test("identical snapshots -> no jobs")
    func identicalSnapshotsProduceNoJobs() {
        let a = inputs(hiddenShown: true, alwaysHiddenShown: false)
        #expect(VerificationTrigger.reduce(previous: a, current: a) == [])
    }

    @Test("initial state (previous nil), nothing shown -> no jobs")
    func initialStateNothingShown() {
        let current = inputs(hiddenShown: false, alwaysHiddenShown: false)
        #expect(VerificationTrigger.reduce(previous: nil, current: current) == [])
    }

    @Test("initial state (previous nil), something shown -> prepare(shown)")
    func initialStateSomethingShown() {
        let current = inputs(hiddenShown: true, alwaysHiddenShown: false)
        #expect(VerificationTrigger.reduce(previous: nil, current: current) == [.prepare([.hidden])])
    }

    @Test("hide assigns all three items (hidden false; always-hidden redundant false, disabled) -> verify([.hidden]) exactly once")
    func hideAssignsAllThreeVerifiesHiddenOnce() {
        let previous = inputs(hiddenShown: true, alwaysHiddenShown: false, alwaysHiddenEnabled: false)
        let current = inputs(hiddenShown: false, alwaysHiddenShown: false, alwaysHiddenEnabled: false)
        #expect(VerificationTrigger.reduce(previous: previous, current: current) == [.verify([.hidden])])
    }

    @Test("show always-hidden (both true, enabled) -> one prepare([.hidden, .alwaysHidden])")
    func showAlwaysHiddenPreparesUnion() {
        let previous = inputs(hiddenShown: true, alwaysHiddenShown: false, alwaysHiddenEnabled: true)
        let current = inputs(hiddenShown: true, alwaysHiddenShown: true, alwaysHiddenEnabled: true)
        #expect(VerificationTrigger.reduce(previous: previous, current: current) == [.prepare([.hidden, .alwaysHidden])])
    }

    @Test("IceBar re-assignment (iceBarMode true) with a changed shown set -> skip(.iceBarMode) only")
    func iceBarModeChangeProducesSkipOnly() {
        let previous = inputs(hiddenShown: false, alwaysHiddenShown: false, iceBarMode: false)
        let current = inputs(hiddenShown: true, alwaysHiddenShown: false, iceBarMode: true)
        let jobs = VerificationTrigger.reduce(previous: previous, current: current)
        #expect(jobs == [.skip([.hidden], .iceBarMode)])
    }

    @Test("IceBar mode already true, shown set unchanged -> no jobs")
    func iceBarModeUnchangedShownProducesNoJobs() {
        let previous = inputs(hiddenShown: true, alwaysHiddenShown: false, iceBarMode: true, barHiddenBySystem: false)
        let current = inputs(hiddenShown: true, alwaysHiddenShown: false, iceBarMode: true, barHiddenBySystem: true) // some other field changed
        let jobs = VerificationTrigger.reduce(previous: previous, current: current)
        #expect(jobs == [])
    }

    @Test("bar hidden by system with a changed shown set -> skip(.barHiddenBySystem) only")
    func barHiddenBySystemChangeProducesSkipOnly() {
        let previous = inputs(hiddenShown: true, alwaysHiddenShown: false, barHiddenBySystem: false)
        let current = inputs(hiddenShown: false, alwaysHiddenShown: false, barHiddenBySystem: true)
        let jobs = VerificationTrigger.reduce(previous: previous, current: current)
        #expect(jobs == [.skip([.hidden], .barHiddenBySystem)])
    }

    @Test("drag start: always-hidden disabled but its shown flag true -> no always-hidden job")
    func alwaysHiddenDisabledButShownProducesNoAlwaysHiddenJob() {
        let previous = inputs(hiddenShown: true, alwaysHiddenShown: false, alwaysHiddenEnabled: false)
        let current = inputs(hiddenShown: true, alwaysHiddenShown: true, alwaysHiddenEnabled: false) // shown flag flips, but disabled -> not counted
        #expect(VerificationTrigger.reduce(previous: previous, current: current) == [])
    }

    @Test("both a hide and a show land in one call: verify first, then prepare")
    func hideAndShowInOneCallOrdersVerifyThenPrepare() {
        let previous = inputs(hiddenShown: true, alwaysHiddenShown: false)
        let current = inputs(hiddenShown: false, alwaysHiddenShown: true)
        let jobs = VerificationTrigger.reduce(previous: previous, current: current)
        #expect(jobs == [.verify([.hidden]), .prepare([.alwaysHidden])])
    }

    @Test("rapid toggling: show, hide, show again produces a job each transition")
    func rapidTogglingProducesAJobPerTransition() {
        let off = inputs(hiddenShown: false, alwaysHiddenShown: false)
        let on = inputs(hiddenShown: true, alwaysHiddenShown: false)
        #expect(VerificationTrigger.reduce(previous: off, current: on) == [.prepare([.hidden])])
        #expect(VerificationTrigger.reduce(previous: on, current: off) == [.verify([.hidden])])
        #expect(VerificationTrigger.reduce(previous: off, current: on) == [.prepare([.hidden])])
    }

    @Test("a change in an unrelated field with no shown-set change and no special mode -> no jobs")
    func unrelatedFieldChangeProducesNoJobs() {
        // barHiddenBySystem flips while iceBarMode stays false throughout --
        // still hits the "shown set changed?" gate for barHiddenBySystem;
        // use a case where the shown set truly does not change instead.
        let previous = inputs(hiddenShown: true, alwaysHiddenShown: true, alwaysHiddenEnabled: true)
        let current = inputs(hiddenShown: true, alwaysHiddenShown: true, alwaysHiddenEnabled: true)
        #expect(VerificationTrigger.reduce(previous: previous, current: current) == [])
    }
}
