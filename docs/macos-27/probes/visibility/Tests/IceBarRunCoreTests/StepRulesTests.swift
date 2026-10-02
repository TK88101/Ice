// The runner plan's Q4 (oracle per attempt), Q5 (left of the notch), Q10
// (roster), Q11 (placement), Q12-Q13 (window-server bounds, C3), Q14 (`«`
// episodes), Q15 (S0) and Q16 (section 8).
@testable import IceBarClaim
import IceBarOracle
@testable import IceBarRunCore
import IceCore
import Testing

private let glyphOrder = ["target", "reference", "alt", "hidden2", "hidden3", "hidden4", "ell", "gamma", "zed", "vee",
                          "wedge", "arrow", "cross", "tee", "eff", "ess", "wave", "hook", "bolt"]

@Suite("Q10: roster and vzhelper arguments")
struct RosterTests {
    @Test("visible = reference, alt, target; members = the other 16 in glyph order; the first k used")
    func entries() throws {
        let roster = try Roster.entries(glyphOrder: glyphOrder, members: 4, colouredMembers: false)
        #expect(roster.filter { $0.role == .visible }.map(\.id) == ["reference", "alt", "target"])
        #expect(roster.filter { $0.role == .member }.map(\.id) == ["hidden2", "hidden3", "hidden4", "ell"])
        #expect(try Roster.entries(glyphOrder: glyphOrder, members: 16, colouredMembers: false).filter { $0.role == .member }.count == 16)
        #expect(throws: RosterError.memberCount(17)) { try Roster.entries(glyphOrder: glyphOrder, members: 17, colouredMembers: false) }
        #expect(throws: RosterError.memberCount(0)) { try Roster.entries(glyphOrder: glyphOrder, members: 0, colouredMembers: false) }
        #expect(throws: RosterError.glyphOrder) { try Roster.entries(glyphOrder: Array(glyphOrder.dropLast()), members: 1, colouredMembers: false) }
    }

    @Test("bundle ids: members target, visible protected; identifiers and autosave names per glyph")
    func identities() throws {
        let roster = try Roster.entries(glyphOrder: glyphOrder, members: 1, colouredMembers: false)
        let member = try #require(roster.first { $0.role == .member })
        let visible = try #require(roster.first { $0.role == .visible })
        #expect(member.bundleID == "com.icespike4.target" && member.app == "Target.app")
        #expect(visible.bundleID == "com.icespike4.protected" && visible.app == "Protected.app")
        #expect(member.identifier == "vz-icebar-hidden2")
    }

    @Test("--coloured on members of a coloured variant only")
    func coloured() throws {
        let roster = try Roster.entries(glyphOrder: glyphOrder, members: 2, colouredMembers: true)
        for entry in roster {
            let args = Roster.arguments(entry, lifetimeSeconds: 900)
            #expect(args.contains("--coloured") == (entry.role == .member))
            #expect(args == ["--items", "1", "--identifiers", entry.identifier, "--glyphs", entry.id]
                + (entry.role == .member ? ["--coloured"] : []) + ["--autosave", entry.identifier, "--lifetime", "900"])
        }
        #expect(!(try Roster.entries(glyphOrder: glyphOrder, members: 2, colouredMembers: false)).contains { $0.coloured })
    }

    @Test("the spacer and Menus keep their C1/C2 forms")
    func others() {
        #expect(Roster.spacerArguments(lifetimeSeconds: 900) == ["--role", "spacer", "--autosave", "vz-icebar-spacer", "--lifetime", "900"])
        #expect(Roster.menusArguments(lifetimeSeconds: 900) == ["--role", "menus", "--lifetime", "900"])
    }
}

@Suite("Q11: placement gate")
struct PlacementTests {
    func frame(_ id: String, _ x: Double, y: Double = 0, w: Double = 22) -> ItemFrame { ItemFrame(id: id, minX: x, minY: y, width: w, height: 24) }

