// The runner plan's Q17 (S-adv sweeps), Q19 (S1: bands, midpoint, re-runs,
// replication, capacity search) and Q20 (the sitting's gates and route C
// 7a's Chinese lines).
import C2Core
import IceBarOracle
@testable import IceBarRunCore
import Testing

@Suite("route C section 3: repeats")
struct RepeatsTests {
    @Test("needed passes; an inconclusive repeat re-run at most twice, a third not shown; NO-GO first")
    func judge() {
        #expect(Repeats.judge([.pass, .pass], needed: 2) == .pass)
        #expect(Repeats.judge([.pass], needed: 2) == .incomplete)
        #expect(Repeats.judge([.inconclusive, .inconclusive, .pass, .pass], needed: 2) == .pass)
        #expect(Repeats.judge([.pass, .inconclusive, .inconclusive, .inconclusive], needed: 2) == .notShown("inconclusive three times"))
        #expect(Repeats.judge([.inconclusive, .noGo], needed: 2) == .noGo)
    }
}

@Suite("Q17: an S-adv sweep")
struct SAdvSweepTests {
    @Test("up from 16 pt by 16 until the members are gone, down to 16 pt, done")
    func upAndDown() {
        var sweep = SAdvSweep()
        var lengths = [Double]()
        while let length = sweep.nextLength() {
            lengths.append(length)
            _ = sweep.record(length >= 64 && sweep.phase == .up ? .membersGone : .membersSeen)
        }
        #expect(lengths == [16, 32, 48, 64, 48, 32, 16])
        #expect(sweep.status == .done)
    }

    @Test("an inconclusive step never ends the upward sweep")
    func inconclusiveStep() {
        var sweep = SAdvSweep()
        #expect(sweep.record(.inconclusive) == .continuing)
        #expect(sweep.nextLength() == 32)
    }

    @Test("gone at the first step: nothing to step down to")
    func goneAtOnce() {
        var sweep = SAdvSweep()
        #expect(sweep.record(.membersGone) == .done)
        #expect(sweep.nextLength() == nil)
    }

    @Test("a NO-GO ends the sweep at once")
    func noGo() {
        var sweep = SAdvSweep()
        _ = sweep.record(.membersSeen)
        #expect(sweep.record(.noGo) == .noGo)
        #expect(sweep.nextLength() == nil)
    }

    @Test("the members never gone below the 1000 pt cap: the sweep is inconclusive")
    func cap() {
        var sweep = SAdvSweep()
        var steps = 0
        while sweep.nextLength() != nil {
            steps += 1
            _ = sweep.record(.membersSeen)
        }
        #expect(steps == 62)
        #expect(sweep.status == .inconclusive("members still seen at 992 pt, the last step under 1000"))
    }

    @Test("four variants: dark and light, ordinary and coloured members")
    func variants() {
        #expect(SAdvVariant.all.map(\.name) == ["dark-ordinary", "dark-coloured", "light-ordinary", "light-coloured"])
        #expect(SAdvVariant.sweepsPerVariant == 2)
    }
}

/// A bar where each profile's band and midpoint outcome are scripted.
struct ScriptedBar {
    var band: [S1Profile: ClosedRange<Double>] = [:]
    var confirm: [S1Profile: [LengthVerdict]] = [:]
    var confirmCalls: [S1Profile: Int] = [:]

    func reading(_ profile: S1Profile, _ length: Double) -> C2Reading {
        band[profile].map { $0.contains(length) } == true ? .hiddenNoFold : .stillDrawn
    }

    mutating func cycles(_ profile: S1Profile) -> [CycleRecord] {
        let script = confirm[profile] ?? [.pass]
        let call = confirmCalls[profile, default: 0]
        confirmCalls[profile] = call + 1
        let verdict = script[min(call, script.count - 1)]
        let good = ObservationRecord(outcome: .granted, cause: nil, oracleClean: true, attempts: 1)
        let bad = ObservationRecord(outcome: .notGranted, cause: .notClear, oracleClean: true, attempts: 3)
        let unsure = ObservationRecord(outcome: .inconclusive, cause: .inconclusive, oracleClean: true, attempts: 3)
        let noGo = ObservationRecord(outcome: .noGo, cause: .noGo, oracleClean: false, attempts: 1)
        let filler: ObservationRecord
        let count: Int
        switch verdict {
        case .pass: (filler, count) = (good, 0)
        case .fail: (filler, count) = (bad, 6)
        case .inconclusive: (filler, count) = (unsure, 3)
        case .noGo: (filler, count) = (noGo, 1)
        case .incomplete: return []
        }
        let all = (0..<20).map { $0 < count ? filler : good }
        return stride(from: 0, to: 20, by: 4).map { CycleRecord(observations: Array(all[$0..<$0 + 4]), controlMiss: false) }
    }

