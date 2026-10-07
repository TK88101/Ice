import Testing
@testable import IceCore

/// What Ice's trace mode starts, and when (plan
/// 2026-10-07-icebar-preference-hiding, S1). The mode adds status items and
/// writes defaults, so it must be off for every ordinary launch and refuse an
/// identity that is not a disposable lab one.
@Suite("LabTraceRule")
struct LabTraceRuleTests {
    func launch(trace: String?, alwaysHidden: String? = nil, bundleID: String? = "com.icespike4.trace.r1") -> LabTraceLaunch {
        LabTraceRule.launch(trace: trace, alwaysHidden: alwaysHidden, bundleID: bundleID)
    }

    @Test("without the launch argument Ice launches normally, under any identity")
    func offByDefault() {
        #expect(launch(trace: nil) == .normal)
        #expect(launch(trace: nil, bundleID: "com.jordanbaird.Ice") == .normal)
        #expect(launch(trace: nil, bundleID: nil) == .normal)
        #expect(launch(trace: nil, alwaysHidden: "YES") == .normal)
    }

    @Test("-IceLabTrace NO is a normal launch")
    func explicitNo() {
        #expect(launch(trace: "NO") == .normal)
        #expect(launch(trace: "NO", bundleID: "com.jordanbaird.Ice") == .normal)
    }

    @Test("-IceLabTrace YES under a lab identity traces, the always-hidden section off unless asked")
    func traces() {
        #expect(launch(trace: "YES") == .trace(LabTracePlan(alwaysHiddenSection: false)))
        #expect(launch(trace: "YES", alwaysHidden: "NO") == .trace(LabTracePlan(alwaysHiddenSection: false)))
        #expect(launch(trace: "YES", alwaysHidden: "YES") == .trace(LabTracePlan(alwaysHiddenSection: true)))
    }

    @Test("the release identity, a fork's, the sacrificial helpers, a look-alike and no identity are refused: the trace writes defaults")
    func refusesOtherIdentities() {
        let others = [
            "com.jordanbaird.Ice", "com.example.Ice", "com.icespike4.target", "com.icespike4.protected", "com.icespike4.ice",
            "com.icespike4.trace", "com.icespike4.trace.", "com.icespike4.tracex.r1", "xcom.icespike4.trace.r1", "",
        ]
        for bundleID in others {
            #expect(launch(trace: "YES", bundleID: bundleID) == .refused(.notLabIdentity(bundleID)))
        }
        #expect(launch(trace: "YES", bundleID: nil) == .refused(.notLabIdentity(nil)))
    }

    @Test("a value that is neither YES nor NO is refused, not guessed at")
    func refusesBadValues() {
        for value in ["yes", "1", "true", "", " YES"] {
            #expect(launch(trace: value) == .refused(.badArgument(name: LabTraceRule.traceArgument, value: value)))
            #expect(launch(trace: "YES", alwaysHidden: value) == .refused(.badArgument(name: LabTraceRule.alwaysHiddenArgument, value: value)))
        }
    }

    @Test("a bad trace value is refused under any identity: the launch was meant as a trace")
    func badValueBeforeIdentity() {
        #expect(launch(trace: "maybe", bundleID: "com.jordanbaird.Ice") == .refused(.badArgument(name: LabTraceRule.traceArgument, value: "maybe")))
    }

    @Test("the trace starts three things only, in S1's order; LabTrace.start runs exactly this list")
    func steps() {
        #expect(LabTracePlan.steps == [.stopPermissionChecks, .setSettingsInMemory, .setUpSections])
    }

    @Test("five points are sampled, in the order the lifecycle reaches them")
    func points() {
        #expect(LabTracePoint.allCases == [.beforeSeed, .afterSeed, .afterStatusItem, .afterAutosaveName, .afterMainQueueTurn])
    }
}