    @Test("members left of the spacer, the spacer left of every visible helper, all on the bar")
    func order() {
        let ok = [frame("m1", 1000), frame("m2", 1030), frame("sp", 1060, w: 30), frame("v1", 1100), frame("v2", 1130)]
        let frames = Dictionary(uniqueKeysWithValues: ok.map { ($0.id, $0) })
        #expect(PlacementCheck.evaluate(frames: frames, members: ["m1", "m2"], spacer: "sp", visible: ["v1", "v2"], barHeightPt: 32) == .placed)
        var wrong = frames
        wrong["m2"] = frame("m2", 1070)
        #expect(PlacementCheck.evaluate(frames: wrong, members: ["m1", "m2"], spacer: "sp", visible: ["v1", "v2"], barHeightPt: 32) == .outOfOrder("m2"))
        wrong = frames
        wrong["v1"] = frame("v1", 1080)
        #expect(PlacementCheck.evaluate(frames: wrong, members: ["m1", "m2"], spacer: "sp", visible: ["v1", "v2"], barHeightPt: 32) == .outOfOrder("v1"))
        wrong = frames
        wrong["v2"] = nil
        #expect(PlacementCheck.evaluate(frames: wrong, members: ["m1", "m2"], spacer: "sp", visible: ["v1", "v2"], barHeightPt: 32) == .missing("v2"))
        wrong = frames
        wrong["m1"] = frame("m1", 1000, y: 40)
        #expect(PlacementCheck.evaluate(frames: wrong, members: ["m1", "m2"], spacer: "sp", visible: ["v1", "v2"], barHeightPt: 32) == .offBar("m1"))
    }
}

@Suite("Q12-Q13: window-server bounds and C3")
struct StatusWindowTests {
    let bounds = WindowBounds(x: 1100, y: 0, width: 22, height: 24)

    @Test("exactly one status-level window per helper pid is its bounds; none or two is not listed")
    func selection() {
        let windows = [
            WindowEntry(pid: 10, layer: StatusWindows.statusLayer, bounds: bounds),
            WindowEntry(pid: 10, layer: 0, bounds: WindowBounds(x: 0, y: 0, width: 400, height: 300)),
            WindowEntry(pid: 11, layer: StatusWindows.statusLayer, bounds: bounds),
            WindowEntry(pid: 11, layer: StatusWindows.statusLayer, bounds: bounds),
            WindowEntry(pid: 13, layer: StatusWindows.statusLayer, bounds: WindowBounds(x: -400, y: 0, width: 22, height: 24)),
        ]
        let selected = StatusWindows.bounds(helpers: ["a": 10, "b": 11, "c": 12, "hidden": 13], windows: windows)
        #expect(selected == ["a": bounds, "hidden": WindowBounds(x: -400, y: 0, width: 22, height: 24)])
    }

    @Test("C3 (S0): every helper listed in every capture and visible bounds within 1 pt of AX on x, y, width, height")
    func c3() {
        let ax = ItemFrame(id: "v", minX: 1100, minY: 0, width: 22, height: 24)
        func capture(_ b: [String: WindowBounds]) -> C3Capture { C3Capture(roster: ["v", "m"], visible: ["v"], bounds: b, visibleFrames: ["v": ax]) }
        let hidden = WindowBounds(x: -400, y: 0, width: 22, height: 24)
        #expect(C3Check.evaluate([capture(["v": bounds, "m": hidden])]) == .holds)
        #expect(C3Check.evaluate([capture(["v": bounds])]) == .notListed("m"))
        for shifted in [WindowBounds(x: 1101.5, y: 0, width: 22, height: 24), WindowBounds(x: 1100, y: 1.5, width: 22, height: 24),
                        WindowBounds(x: 1100, y: 0, width: 23.5, height: 24), WindowBounds(x: 1100, y: 0, width: 22, height: 22.5)] {
            #expect(C3Check.evaluate([capture(["v": shifted, "m": hidden])]) == .mismatch("v"))
        }
        #expect(C3Check.evaluate([capture(["v": WindowBounds(x: 1101, y: 1, width: 23, height: 23), "m": hidden])]) == .holds)
        #expect(C3Check.evaluate([C3Capture(roster: ["v"], visible: ["v"], bounds: ["v": bounds], visibleFrames: [:])]) == .mismatch("v"))
        #expect(C3Check.evaluate([]) == .notListed("no capture"))
    }
}

@Suite("Q4-Q5: the oracle per attempt")
struct OracleSummaryTests {
    func labels(_ l: [String: HelperLabel], sightings: [Sighting] = [], chevron: ChevronSighting = .absent) -> CaptureLabels {
        CaptureLabels(labels: l, matches: [:], sightings: sightings, inconclusive: [], chevron: chevron)
    }