    /// Runs the sequencer to its verdict; returns it with every step taken.
    mutating func run(_ sequencer: inout S1Sequencer) -> (S1Verdict, [S1Step]) {
        var steps = [S1Step]()
        while true {
            let step = sequencer.next()
            steps.append(step)
            switch step {
            case .finished(let verdict):
                return (verdict, steps)
            case .run(let profile, .bracket, let lengths):
                let points = lengths.map { C2Point(length: $0, reading: reading(profile, $0)) }
                sequencer.record(.bracket(points: points, completed: true, noGo: false))
            case .run(let profile, .confirm, _):
                let cycles = cycles(profile)
                sequencer.record(.confirm(cycles: cycles, completed: !cycles.isEmpty))
            }
        }
    }
}

@Suite("Q19: S1")
struct S1SequencerTests {
    func profile(_ k: Int, _ menu: C2MenuWidth) -> S1Profile { S1Profile(k: k, menu: menu) }

    func everyProfile(_ ks: [Int], band: ClosedRange<Double>) -> [S1Profile: ClosedRange<Double>] {
        Dictionary(uniqueKeysWithValues: ks.flatMap { k in [C2MenuWidth.short, .mid].map { (profile(k, $0), band) } })
    }

    func ks(_ steps: [S1Step]) -> [Int] {
        var ks = [Int]()
        for step in steps {
            if case .run(let p, .bracket, _) = step, ks.last != p.k { ks.append(p.k) }
        }
        return ks
    }

