import IceCore
import Testing
@testable import MenuBarDiscovery

/// Proves the walk *obeys* `AttributeWalkPolicy`, which the policy's own tests
/// cannot: a pure rule can say "go on" and an adapter can still fail to ask for
/// anything else. So the reads are scripted here and the trace is the assertion
/// -- which AX attributes were asked, in which order (2026-09-25 plan, T-2).
///
/// What this cannot reach is the live boundary itself: the AX call, the
/// messaging timeout, the error mapping, the `AXValue` conversion, the binding
/// of the right child. `mbdiscover`'s smoke run is what covers that.
@Suite("LiveExtrasReader: the attribute walk")
struct LiveExtrasReaderWalkTests {
    private let timeout = ReadClassifier.defaultTimeout

    /// Records every attribute asked for, in order, and answers from a script
    /// keyed by AX attribute name. Anything not in the script reads clean.
    private final class Script {
        var asked = [String]()
        private let answers: [String: LiveExtrasReader.TimedRead<String>]
        private let frame: LiveExtrasReader.TimedRead<BarRect>

        init(
            answers: [String: LiveExtrasReader.TimedRead<String>] = [:],
            frame: LiveExtrasReader.TimedRead<BarRect> = .init(value: BarRect(minX: 100, minY: 4, width: 30, height: 24), rawError: "success", elapsed: 0.001)
        ) {
            self.answers = answers
            self.frame = frame
        }

        func readString(_ index: Int, _ axAttribute: String) -> LiveExtrasReader.TimedRead<String> {
            asked.append(axAttribute)
            return answers[axAttribute] ?? .init(value: "ok", rawError: "success", elapsed: 0.001)
        }

        func readFrame(_ index: Int) -> LiveExtrasReader.TimedRead<BarRect> {
            asked.append("AXFrame")
            return frame
        }
    }

    private func walk(_ script: Script, readsLabels: Bool = true) -> (record: ExtrasRecord, stop: Bool) {
        LiveExtrasReader.readChild(
            index: 0,
            readsLabels: readsLabels,
            timeout: timeout,
            readString: script.readString,
            readFrame: script.readFrame
        )
    }

    // MARK: - the tolerated case really does go on

    @Test("a fast identifier failure is recorded and the walk goes on to ask for the frame")
    func toleratedIdentifierFailureStillAsksTheFrame() {
        let script = Script(answers: ["AXIdentifier": .init(value: nil, rawError: "failure", elapsed: 0.001)])
        let (record, stop) = walk(script)

        #expect(script.asked == ["AXRole", "AXIdentifier", "AXTitle", "AXDescription", "AXHelp", "AXFrame"])
        #expect(record.identifier.error == "failure")
        #expect(record.frame.error == "success")
        #expect(record.frame.value != nil)
        #expect(stop == false)
    }

    @Test("the same identifier failure taken slowly stops, and nothing after it is asked")
    func slowIdentifierFailureStopsTheWalk() {
        let script = Script(answers: ["AXIdentifier": .init(value: nil, rawError: "failure", elapsed: 0.24)])
        let (record, stop) = walk(script)

        #expect(script.asked == ["AXRole", "AXIdentifier"])
        #expect(record.frame.error == "notAttempted")
        #expect(stop == true)
    }

    @Test("a hard error on the role stops before the identifier is ever asked")
    func roleFailureStopsFirst() {
        let script = Script(answers: ["AXRole": .init(value: nil, rawError: "apiDisabled", elapsed: 0.001)])
        let (record, stop) = walk(script)

        #expect(script.asked == ["AXRole"])
        #expect(record.identifier.error == "notAttempted")
        #expect(record.frame.error == "notAttempted")
        #expect(stop == true)
    }

    @Test("a hard error on the frame stops the process's walk, with everything before it recorded")
    func frameFailureStopsTheWalk() {
        let script = Script(frame: .init(value: nil, rawError: "apiDisabled", elapsed: 0.001))
        let (record, stop) = walk(script)

        #expect(script.asked == ["AXRole", "AXIdentifier", "AXTitle", "AXDescription", "AXHelp", "AXFrame"])
        #expect(record.role.error == "success")
        #expect(record.frame.error == "apiDisabled")
        #expect(stop == true)
    }

    // MARK: - the slow-success normalization, at the seam

    @Test("a slow successful read is recorded as cannotComplete with its value dropped, and stops")
    func slowSuccessDropsItsValue() {
        let script = Script(answers: ["AXRole": .init(value: "AXMenuBarItem", rawError: "success", elapsed: 0.25)])
        let (record, stop) = walk(script)

        #expect(record.role.error == "cannotComplete")
        #expect(record.role.value == nil)
        #expect(stop == true)
    }

    @Test("a slow successful frame read drops its rect too")
    func slowSuccessFrameDropsItsRect() {
        let script = Script(frame: .init(value: BarRect(minX: 1, minY: 2, width: 3, height: 4), rawError: "success", elapsed: 0.25))
        let (record, stop) = walk(script)

        #expect(record.frame.error == "cannotComplete")
        #expect(record.frame.value == nil)
        #expect(stop == true)
    }

    // MARK: - the labels, unchanged

    @Test("with labels off the three label attributes are never asked, and the frame still is")
    func labelsOffSkipsThreeCalls() {
        let script = Script()
        let (record, stop) = walk(script, readsLabels: false)

        #expect(script.asked == ["AXRole", "AXIdentifier", "AXFrame"])
        #expect(record.title.error == "notAttempted")
        #expect(record.description.error == "notAttempted")
        #expect(record.help.error == "notAttempted")
        #expect(stop == false)
    }

    @Test("with labels off a tolerated identifier failure still reaches the frame")
    func labelsOffStillReachesTheFrameAfterTheToleratedError() {
        let script = Script(answers: ["AXIdentifier": .init(value: nil, rawError: "failure", elapsed: 0.001)])
        let (record, stop) = walk(script, readsLabels: false)

        #expect(script.asked == ["AXRole", "AXIdentifier", "AXFrame"])
        #expect(record.frame.value != nil)
        #expect(stop == false)
    }

    @Test("a label call that fails hard still stops the child, as it did before")
    func labelFailureStillStops() {
        let script = Script(answers: ["AXTitle": .init(value: nil, rawError: "apiDisabled", elapsed: 0.001)])
        let (record, stop) = walk(script)

        #expect(script.asked == ["AXRole", "AXIdentifier", "AXTitle"])
        #expect(record.frame.error == "notAttempted")
        #expect(stop == true)
    }

    // MARK: - the harmless errors

    @Test("an unsupported identifier is harmless and changes nothing about the walk")
    func unsupportedIdentifierProceeds() {
        let script = Script(answers: ["AXIdentifier": .init(value: nil, rawError: "attributeUnsupported", elapsed: 0.001)])
        let (record, stop) = walk(script)

        #expect(script.asked == ["AXRole", "AXIdentifier", "AXTitle", "AXDescription", "AXHelp", "AXFrame"])
        #expect(record.identifier.error == "attributeUnsupported")
        #expect(stop == false)
    }
}