    @Test("an attempt ORs its samples' verdicts")
    func combine() {
        let clean = AttemptVerdict.evaluate(captures: [labels([:])], reads: [[]], barHeightPt: 32, members: ["m"], visible: [], overlap: .clear)
        let member = AttemptVerdict.evaluate(captures: [labels(["m": .drawn(.full, xPt: 1000, zone: .region)])], reads: [[]],
                                             barHeightPt: 32, members: ["m"], visible: [], overlap: .clear)
        let missing = AttemptVerdict.evaluate(captures: [labels([:])], reads: [[]], barHeightPt: 32, members: ["m"], visible: [], overlap: .missing("m"))
        let notEvaluable = AttemptVerdict.evaluate(captures: [labels([:], chevron: .notEvaluable)], reads: [[]], barHeightPt: 32, members: ["m"], visible: [], overlap: .clear)
        #expect(OracleSummary.combine([clean, clean]) == OracleAttempt(seesMember: false, seesChevron: false, chevronNotEvaluable: false, inconclusive: false))
        #expect(OracleSummary.combine([clean, member]).seesMember)
        #expect(OracleSummary.combine([missing, clean]).inconclusive)
        #expect(OracleSummary.combine([notEvaluable]).chevronNotEvaluable)
        #expect(OracleSummary.combine([]).inconclusive)
    }

    @Test("an attempt's overlap outcome per sample: the first non-clear of its captures")
    func overlap() {
        #expect(OracleSummary.overlap([.clear, .clear]) == .clear)
        #expect(OracleSummary.overlap([.clear, .overlap("a", "b"), .missing("c")]) == .overlap("a", "b"))
        #expect(OracleSummary.overlap([]) == .missing("no capture"))
    }

    @Test("Q5: a member left of the notch -- full in that zone, or an unexplained sighting ending left of the notch")
    func leftOfNotch() {
        let notch = PtSpan(lo: 771.5, hi: 956.5)
        let full = labels(["m": .drawn(.full, xPt: 600, zone: .leftOfNotch)])
        #expect(OracleSummary.memberLeftOfNotch([full], members: ["m"], notch: notch, scale: 2))
        let visibleThere = labels(["v": .drawn(.full, xPt: 600, zone: .leftOfNotch)])
        #expect(!OracleSummary.memberLeftOfNotch([visibleThere], members: ["m"], notch: notch, scale: 2))
        let sighting = Sighting(templateID: "x", xPx: 1500, yPx: 0, width: 24, matchClass: .edge, explained: false)
        #expect(OracleSummary.memberLeftOfNotch([labels([:], sightings: [sighting])], members: ["m"], notch: notch, scale: 2))
        let straddling = Sighting(templateID: "x", xPx: 1530, yPx: 0, width: 24, matchClass: .edge, explained: false)
        #expect(!OracleSummary.memberLeftOfNotch([labels([:], sightings: [straddling])], members: ["m"], notch: notch, scale: 2))
        let explained = Sighting(templateID: "x", xPx: 1500, yPx: 0, width: 24, matchClass: .edge, explained: true)
        #expect(!OracleSummary.memberLeftOfNotch([labels([:], sightings: [explained])], members: ["m"], notch: notch, scale: 2))
        #expect(!OracleSummary.memberLeftOfNotch([labels([:], sightings: [sighting])], members: ["m"], notch: nil, scale: 2))
    }
}

@Suite("Q14: `«` episodes for BControl")
struct ChevronEpisodeTests {
    @Test("one observation per capture; an episode is a maximal run of reads with (a); numbering continues")
    func episodes() {
        var episodes = ChevronEpisodes()
        let a = episodes.observe(readShowsChevron: false, captures: [.absent, .absent])
        let b = episodes.observe(readShowsChevron: true, captures: [.present, .present])
        let c = episodes.observe(readShowsChevron: true, captures: [.present, .absent])
        let d = episodes.observe(readShowsChevron: false, captures: [.absent, .absent])
        let e = episodes.observe(readShowsChevron: true, captures: [.present, .present])
        #expect(a.map(\.axChevron) == [false, false])
        #expect(b.map(\.episode) == [1, 1] && c.map(\.episode) == [1, 1] && e.map(\.episode) == [2, 2])
        #expect(d.allSatisfy { !$0.axChevron })
        #expect(c.map(\.pixels) == [.present, .absent])
        #expect(episodes.all.count == 10)
        #expect(BControl.evaluate(episodes.all) == .mismatch(index: 5))
    }
}