    @Test("a profile: coarse scan in batches of at most 14, then refinement, then 5 cycles at the band's midpoint")
    func oneProfile() {
        var bar = ScriptedBar(band: everyProfile([1, 2, 3, 4, 8, 12, 16], band: 600...700))
        var sequencer = S1Sequencer()
        let (verdict, steps) = bar.run(&sequencer)
        #expect(verdict == .capacity(16))
        guard case .run(let first, .bracket, let lengths) = steps[0] else { Issue.record("first step"); return }
        #expect(first == profile(1, .short))
        #expect(lengths == Array(C2BracketSequencer.coarse.prefix(14)))
        let confirms = steps.compactMap { step -> Double? in
            if case .run(profile(1, .short), .confirm(replicate: false), let l) = step { return l.first }
            return nil
        }
        #expect(confirms == [650])
        #expect(steps.allSatisfy { step in
            if case .run(_, _, let l) = step { return l.count <= S1Sequencer.maxLengthsPerStep }
            return true
        })
    }

    @Test("capacity search: 1, 2, 4, 8, 12, 16 while each passes; then k = 3 confirmed")
    func doubling() {
        var bar = ScriptedBar(band: everyProfile([1, 2, 3, 4, 8, 12, 16], band: 600...700))
        var sequencer = S1Sequencer()
        #expect(ks(bar.run(&sequencer).1) == [1, 2, 4, 8, 12, 16, 3])
    }

    @Test("after the first failure, every integer between the last pass and it; the capacity is the largest k with every tested smaller k passing")
    func integers() {
        var bar = ScriptedBar(band: everyProfile([1, 2, 3, 4, 8, 9, 10], band: 600...700))
        var sequencer = S1Sequencer()
        let (verdict, steps) = bar.run(&sequencer)
        #expect(ks(steps) == [1, 2, 4, 8, 12, 9, 10, 11, 3])
        #expect(verdict == .capacity(10))
    }

    @Test("an intermediate failure stops the search above it")
    func intermediateFails() {
        var bar = ScriptedBar(band: everyProfile([1, 2, 3, 4, 5], band: 600...700))
        var sequencer = S1Sequencer()
        let (verdict, steps) = bar.run(&sequencer)
        #expect(ks(steps) == [1, 2, 4, 8, 5, 6, 3])
        #expect(verdict == .capacity(5))
    }

    @Test("no band at k = 1 is NO-GO")
    func noBandAtOne() {
        var bar = ScriptedBar()
        var sequencer = S1Sequencer()
        #expect(bar.run(&sequencer).0 == .noGo("no band at k = 1 (short)"))
    }

    @Test("a mid-menu failure fails k even when short passes; capacity below 4 ends the sitting")
    func belowFour() {
        var bar = ScriptedBar(band: everyProfile([1, 2, 3], band: 600...700))
        bar.band[profile(4, .short)] = 600...700
        var sequencer = S1Sequencer()
        let (verdict, steps) = bar.run(&sequencer)
        #expect(ks(steps) == [1, 2, 4, 3])
        #expect(verdict == .capacityBelowFour(3))
    }

    @Test("k = 3 failing after the doubling lowers the capacity")
    func threeFails() {
        var bar = ScriptedBar(band: everyProfile([1, 2, 4, 8, 12, 16], band: 600...700))
        var sequencer = S1Sequencer()
        #expect(bar.run(&sequencer).0 == .capacityBelowFour(2))
    }

    @Test("a rate failure is replicated once in a new step; the replicate decides")
    func replication() {
        var bar = ScriptedBar(band: everyProfile([1, 2, 3, 4, 8, 12, 16], band: 600...700))
        bar.confirm[profile(1, .short)] = [.fail, .pass]
        bar.confirm[profile(2, .short)] = [.fail, .fail]
        var sequencer = S1Sequencer()
        let (verdict, steps) = bar.run(&sequencer)
        #expect(steps.contains(.run(profile(1, .short), purpose: .confirm(replicate: true), lengths: [650])))
        #expect(verdict == .capacityBelowFour(1))
    }

    @Test("an inconclusive repeat is re-run at most twice; a third is not shown (a failure); an incomplete step counts as inconclusive")
    func inconclusiveRepeats() {
        var bar = ScriptedBar(band: everyProfile([1, 2, 3, 4, 8, 12, 16], band: 600...700))
        bar.confirm[profile(1, .short)] = [.inconclusive, .incomplete(0), .pass]
        bar.confirm[profile(2, .short)] = [.inconclusive, .inconclusive, .inconclusive]
        var sequencer = S1Sequencer()
        let (verdict, steps) = bar.run(&sequencer)
        #expect(bar.confirmCalls[profile(1, .short)] == 3)
        #expect(bar.confirmCalls[profile(2, .short)] == 3)
        #expect(!steps.contains(.run(profile(2, .short), purpose: .confirm(replicate: true), lengths: [650])))
        #expect(verdict == .capacityBelowFour(1))
    }

    @Test("a NO-GO anywhere ends S1")
    func noGo() {
        var bar = ScriptedBar(band: everyProfile([1, 2, 3, 4, 8, 12, 16], band: 600...700))
        bar.confirm[profile(2, .mid)] = [.noGo]
        var sequencer = S1Sequencer()
        #expect(bar.run(&sequencer).0 == .noGo("k2-mid at 650 pt"))
        var bracketNoGo = S1Sequencer()
        _ = bracketNoGo.next()
        bracketNoGo.record(.bracket(points: [], completed: true, noGo: true))
        #expect(bracketNoGo.next() == .finished(.noGo("k1-short during the band scan")))
    }

    @Test("a safety stop ends S1")
    func safety() {
        var sequencer = S1Sequencer()
        _ = sequencer.next()
        sequencer.record(.safetyStop("foreign item"))
        #expect(sequencer.next() == .finished(.safetyStop("foreign item")))
    }

    @Test("a short batch is re-run without its measured lengths; three short batches: the profile is not shown")
    func shortBatches() {
        var sequencer = S1Sequencer()
        guard case .run(_, _, let first) = sequencer.next() else { Issue.record("no step"); return }
        sequencer.record(.bracket(points: [C2Point(length: first[0], reading: .stillDrawn)], completed: false, noGo: false))
        guard case .run(_, _, let second) = sequencer.next() else { Issue.record("no step"); return }
        #expect(second.first == first[1])
        sequencer.record(.bracket(points: [], completed: false, noGo: false))
        _ = sequencer.next()
        sequencer.record(.bracket(points: [], completed: false, noGo: false))
        // k = 1 short not shown is a failure; with no capacity, S1 ends below four.
        #expect(sequencer.next() == .finished(.capacityBelowFour(0)))
    }
}

