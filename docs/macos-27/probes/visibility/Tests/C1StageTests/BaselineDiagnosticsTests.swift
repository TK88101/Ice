// Evidence-only diagnostics for step 3's own rest baseline: what the baseline
// saw when it did not accept, so a "fold is not absent" abort says why.
import C1Stage
import IceCore
import Testing

@Suite("BaselineDiagnostics")
struct BaselineDiagnosticsTests {
    private let geometry = BarGeometry(widthPt: 1728, heightPt: 32, scale: 2, notch: PtSpan(lo: 771.5, hi: 956.5))

    @Test("an unreadable fold with no ink records the fold, the missing ink, and every rejection by reason")
    func unreadableWithoutInk() {
        let result = BaselineResult(
            templates: [:],
            rejections: ["b": .inkUnknown, "a": .readsDisagree],
            ink: nil,
            agentFrames: [],
            foldAtBaseline: .unreadable,
            geometry: geometry
        )
        let fields = BaselineDiagnostics.fields(result, parameters: .preRegistered)

        #expect(fields["fold"] as? String == "unreadable")
        #expect(fields["inkCalibrated"] as? Bool == false)
        #expect(fields["accepted"] as? Int == 0)
        #expect(fields["rejections"] as? [String] == ["a: readsDisagree", "b: inkUnknown"])
        #expect(fields["agentFrames"] as? [[Double]] == [])
        #expect(fields["chevronSizedOnBar"] as? Int == 0)
        #expect(fields["notchHi"] as? Double == 956.5)
    }

    @Test("agent frames are recorded as [minX, minY, width], and only on-bar chevron-sized ones are counted")
    func agentFramesAndChevronCount() {
        let result = BaselineResult(
            templates: [:],
            rejections: [:],
            ink: nil,
            agentFrames: [
                AgentFrame(minX: 1600, minY: 0, width: 17.5),
                AgentFrame(minX: 1650, minY: 0, width: 40),
                AgentFrame(minX: 1700, minY: 40, width: 17.5),
            ],
            foldAtBaseline: .present,
            geometry: geometry
        )
        let fields = BaselineDiagnostics.fields(result, parameters: .preRegistered)

        #expect(fields["fold"] as? String == "present")
        #expect(fields["agentFrames"] as? [[Double]] == [[1600, 0, 17.5], [1650, 0, 40], [1700, 40, 17.5]])
        #expect(fields["chevronSizedOnBar"] as? Int == 1)
    }

    @Test("an absent fold with no notch records notchHi as 0")
    func absentWithoutNotch() {
        let flat = BarGeometry(widthPt: 1440, heightPt: 24, scale: 2, notch: nil)
        let result = BaselineResult(templates: [:], rejections: [:], ink: nil, agentFrames: [], foldAtBaseline: .absent, geometry: flat)
        let fields = BaselineDiagnostics.fields(result, parameters: .preRegistered)

        #expect(fields["fold"] as? String == "absent")
        #expect(fields["notchHi"] as? Double == 0)
    }
}
