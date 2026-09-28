import C2Core
import Testing

@Suite("C2Evidence")
struct C2EvidenceTests {
    @Test("reading names round-trip; an unknown name is nil")
    func readingNames() {
        for reading in [C2Reading.hiddenNoFold, .hiddenFolded, .stillDrawn, .notShown] {
            #expect(C2Reading(name: "\(reading)") == reading)
        }
        #expect(C2Reading(name: "hidden") == nil)
    }

    @Test("process status from its verdict; a missing verdict is treated as a safety stop")
    func statusFromVerdict() {
        #expect(C2ProcessResult.Status(verdict: "pass") == .completed)
        #expect(C2ProcessResult.Status(verdict: "safetyStopNeedingAttention") == .safetyStop)
        #expect(C2ProcessResult.Status(verdict: "safetyStop") == .safetyStop)
        #expect(C2ProcessResult.Status(verdict: "inconclusive(\"measured 1 of 2 lengths\")") == .inconclusive("inconclusive(\"measured 1 of 2 lengths\")"))
        #expect(C2ProcessResult.Status(verdict: nil) == .safetyStop)
    }

    @Test("a manifest verifies only when non-empty and identical")
    func manifestVerify() {
        #expect(C2Manifest.verify(recorded: ["a": "1"], actual: ["a": "1"]))
        #expect(!C2Manifest.verify(recorded: ["a": "1"], actual: ["a": "2"]))
        #expect(!C2Manifest.verify(recorded: ["a": "1"], actual: ["a": "1", "b": "2"]))
        #expect(!C2Manifest.verify(recorded: [:], actual: [:]))
    }
}
