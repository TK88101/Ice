import Testing
@testable import IceCore

/// The lines Ice's lab report mode writes (plan
/// 2026-10-07-icebar-preference-hiding, S4 design D1). `lab-tool.py` reads
/// them: the keys and the names below are its contract, and `test-lab.sh`
/// compares its list of keys with `LabReportSnapshot.keys`.
@Suite("LabReport")
struct LabReportTests {
    let memberKey = ItemKey(namespace: "com.icespike4.target", identifier: "vz-lab-1", pid: 41, childIndex: nil)

    func snapshot() -> LabReportSnapshot {
        LabReportSnapshot(
            phase: "resting",
            status: "verified",
            lengthSet: true,
            lengthApplied: true,
            calibratedHiddenLength: 736,
            isIceBarOffered: true,
            isIceBarPresented: false,
            isInteracting: false,
            roster: [LabReportMember(
                namespace: "com.icespike4.target", identifier: "vz-lab-1", pid: 41, condition: "stacked", pressable: true,
                frame: BarRect(minX: 900, minY: 4, width: 14, height: 22), overlaps: [BarRect(minX: 896, minY: 4, width: 20, height: 22)]
            )],
            blockers: [],
            cells: [LabReportCell(namespace: "com.icespike4.target", identifier: "vz-lab-1", disabled: false)],
            cacheVisible: [LabReportItem(namespace: "com.icespike4.protected", identifier: "vz-lab-ref1")],
            cacheHidden: [LabReportItem(namespace: "com.icespike4.target", identifier: "vz-lab-1")],
            cacheAlwaysHidden: [],
            iconPlacement: nil,
            hiddenBoundaryUsable: true,
            icon: LabReportControlItem(frame: BarRect(minX: 1500, minY: 0, width: 28, height: 30), usable: true),
            hiddenDivider: LabReportControlItem(frame: BarRect(minX: 880, minY: 0, width: 18, height: 30), usable: true),
            alwaysHiddenDivider: nil,
            completeness: "complete",
            pass: 12,
            checks: [LabReportCheck(namespace: "com.icespike4.target", identifier: "vz-lab-1", outcome: "hidden")],
            chevronListed: false,
            systemElements: [BarRect(minX: 896, minY: 4, width: 20, height: 22)]
        )
    }

