// T0: one length's outcome from its brackets and its restore control.
import SpikeCore
import Testing

@Suite("T0: spike A reading rules")
struct SpikeRulesTests {
    static let clean = StepObservation(axChevron: false, pixelChevron: [.absent, .absent], membersSeen: [], visibleMissing: [], ambiguous: false)

    @Test("two clean brackets and a passing control: hidden clean")
    func hiddenClean() {
        #expect(SpikeRules.outcome([Self.clean, Self.clean], controlPassed: true) == .hiddenClean)
    }

    @Test("a « listed by AX in either bracket: folded, with whatever members were drawn")
    func foldedByAX() {
        var second = Self.clean
        second.axChevron = true
        second.membersSeen = ["ell"]
        #expect(SpikeRules.outcome([Self.clean, second], controlPassed: true) == .folded(drawn: ["ell"]))
    }

    @Test("a « seen in pixels only: folded")
    func foldedByPixels() {
        var first = Self.clean
        first.pixelChevron = [.absent, .present]
        #expect(SpikeRules.outcome([first, Self.clean], controlPassed: true) == .folded(drawn: []))
    }

    @Test("a member drawn in any bracket: drawn, ids sorted and unique")
    func drawn() {
        var first = Self.clean
        first.membersSeen = ["zed", "ell"]
        var second = Self.clean
        second.membersSeen = ["ell"]
        #expect(SpikeRules.outcome([first, second], controlPassed: true) == .drawn(["ell", "zed"]))
    }

    @Test("the restore control failing makes the length unknown, even when the brackets were clean")
    func controlFailed() {
        #expect(SpikeRules.outcome([Self.clean, Self.clean], controlPassed: false) == .unknown("restore control"))
    }

    @Test("a visible helper not drawn, an unevaluable chevron or an ambiguous read: unknown, never clean")
    func refusals() {
        var missing = Self.clean
        missing.visibleMissing = ["reference"]
        #expect(SpikeRules.outcome([missing], controlPassed: true) == .unknown("visible helper not drawn: reference"))
        var notEvaluable = Self.clean
        notEvaluable.pixelChevron = [.notEvaluable, .absent]
        #expect(SpikeRules.outcome([notEvaluable], controlPassed: true) == .unknown("chevron not evaluable"))
        var ambiguous = Self.clean
        ambiguous.ambiguous = true
        #expect(SpikeRules.outcome([ambiguous], controlPassed: true) == .unknown("ambiguous"))
        #expect(SpikeRules.outcome([], controlPassed: true) == .unknown("no bracket"))
    }

    @Test("a fold outranks a drawn member; a refusal outranks both")
    func precedence() {
        var folded = Self.clean
        folded.axChevron = true
        folded.membersSeen = ["ell"]
        folded.visibleMissing = ["alt"]
        #expect(SpikeRules.outcome([folded], controlPassed: true) == .unknown("visible helper not drawn: alt"))
    }

    @Test("isClean is true for hiddenClean only")
    func isClean() {
        #expect(StepOutcome.hiddenClean.isClean)
        #expect(!StepOutcome.folded(drawn: []).isClean)
        #expect(!StepOutcome.drawn(["ell"]).isClean)
        #expect(!StepOutcome.unknown("x").isClean)
    }
}
