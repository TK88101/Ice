import ApplicationServices
import Foundation
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

    @Test("a fast identifier failure is recorded, its value dropped, and the walk goes on to ask for the frame")
    func toleratedIdentifierFailureStillAsksTheFrame() {
        // The script answers with a value *and* the error, which is the case
        // `.discard` exists for: if Accessibility ever populated the
        // out-parameter while returning the error, keeping it would key the item
        // on a string a failed call produced.
        let script = Script(answers: ["AXIdentifier": .init(value: "leaked", rawError: "failure", elapsed: 0.001)])
        let (record, stop) = walk(script)

        #expect(script.asked == ["AXRole", "AXIdentifier", "AXTitle", "AXDescription", "AXHelp", "AXFrame"])
        #expect(record.identifier.error == "failure")
        #expect(record.identifier.value == nil)
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

/// The walk over the children snapshot (2026-09-25 responsiveness-quarantine
/// plan, 3.7-3.8): the count comes from the value Accessibility returned, never
/// from what Swift could cast; the caller's interrupt is polled before every
/// child; a snapshot over the cap is not walked at all; and the `RawRead` is
/// built right here, so no call site ever handles a count it could get wrong
/// (the identifier-failure plan's section 9, item 3).
@Suite("LiveExtrasReader: walking the children snapshot")
struct LiveExtrasReaderWalkChildrenTests {
    private let process = testProcess(pid: 42)

    /// A real `AXUIElement`, made for this very process -- creating one reads
    /// nothing and touches nobody's menu bar.
    private var element: AXUIElement { AXUIElementCreateApplication(getpid()) }

    /// Walks `value`, recording which children were asked for; `stopAt` makes
    /// that child's read report a policy stop.
    private func walk(
        _ value: CFTypeRef?,
        cap: Int = LiveExtrasReader.maxChildren,
        interruptAfter: Int? = nil,
        stopAt: Int? = nil
    ) -> (raw: RawRead, asked: [Int]) {
        var asked = [Int]()
        var polls = 0
        let raw = LiveExtrasReader.walkChildren(
            process: process,
            extrasElapsed: 0.011,
            childrenElapsed: 0.012,
            childrenValue: value,
            cap: cap,
            interrupt: {
                defer { polls += 1 }
                return interruptAfter.map { polls >= $0 } ?? false
            },
            readChild: { index, _ in
                asked.append(index)
                return (extrasRecord(childIndex: index, identifier: "c\(index)", minX: Double(100 + 30 * index)), index == stopAt)
            }
        )
        return (raw, asked)
    }

    @Test("w1: a mixed array and one record -- childCount 2, records 1, and the classifier calls it a partial walk")
    func mixedArrayPinsTheCountAgainstTheRecords() {
        let (raw, asked) = walk(NSArray(array: [element, NSNumber(value: 3)]))

        #expect(raw.childCount == 2)
        #expect(raw.records.count == 1)
        #expect(asked == [0])
        #expect(raw.walkInterrupted == false)
        #expect(ReadClassifier.outcome(raw) == .failed(.partialWalk(childCount: 2, records: 1)))
    }

    @Test("the read it builds carries the process and both calls as they were")
    func carriesTheCallsThrough() {
        let (raw, _) = walk(NSArray(array: [element]))

        #expect(raw.process == process)
        #expect(raw.extrasError == "success")
        #expect(raw.extrasElapsed == 0.011)
        #expect(raw.childrenError == "success")
        #expect(raw.childrenElapsed == 0.012)
        #expect(ReadClassifier.outcome(raw) == .items(raw.records))
    }

    @Test("w2: an interrupt after the first child stops the walk there, and says so")
    func interruptAfterTheFirstChild() {
        let (raw, asked) = walk(NSArray(array: [element, element, element]), interruptAfter: 1)

        #expect(asked == [0])
        #expect(raw.records.count == 1)
        #expect(raw.walkInterrupted)
        #expect(raw.childCount == 3)
    }

    @Test("w3: an interrupt already tripped before the first child reads nothing")
    func interruptBeforeTheFirstChild() {
        let (raw, asked) = walk(NSArray(array: [element, element, element]), interruptAfter: 0)

        #expect(asked.isEmpty)
        #expect(raw.records.isEmpty)
        #expect(raw.walkInterrupted)
        #expect(raw.childCount == 3)
    }

    @Test("w4: a snapshot over the cap is not walked at all, and is interrupted rather than cut short")
    func overTheCapIsNotWalked() {
        let (raw, asked) = walk(NSArray(array: [element, element, element]), cap: 2)

        #expect(asked.isEmpty)
        #expect(raw.records.isEmpty)
        #expect(raw.walkInterrupted)
        #expect(raw.childCount == 3)
        #expect(ReadClassifier.outcome(raw) == .failed(.walkInterrupted))
    }

    @Test("w5: a snapshot exactly at the cap is walked whole")
    func atTheCapIsWalked() {
        let (raw, asked) = walk(NSArray(array: [element, element]), cap: 2)

        #expect(asked == [0, 1])
        #expect(raw.walkInterrupted == false)
        #expect(raw.records.count == 2)
    }

    @Test("w6: a policy stop on a child still interrupts the process's walk")
    func policyStopInterrupts() {
        let (raw, asked) = walk(NSArray(array: [element, element]), stopAt: 0)

        #expect(asked == [0])
        #expect(raw.walkInterrupted)
        #expect(raw.records.count == 1)
    }

    @Test("w7: no value, a non-array or an empty array counts nothing; an array of non-elements still counts what came back", arguments: [
        (SnapshotShape.none, 0), (.nonArray, 0), (.empty, 0), (.onlyNonElements, 2),
    ])
    func whatTheCountIsTakenFrom(shape: SnapshotShape, count: Int) {
        let (raw, asked) = walk(shape.value)

        #expect(raw.childCount == count)
        #expect(raw.records.isEmpty)
        #expect(asked.isEmpty)
        #expect(raw.walkInterrupted == false)
    }

    @Test("the cap is the plan's 64")
    func capValue() {
        #expect(LiveExtrasReader.maxChildren == 64)
    }
}

/// The four values the old snapshot-count tests pinned, now read through
/// `walkChildren`.
enum SnapshotShape: CustomTestStringConvertible, Sendable {
    case none, nonArray, empty, onlyNonElements

    var testDescription: String { "\(self)" }

    var value: CFTypeRef? {
        switch self {
        case .none: return nil
        case .nonArray: return NSString("not an array")
        case .empty: return NSArray()
        case .onlyNonElements: return NSArray(array: [NSString("a"), NSNumber(value: 3)])
        }
    }
}

/// Which children the walk is willing to touch.
///
/// MEASURED 2026-09-25, and the reason this exists: `as? [AXUIElement]` does not
/// check its elements. `AXUIElement` is a Core Foundation type, so the cast
/// succeeds on any `CFArray` whatever it holds -- an array of
/// `[AXUIElement, NSNumber]` casts to "an array of 2", not to `nil`. Walking
/// that would mean issuing Accessibility calls against something that is not an
/// element, on a value another process chose. These tests pin the filter that
/// stops it, and the count mismatch it leaves behind for `ReadClassifier`.
@Suite("LiveExtrasReader: which children the walk will touch")
struct LiveExtrasReaderChildElementsTests {
    /// A real `AXUIElement`, made for this very process -- creating one reads
    /// nothing and touches nobody's menu bar.
    private var element: AXUIElement { AXUIElementCreateApplication(getpid()) }

    /// The count `walkChildren` reports for `value`, walking nothing.
    private static func count(of value: CFTypeRef) -> Int {
        LiveExtrasReader.walkChildren(
            process: testProcess(pid: 42), extrasElapsed: 0, childrenElapsed: 0, childrenValue: value,
            cap: LiveExtrasReader.maxChildren, interrupt: { true }, readChild: { index, _ in
                (extrasRecord(childIndex: index, identifier: "", minX: 0), false)
            }
        ).childCount
    }

    @Test("no value and a non-array both yield no children")
    func noChildren() {
        #expect(LiveExtrasReader.childElements(nil).isEmpty)
        #expect(LiveExtrasReader.childElements(NSString("not an array")).isEmpty)
        #expect(LiveExtrasReader.childElements(NSArray()).isEmpty)
    }

    @Test("an array of real elements comes through whole, and the count agrees")
    func realElementsSurvive() {
        let array = NSArray(array: [element, element])
        #expect(LiveExtrasReader.childElements(array).count == 2)
        #expect(Self.count(of: array) == 2)
    }

    @Test("a non-element is dropped, and the count no longer agrees -- which is the point")
    func nonElementsAreDroppedAndLeaveAMismatch() {
        // This is what `ReadClassifier` then fails as `.partialWalk`: the walk
        // produced fewer records than Accessibility claimed children, so the
        // read is not reported as a process with fewer items.
        let array = NSArray(array: [element, NSNumber(value: 3)])
        #expect(LiveExtrasReader.childElements(array).count == 1)
        #expect(Self.count(of: array) == 2)
        // And the cast this replaces would have handed the walk both of them.
        #expect((array as? [AXUIElement])?.count == 2)
    }

    @Test("an array holding no element at all yields none, against a non-zero count")
    func noElementsAtAllLeavesTheLargestMismatch() {
        let array = NSArray(array: [NSNumber(value: 1), NSString("x")])
        #expect(LiveExtrasReader.childElements(array).isEmpty)
        #expect(Self.count(of: array) == 2)
    }
}
