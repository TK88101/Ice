import Testing
@testable import IceCore

/// When Ice's lab report mode is on, and what its commands may do (plan
/// 2026-10-07-icebar-preference-hiding, S4 design D1). The mode writes what
/// Ice holds to standard output and takes commands, and one of its arguments
/// is a deliberate fault, so it must be off for every ordinary launch and
/// refuse an identity that is not a disposable lab one.
@Suite("LabReportRule")
struct LabReportRuleTests {
    func launch(report: String?, holdLength: String? = nil, bundleID: String? = "com.icespike4.lab.r1.1sparse") -> LabReportLaunch {
        LabReportRule.launch(report: report, holdLength: holdLength, bundleID: bundleID)
    }

    @Test("without the launch argument Ice launches normally, under any identity, whatever the fault argument says")
    func offByDefault() {
        #expect(launch(report: nil) == .normal)
        #expect(launch(report: nil, bundleID: "com.jordanbaird.Ice") == .normal)
        #expect(launch(report: nil, bundleID: nil) == .normal)
        #expect(launch(report: nil, holdLength: "YES") == .normal)
        #expect(launch(report: "NO", holdLength: "YES") == .normal)
        #expect(launch(report: "NO", bundleID: "com.jordanbaird.Ice") == .normal)
    }

    @Test("-IceLabReport YES under a lab identity reports; lengths are applied unless the fault is asked for")
    func reports() {
        #expect(launch(report: "YES") == .report(LabReportPlan(holdLength: false)))
        #expect(launch(report: "YES", holdLength: "NO") == .report(LabReportPlan(holdLength: false)))
        #expect(launch(report: "YES", holdLength: "YES") == .report(LabReportPlan(holdLength: true)))
    }

    @Test("an owner identity, passed only by a Debug build, reports under exactly that id and no other")
    func ownerIdentity() {
        let daily = "io.github.tk88101.Ice"
        #expect(LabReportRule.launch(report: "YES", holdLength: nil, bundleID: daily, ownerIdentity: daily) == .report(LabReportPlan(holdLength: false)))
        // Release passes no owner identity: the daily id is refused as before.
        #expect(LabReportRule.launch(report: "YES", holdLength: nil, bundleID: daily, ownerIdentity: nil) == .refused(.notLabIdentity(daily)))
        for other in ["io.github.tk88101.Ice2", "io.github.tk88101.ice", "com.jordanbaird.Ice", ""] {
            #expect(LabReportRule.launch(report: "YES", holdLength: nil, bundleID: other, ownerIdentity: daily) == .refused(.notLabIdentity(other)))
        }
        #expect(LabReportRule.launch(report: "YES", holdLength: nil, bundleID: nil, ownerIdentity: daily) == .refused(.notLabIdentity(nil)))
        // An empty owner identity grants nothing.
        #expect(LabReportRule.launch(report: "YES", holdLength: nil, bundleID: "", ownerIdentity: "") == .refused(.notLabIdentity("")))
        #expect(LabReportRule.launch(report: nil, holdLength: nil, bundleID: daily, ownerIdentity: daily) == .normal)
    }

    @Test("the release identity, a fork's, the helpers', the trace's, a look-alike and no identity are refused")
    func refusesOtherIdentities() {
        let others = [
            "com.jordanbaird.Ice", "com.example.Ice", "com.icespike4.target", "com.icespike4.protected", "com.icespike4.ice",
            "com.icespike4.trace.r1", "com.icespike4.lab", "com.icespike4.lab.", "com.icespike4.labx.r1", "xcom.icespike4.lab.r1", "",
        ]
        for bundleID in others {
            #expect(launch(report: "YES", bundleID: bundleID) == .refused(.notLabIdentity(bundleID)))
            #expect(launch(report: "YES", holdLength: "YES", bundleID: bundleID) == .refused(.notLabIdentity(bundleID)))
        }
        #expect(launch(report: "YES", bundleID: nil) == .refused(.notLabIdentity(nil)))
    }

    @Test("a value that is neither YES nor NO is refused, not guessed at, under any identity")
    func refusesBadValues() {
        for value in ["yes", "1", "true", "", " YES"] {
            #expect(launch(report: value) == .refused(.badArgument(name: LabReportRule.reportArgument, value: value)))
            #expect(launch(report: value, bundleID: "com.jordanbaird.Ice") == .refused(.badArgument(name: LabReportRule.reportArgument, value: value)))
            #expect(launch(report: "YES", holdLength: value) == .refused(.badArgument(name: LabReportRule.holdLengthArgument, value: value)))
        }
    }

