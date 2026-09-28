// C2 T3 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 3): one cycle's
// reading of the whole hidden section from its items' own readings.
import Testing
@testable import C1Core

@Suite("HiddenSectionReading")
struct HiddenSectionReadingTests {
    @Test("one item: its own reading, unchanged (C1)")
    func single() {
        for reading in [TargetReading.hidden(folded: false), .hidden(folded: true), .stillDrawn, .refused] {
            #expect(TargetReading.section([reading]) == reading)
        }
    }

    @Test("every item agreeing -> that reading")
    func agreeing() {
        #expect(TargetReading.section([.hidden(folded: false), .hidden(folded: false), .hidden(folded: false)]) == .hidden(folded: false))
        #expect(TargetReading.section([.stillDrawn, .stillDrawn]) == .stillDrawn)
        #expect(TargetReading.section([.hidden(folded: true), .hidden(folded: true)]) == .hidden(folded: true))
    }

    @Test("any mix, any refusal, or no item at all -> refused (never a partial hide)")
    func mixed() {
        #expect(TargetReading.section([.hidden(folded: false), .stillDrawn]) == .refused)
        #expect(TargetReading.section([.hidden(folded: false), .hidden(folded: true)]) == .refused)
        #expect(TargetReading.section([.hidden(folded: false), .refused]) == .refused)
        #expect(TargetReading.section([]) == .refused)
    }
}