@Suite("Q16: section 8's report from S0")
struct Section8Tests {
    let p = ClaimParameters.preRegistered

    func m(agree: Int = 0, cluster: Int = 0, texture: Int = 3, cR: Int = 150) -> BaselineMeasurements {
        BaselineMeasurements(maxAgreementDistance: agree, largestRowCluster: cluster, maxRowDeviation: 5,
                             texture: texture * 2 <= 24 ? .accepted(maxDeviation: texture) : .refused(maxDeviation: texture),
                             contrast: ContrastMeasurement(cR: cR, mR: PixelColour(r: 40, g: 40, b: 40), mX: PixelColour(r: 40, g: 40, b: 40), mxToMr: 0, maxRowMedianToMx: 0))
    }

    @Test("consistent when some baseline meets every inequality, even if others fail one")
    func consistent() {
        #expect(Section8Check.evaluate([m(), m(agree: 9)], parameters: p) == .consistent)
    }

    @Test("a contradiction: every baseline with the number fails it (the registered examples)")
    func contradiction() {
        #expect(Section8Check.evaluate([m(cR: 128), m(cR: 100)], parameters: p) == .contradiction(["C_r"]))
        #expect(Section8Check.evaluate([m(agree: 9), m(agree: 12)], parameters: p) == .contradiction(["kept distance"]))
        #expect(Section8Check.evaluate([m(cluster: 16)], parameters: p) == .contradiction(["row spread"]))
        #expect(Section8Check.evaluate([m(texture: 13)], parameters: p) == .contradiction(["texture"]))
    }

    @Test("no baseline reached the pixel clauses, or a number is never measured: unmeasured (the sitting stops)")
    func unmeasured() {
        #expect(Section8Check.evaluate([], parameters: p) == .unmeasured(["kept distance", "row spread", "texture", "C_r"]))
        #expect(Section8Check.evaluate([BaselineMeasurements()], parameters: p) == .unmeasured(["kept distance", "row spread", "texture", "C_r"]))
        let noContrast = BaselineMeasurements(maxAgreementDistance: 0, largestRowCluster: 0, maxRowDeviation: 0, texture: .accepted(maxDeviation: 2))
        #expect(Section8Check.evaluate([noContrast], parameters: p) == .unmeasured(["C_r"]))
    }
}

@Suite("Q15: S0")
struct S0JudgeTests {
    @Test("a cycle: any granted claim is NO-GO; a control miss is inconclusive; otherwise it passes")
    func cycles() {
        #expect(S0Judge.cycle(claimGranted: false, controlsPassed: true) == .pass)
        #expect(S0Judge.cycle(claimGranted: true, controlsPassed: true) == .noGo)
        #expect(S0Judge.cycle(claimGranted: true, controlsPassed: false) == .noGo)
        #expect(S0Judge.cycle(claimGranted: false, controlsPassed: false) == .inconclusive)
    }

    @Test("5/5 passing cycles and a final control after Menus quits; inconclusive cycles re-run at most twice each")
    func stage() {
        let five = Array(repeating: S0CycleResult.pass, count: 5)
        #expect(S0Judge.stage(five, finalControlPassed: true) == .pass)
        #expect(S0Judge.stage(five, finalControlPassed: false) == .notShown("bar not restored after Menus quit"))
        #expect(S0Judge.stage(five + [.noGo], finalControlPassed: true) == .noGo)
        #expect(S0Judge.stage([.inconclusive, .inconclusive, .pass] + Array(repeating: .pass, count: 4), finalControlPassed: true) == .pass)
        #expect(S0Judge.stage([.inconclusive, .inconclusive, .inconclusive], finalControlPassed: true) == .notShown("a cycle inconclusive three times"))
        #expect(S0Judge.stage(Array(repeating: .pass, count: 4), finalControlPassed: true) == .incomplete)
        #expect(S0Judge.nextCycleNeeded(Array(repeating: .pass, count: 4)))
        #expect(!S0Judge.nextCycleNeeded(five))
        #expect(!S0Judge.nextCycleNeeded([.noGo]))
        #expect(!S0Judge.nextCycleNeeded([.inconclusive, .inconclusive, .inconclusive]))
    }
}