    @Test("a held length is reported and never applied; without the fault every length is applied as decided")
    func heldLength() {
        let hold = LabReportPlan(holdLength: true)
        let apply = LabReportPlan(holdLength: false)
        #expect(LabReportRule.appliedLength(736, plan: apply) == LabReportLength(applied: 736, held: false))
        #expect(LabReportRule.appliedLength(nil, plan: apply) == LabReportLength(applied: nil, held: false))
        #expect(LabReportRule.appliedLength(736, plan: hold) == LabReportLength(applied: nil, held: true))
        // Retiring a length that was never applied is not a held length.
        #expect(LabReportRule.appliedLength(nil, plan: hold) == LabReportLength(applied: nil, held: false))
        #expect(LabReportRule.appliedLength(736, plan: nil) == LabReportLength(applied: 736, held: false))
    }

    @Test("the three commands, exactly; anything else is no command")
    func parsesCommands() {
        #expect(LabReportCommand.parse("bar open") == .barOpen)
        #expect(LabReportCommand.parse("bar close") == .barClose)
        #expect(LabReportCommand.parse("press com.icespike4.target vz-lab-1") == .press(namespace: "com.icespike4.target", identifier: "vz-lab-1"))
        #expect(LabReportCommand.parse("  bar open  ") == .barOpen)
        for line in ["", "bar", "bar toggle", "bar open now", "press", "press a", "press a b c", "quit", "BAR OPEN"] {
            #expect(LabReportCommand.parse(line) == nil)
        }
    }

    @Test("a length command sets a held length, standard length, or releases it; anything else is no command")
    func parsesLengthCommands() {
        #expect(LabReportCommand.parse("length 736") == .length(.points(736)))
        #expect(LabReportCommand.parse("length 12.5") == .length(.points(12.5)))
        #expect(LabReportCommand.parse("length 4000") == .length(.points(4000)))
        #expect(LabReportCommand.parse("length standard") == .length(.standard))
        #expect(LabReportCommand.parse("length release") == .lengthRelease)
        for line in ["length", "length 0", "length -5", "length 4000.5", "length nan", "length inf", "length 1e9", "length abc", "length 736 now", "LENGTH 736"] {
            #expect(LabReportCommand.parse(line) == nil)
        }
    }

    @Test("an override replaces what the machine decided until it is released")
    func overrideWins() {
        #expect(LabReportRule.appliedLength(736, plan: nil, override: .points(900)) == LabReportLength(applied: 900, held: true))
        #expect(LabReportRule.appliedLength(nil, plan: nil, override: .points(900)) == LabReportLength(applied: 900, held: true))
        #expect(LabReportRule.appliedLength(736, plan: nil, override: .standard) == LabReportLength(applied: nil, held: true))
        #expect(LabReportRule.appliedLength(736, plan: nil, override: nil) == LabReportLength(applied: 736, held: false))
    }

    let cells = [
        LabReportCell(namespace: "com.icespike4.target", identifier: "a", disabled: false),
        LabReportCell(namespace: "com.icespike4.target", identifier: "b", disabled: true),
        LabReportCell(namespace: "com.icespike4.target", identifier: "twin", disabled: false),
        LabReportCell(namespace: "com.icespike4.target", identifier: "twin", disabled: false),
    ]

    @Test("a press goes to exactly one enabled cell of an offered IceBar, as a click would")
    func pressTarget() {
        func target(_ identifier: String, namespace: String = "com.icespike4.target", offered: Bool = true) -> LabReportPressTarget {
            LabReportRule.pressTarget(namespace: namespace, identifier: identifier, cells: cells, isIceBarOffered: offered)
        }
        #expect(target("a") == .cell(0))
        #expect(target("a", offered: false) == .refused(.notOffered))
        #expect(target("b") == .refused(.disabled))
        #expect(target("twin") == .refused(.ambiguous))
        #expect(target("missing") == .refused(.noCell))
        #expect(target("a", namespace: "com.example") == .refused(.noCell))
        // Not offered speaks first: without an IceBar there are no cells to press.
        #expect(target("missing", offered: false) == .refused(.notOffered))
    }
}