@Suite("Q20: the sitting and route C 7a")
struct SittingTests {
    @Test("S0's gates: NO-GO fails; C3, section 8 or a non-pass stops for the owner")
    func afterS0() {
        #expect(Sitting.afterS0(.pass, c3: .holds, section8: .consistent) == .proceed)
        #expect(Sitting.afterS0(.noGo, c3: .holds, section8: .consistent) == .end(.failed("S0: the claim was granted with a long menu")))
        #expect(Sitting.afterS0(.notShown("x"), c3: .holds, section8: .consistent) == .end(.failed("S0 not shown: x")))
        #expect(Sitting.afterS0(.pass, c3: .notListed("m"), section8: .consistent) == .end(.interrupted("S0: window-server bounds unusable (m not listed); the owner decides")))
        #expect(Sitting.afterS0(.pass, c3: .mismatch("v"), section8: .consistent) == .end(.interrupted("S0: window-server bounds unusable (v off its AX frame); the owner decides")))
        #expect(Sitting.afterS0(.pass, c3: .holds, section8: .unmeasured(["C_r"])) == .end(.interrupted("S0: section 8 cannot be checked (C_r unmeasured); the owner decides")))
        #expect(Sitting.afterS0(.pass, c3: .holds, section8: .contradiction(["C_r"])) == .end(.interrupted("S0: section 8 contradiction (C_r); the owner decides")))
        #expect(Sitting.afterS0(.incomplete, c3: .holds, section8: .consistent) == .end(.failed("S0 not shown: ended before 5 cycles")))
    }

    @Test("S-adv cannot run until the owner decides how the appearance variants are produced (K2)")
    func appearanceGate() {
        #expect(Sitting.beforeSAdv(appearanceDecided: false) == .end(.interrupted("S-adv waits for the owner's decision on the appearance variants (E3, K2)")))
        #expect(Sitting.beforeSAdv(appearanceDecided: true) == .proceed)
    }

    @Test("S-adv's gates: NO-GO fails; BControl must be valid before S1")
    func afterSAdv() {
        #expect(Sitting.afterSAdv(.pass, bControl: .valid(captures: 10, episodes: 2)) == .proceed)
        #expect(Sitting.afterSAdv(.noGo, bControl: .valid(captures: 10, episodes: 2)) == .end(.failed("S-adv: the claim was granted while the oracle saw a member or «")))
        #expect(Sitting.afterSAdv(.notShown("y"), bControl: .valid(captures: 10, episodes: 2)) == .end(.failed("S-adv not shown: y")))
        #expect(Sitting.afterSAdv(.incomplete, bControl: .valid(captures: 10, episodes: 2)) == .end(.failed("S-adv not shown: ended before every sweep")))
        #expect(Sitting.afterSAdv(.pass, bControl: .mismatch(index: 3)) == .end(.interrupted("« (b) control: mismatch at capture 3; the owner decides")))
        #expect(Sitting.afterSAdv(.pass, bControl: .insufficientEpisodes(1)) == .end(.interrupted("« (b) control: 1 episodes, 2 needed; the owner decides")))
        #expect(Sitting.afterSAdv(.pass, bControl: .insufficientCaptures(9)) == .end(.interrupted("« (b) control: 9 captures, 10 needed; the owner decides")))
    }

    @Test("S1's verdict")
    func afterS1() {
        #expect(Sitting.afterS1(.capacity(8)) == .completed("S1 capacity 8"))
        #expect(Sitting.afterS1(.capacityBelowFour(2)) == .interrupted("S1 capacity 2, below 4; the owner decides before S2"))
        #expect(Sitting.afterS1(.noGo("k2-mid at 650 pt")) == .failed("S1 NO-GO: k2-mid at 650 pt"))
        #expect(Sitting.afterS1(.safetyStop("x")) == .safetyStop("x"))
    }

    @Test("7a: one line per step start and end; the final line is result｜reason｜directory")
    func lines() {
        #expect(ProgressLine.start(step: 3, name: "S1 k2-short", clock: "01:02:03", elapsed: 3_725) == "步驟 3 S1 k2-short 開始 [01:02:03，已過 1:02]")
        #expect(ProgressLine.end(step: 3, name: "S1 k2-short", status: "completed", clock: "01:30:00", elapsed: 5_400) == "步驟 3 S1 k2-short 結束：completed [01:30:00，已過 1:30]")
        #expect(ProgressLine.final(.completed("S1 capacity 8"), directory: "/d") == "結果：完成｜S1 capacity 8｜/d")
        #expect(ProgressLine.final(.failed("x"), directory: "/d") == "結果：失敗｜x｜/d")
        #expect(ProgressLine.final(.interrupted("x"), directory: "/d") == "結果：中斷｜x｜/d")
        #expect(ProgressLine.final(.safetyStop("x"), directory: "/d") == "結果：安全停止｜x｜/d")
    }
}

@Suite("Q19: a NO-GO reported outside the cycles")
struct S1NoGoResultTests {
    @Test("a step's own NO-GO ends S1 whatever its purpose")
    func noGo() {
        var sequencer = S1Sequencer()
        _ = sequencer.next()
        sequencer.record(.noGo("member left of the notch at 520 pt"))
        #expect(sequencer.next() == .finished(.noGo("k1-short: member left of the notch at 520 pt")))
    }
}