    @Test("a snapshot's line carries exactly the pinned keys")
    func snapshotKeys() {
        let object = LabReportEvent.snapshot(snapshot()).fields
        #expect(Set(object.keys) == Set(LabReportSnapshot.keys))
        #expect(LabReportSnapshot.keys == [
            "phase", "status", "lengthSet", "lengthApplied", "calibratedHiddenLength", "isIceBarOffered",
            "isIceBarPresented", "isInteracting", "roster", "blockers", "cells", "cacheVisible", "cacheHidden",
            "cacheAlwaysHidden", "iconPlacement", "hiddenBoundaryUsable", "icon", "hiddenDivider",
            "alwaysHiddenDivider", "completeness", "pass", "checks", "chevronListed", "systemElements",
        ])
    }

    @Test("a member names the frames it overlaps, and the snapshot MenuBarAgent's elements (plan 2026-10-19-verify-in-a-clean-burst, D6)")
    func obstacles() {
        let fields = LabReportEvent.snapshot(snapshot()).fields
        #expect(fields["systemElements"]?.text == "[[896,4,20,22]]")
        #expect(fields["roster"]?.text.contains(#""overlaps":[[896,4,20,22]]"#) == true)
    }

    @Test("a set's obstacles for an item are the catalog's: MenuBarAgent's elements and the other items on the bar, never a parked one")
    func obstaclesAreTheCatalogs() {
        let member = fixtureItem(identifier: "m", pid: 1, frame: barFrame(minX: 100, width: 20))
        let neighbour = fixtureItem(identifier: "n", pid: 2, frame: barFrame(minX: 130, width: 20))
        let parked = fixtureItem(identifier: "p", pid: 3, frame: barFrame(minX: 100, width: 20), position: .parked)
        let frameless = fixtureItem(identifier: "f", pid: 4, frame: nil, position: .noFrame)
        let indicator = barFrame(minX: 104, width: 40)
        let set = DiscoveredItemSet(
            items: [member, neighbour, parked, frameless], visibleControlItem: nil, hiddenDivider: nil, alwaysHiddenDivider: nil,
            ownRead: .ok, systemElements: [indicator], dropped: [], completeness: .complete
        )
        #expect(set.obstacles(excluding: member.key) == [indicator, neighbour.frame!])
    }

    @Test("the frames an item overlaps by the stacked rule's measure, and only those")
    func overlapsByTheStackedRule() {
        let item = BarRect(minX: 100, minY: 0, width: 20, height: 24)
        let neighbour = BarRect(minX: 118, minY: 0, width: 20, height: 24)
        let indicator = BarRect(minX: 104, minY: 0, width: 40, height: 24)
        #expect(PositionRule.overlaps(of: item, obstacles: [neighbour, indicator]) == [indicator])
    }

    @Test("lines are numbered from 1, in order, each with its event's name and time, keys sorted")
    func writerNumbersLines() {
        var writer = LabReportWriter()
        let first = writer.line(.start(pid: 7, bundleID: "com.icespike4.lab.r1", holdLength: false), at: 0)
        let second = writer.line(.status("verified"), at: 1.5)
        #expect(first == #"{"bundleID":"com.icespike4.lab.r1","event":"start","holdLength":false,"marker":"IceLabReport-start-v1","pid":7,"seq":1,"t":0}"#)
        #expect(second == #"{"event":"status","seq":2,"status":"verified","t":1.5}"#)
    }

    @Test("each event's line")
    func eventLines() {
        func line(_ event: LabReportEvent) -> String {
            var writer = LabReportWriter()
            return writer.line(event, at: 2)
        }
        #expect(line(.length(LabReportLength(applied: 736, held: false), decided: 736)) == #"{"applied":736,"decided":736,"event":"length","held":false,"seq":1,"t":2}"#)
        #expect(line(.length(LabReportLength(applied: nil, held: true), decided: 736)) == #"{"applied":null,"decided":736,"event":"length","held":true,"seq":1,"t":2}"#)
        #expect(line(.length(LabReportLength(applied: nil, held: false), decided: nil)) == #"{"applied":null,"decided":null,"event":"length","held":false,"seq":1,"t":2}"#)
        let reference = ItemKey(namespace: "com.icespike4.protected", identifier: "ref1", pid: 11, childIndex: nil)
        let diagnostics = ObservationDiagnostics(
            references: [ReferenceReading(key: reference, match: "unique", mismatch: 0.01, offset: -48)],
            captureStable: false,
            fold: "absent"
        )
        let burst = ObservationBurst(burstID: 4, ordinal: 2, burstStartedAt: 100, capturedAt: 101.5)
        #expect(line(.observation(length: 736, diagnostics: diagnostics, waited: 21.5, burst: burst, sinceCapture: 0.25)) == #"{"burstAge":1.5,"burstID":4,"captureStable":false,"event":"observation","fold":"absent","length":736,"ordinal":2,"references":[{"identifier":"ref1","match":"unique","mismatch":0.01,"namespace":"com.icespike4.protected","offset":-48}],"seq":1,"sinceCapture":0.25,"t":2,"waited":21.5}"#)
        #expect(line(.observation(length: 736, diagnostics: nil, waited: 0, burst: nil, sinceCapture: nil)) == #"{"burstAge":null,"burstID":null,"captureStable":null,"event":"observation","fold":null,"length":736,"ordinal":null,"references":[],"seq":1,"sinceCapture":null,"t":2,"waited":0}"#)
        #expect(line(.roster([LabReportItem(namespace: "n", identifier: "a")])) == #"{"event":"roster","members":[{"identifier":"a","namespace":"n"}],"seq":1,"t":2}"#)
        #expect(line(.press(namespace: "n", identifier: "a", answer: "sent")) == #"{"answer":"sent","event":"press","identifier":"a","namespace":"n","seq":1,"t":2}"#)
        #expect(line(.bar(action: "open", answer: "refused:notOffered")) == #"{"action":"open","answer":"refused:notOffered","event":"bar","seq":1,"t":2}"#)
        #expect(line(.unknownCommand) == #"{"event":"unknownCommand","seq":1,"t":2}"#)
    }

    @Test("a snapshot's members, cells, frames and absent values")
    func snapshotLine() {
        var writer = LabReportWriter()
        let line = writer.line(.snapshot(snapshot()), at: 3.25)
        #expect(line.hasPrefix(#"{"alwaysHiddenDivider":null,"blockers":[],"cacheAlwaysHidden":[],"#))
        #expect(line.contains(#""roster":[{"condition":"stacked","frame":[900,4,14,22],"identifier":"vz-lab-1","namespace":"com.icespike4.target","overlaps":[[896,4,20,22]],"pid":41,"pressable":true}]"#))
        #expect(line.contains(#""cells":[{"disabled":false,"identifier":"vz-lab-1","namespace":"com.icespike4.target"}]"#))
        #expect(line.contains(#""hiddenDivider":{"frame":[880,0,18,30],"usable":true}"#))
        #expect(line.contains(#""checks":[{"identifier":"vz-lab-1","namespace":"com.icespike4.target","outcome":"hidden"}]"#))
        #expect(line.contains(#""iconPlacement":null"#))
        #expect(line.contains(#""calibratedHiddenLength":736"#))
        #expect(line.contains(#""event":"snapshot","#))
        #expect(line.hasSuffix(#""seq":1,"status":"verified","systemElements":[[896,4,20,22]],"t":3.25}"#))
    }

    @Test("text another app chose cannot break a line: quotes, backslashes, control characters and newlines are escaped")
    func escapes() {
        #expect(LabJSON.string("a\"b\\c\nd\te\u{01}").text == #""a\"b\\c\nd\te\u0001""#)
        #expect(LabJSON.string("«é").text == "\"«é\"")
    }

    @Test("numbers: whole ones without a fraction, others as they are, anything not finite as null")
    func numbers() {
        #expect(LabJSON.number(736).text == "736")
        #expect(LabJSON.number(-1).text == "-1")
        #expect(LabJSON.number(1508.5).text == "1508.5")
        #expect(LabJSON.number(.infinity).text == "null")
        #expect(LabJSON.number(.nan).text == "null")
        #expect(LabJSON.number(1e300).text == "1e+300")
    }

    @Test("a member's condition, by name")
    func conditionNames() {
        #expect(LabReportNames.condition(.ready) == "ready")
        #expect(LabReportNames.condition(.stacked) == "stacked")
        #expect(LabReportNames.condition(.stale(.missingFromRead)) == "stale:missingFromRead")
        #expect(LabReportNames.condition(.stale(.ambiguousOrUnreadable)) == "stale:ambiguousOrUnreadable")
        #expect(LabReportNames.condition(.stale(.parked)) == "stale:parked")
        #expect(LabReportNames.condition(.stale(.noFrame)) == "stale:noFrame")
    }

    @Test("a check's outcome, by name: absent, absent behind the fold, drawn, and why not checked")
    func checkNames() {
        #expect(VerificationSummary.name(of: .checked(.hidden(folded: false))) == "hidden")
        #expect(VerificationSummary.name(of: .checked(.hidden(folded: true))) == "hiddenFolded")
        #expect(VerificationSummary.name(of: .checked(.stillDrawn)) == "stillDrawn")
        #expect(VerificationSummary.name(of: .checked(.unverifiable(.weakMatch))) == "unverifiable:weakMatch")
        #expect(VerificationSummary.name(of: .refusedAtBaseline(.notUniqueAtBaseline)) == "refused:notUniqueAtBaseline")
        #expect(VerificationSummary.name(of: .skipped(.noReference)) == "skipped:noReference")
    }

    @Test("a member keeps its name while it goes stale: its key, else the key it was last read with, else its tag")
    func memberNames() {
        let tag = TagKey(namespace: "com.icespike4.target", title: "a title")
        #expect(LabReportItem(member: PreferenceHidingMember(tag: tag, key: memberKey, condition: .ready), lastKey: nil) == LabReportItem(memberKey))
        let missing = PreferenceHidingMember(tag: tag, key: nil, condition: .stale(.missingFromRead))
        #expect(LabReportItem(member: missing, lastKey: memberKey) == LabReportItem(memberKey))
        #expect(LabReportItem(member: missing, lastKey: nil) == LabReportItem(namespace: "com.icespike4.target", identifier: "a title"))
    }

    @Test("completeness, by name")
    func completenessNames() {
        #expect(LabReportNames.completeness(.complete) == "complete")
        #expect(LabReportNames.completeness(.incomplete(failedPIDs: [1, 2])) == "incomplete:2")
        #expect(LabReportNames.completeness(.permissionDenied) == "permissionDenied")
        #expect(LabReportNames.completeness(nil) == nil)
    }

    @Test("what the machine tells the report: its phase by name, whether a length is set, and the rest's checks")
    func machineFacts() {
        var machine = IceBarHidingMachine()
        #expect(machine.labFacts == LabReportMachineFacts(phase: "off", status: "off", lengthSet: false, lengthApplied: false, checks: [:], chevronListed: nil))
        let (next, _) = machine.step(.mode(isIceBar: true), now: 0)
        machine = next
        #expect(machine.labFacts.phase == "quiet")
        #expect(machine.labFacts.status == "notVerified(lengthNotApplied)")
        #expect(!machine.labFacts.lengthSet)
    }

    @Test("every phase has a name")
    func phaseNames() {
        let trial = IceBarHidingMachine.Trial(token: 1, length: 736)
        let rest = IceBarHidingMachine.Rest(length: 736, checks: [memberKey: .checked(.hidden(folded: false))], chevronListed: true, pending: nil)
        let phases: [(IceBarHidingMachine.Phase, String)] = [
            (.off, "off"), (.blocked, "blocked"), (.quiet(since: 0), "quiet"), (.baselining(token: 1), "baselining"),
            (.calibrating(observations: [], pending: trial, restedAt: 0), "calibrating"),
            (.settling(trial, .final), "settling"), (.resting(rest), "resting"),
        ]
        for (phase, name) in phases {
            #expect(LabReportNames.phase(phase) == name)
        }
    }
}
