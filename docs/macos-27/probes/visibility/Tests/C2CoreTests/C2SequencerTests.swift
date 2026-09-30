// T4 (docs/plans/2026-09-28-c2-protocol.md sections 3-5): the sequencer's
// next process for both sittings.
import C2Core
import Testing

private func points(_ lengths: [Double], _ reading: (Double) -> C2Reading) -> [C2Point] {
    lengths.map { C2Point(length: $0, reading: reading($0)) }
}

/// A bar whose band is exactly [lo, hi]: folded below, drawn above.
private func bar(_ lo: Double, _ hi: Double) -> (Double) -> C2Reading {
    { $0 < lo ? .hiddenFolded : ($0 > hi ? .stillDrawn : .hiddenNoFold) }
}

@Suite("C2Sequencer")
struct C2SequencerTests {
    @Test("the 12 configurations, long menus first")
    func configurationOrder() {
        #expect(C2Configuration.all.count == 12)
        #expect(C2Configuration.all.prefix(4).allSatisfy { $0.width == .long })
        #expect(C2Configuration.all.first?.id == "k1-long")
        #expect(C2Configuration.all.last?.id == "k4-short")
    }

    @Test("sitting A: coarse in batches of 14, then refinement, then the next configuration; both bracketed -> the length")
    func bracketsTwoConfigurations() {
        let configs = Array(C2Configuration.all.prefix(2))
        var sequencer = C2BracketSequencer(configurations: configs)
        for config in configs {
            var measured = [Double]()
            while case .run(let c, let lengths) = sequencer.next(), c == config {
                #expect(lengths.count <= 14)
                measured += lengths
                sequencer.record(C2ProcessResult(status: .completed, points: points(lengths, bar(610, 842))))
            }
            #expect(Array(measured.prefix(C2BracketSequencer.coarse.count)) == C2BracketSequencer.coarse)
            #expect(Array(measured.dropFirst(C2BracketSequencer.coarse.count)) == [604, 608, 612, 844, 848, 852])
        }
        #expect(sequencer.next() == .finished(.length(726, intersection: C2Span(lo: 612, hi: 840))))
    }

    @Test("sitting A: a short process re-runs only its unmeasured lengths; three short processes -> not shown")
    func bracketRetriesThenNotShown() {
        var sequencer = C2BracketSequencer(configurations: [C2Configuration.all[0]])
        let coarse = C2BracketSequencer.coarse
        #expect(sequencer.next() == .run(C2Configuration.all[0], lengths: Array(coarse.prefix(14))))
        sequencer.record(C2ProcessResult(status: .inconclusive("fold unreadable"), points: points(Array(coarse.prefix(3)), bar(600, 800))))
        #expect(sequencer.next() == .run(C2Configuration.all[0], lengths: Array(coarse.dropFirst(3).prefix(14))))
        sequencer.record(C2ProcessResult(status: .inconclusive("fold unreadable"), points: []))
        sequencer.record(C2ProcessResult(status: .inconclusive("fold unreadable"), points: []))
        #expect(sequencer.next() == .finished(.provisionalFail(configuration: "k1-long", reason: "not shown: fold unreadable")))
    }

    @Test("full batches never count as failures: many complete processes still finish the configuration")
    func fullBatchesAreNotFailures() {
        var sequencer = C2BracketSequencer(configurations: [C2Configuration.all[0]])
        var processes = 0
        while case .run(_, let lengths) = sequencer.next(), processes < 30 {
            sequencer.record(C2ProcessResult(status: .completed, points: points(lengths, bar(610, 842))))
            processes += 1
        }
        #expect(processes == 3) // 14 + 14 coarse, then one refinement batch
        #expect(sequencer.next() == .finished(.length(726, intersection: C2Span(lo: 612, hi: 840))))
    }

    @Test("sitting A: no band after the scan reaches 0 and 1000 -> provisional fail, and the later configurations never run")
    func bracketNoBandStops() {
        var sequencer = C2BracketSequencer(configurations: Array(C2Configuration.all.prefix(2)))
        var guardSteps = 0
        while case .run(_, let lengths) = sequencer.next(), guardSteps < 20 {
            sequencer.record(C2ProcessResult(status: .completed, points: points(lengths) { _ in .stillDrawn }))
            guardSteps += 1
        }
        #expect(sequencer.next() == .finished(.provisionalFail(configuration: "k1-long", reason: "no band")))
    }

    @Test("sitting A: a safety stop ends it at once")
    func bracketSafetyStop() {
        var sequencer = C2BracketSequencer(configurations: Array(C2Configuration.all.prefix(2)))
        sequencer.record(C2ProcessResult(status: .safetyStop, points: []))
        #expect(sequencer.next() == .finished(.safetyStop(configuration: "k1-long")))
        sequencer.record(C2ProcessResult(status: .completed, points: []))
        #expect(sequencer.next() == .finished(.safetyStop(configuration: "k1-long")))
    }

    @Test("sitting A: a completed process that still left lengths unmeasured three times -> not shown")
    func bracketCompletedButShort() {
        var sequencer = C2BracketSequencer(configurations: [C2Configuration.all[0]])
        for _ in 0..<C2Retry.maxAttempts { sequencer.record(C2ProcessResult(status: .completed, points: [])) }
        #expect(sequencer.next() == .finished(.provisionalFail(configuration: "k1-long", reason: "not shown: lengths left unmeasured")))
    }

    @Test("no configuration -> a finished provisional fail for either sitting")
    func emptyConfigurations() {
        #expect(C2BracketSequencer(configurations: []).next() == .finished(.provisionalFail(configuration: nil, reason: "no configuration ran")))
        #expect(C2ConfirmSequencer(length: 700, configurations: []).next() == .finished(.provisionalFail(configuration: nil, reason: "no configuration ran")))
    }

    @Test("sitting B: collar then five baseline cycles per configuration; all hidden -> pass")
    func confirmPasses() {
        let configs = Array(C2Configuration.all.prefix(2))
        var sequencer = C2ConfirmSequencer(length: 700, configurations: configs)
        for _ in configs {
            guard case .run(_, let lengths) = sequencer.next() else { Issue.record("expected a run"); return }
            #expect(lengths == C2Band.collar(700) + [700, 700, 700, 700, 700])
            sequencer.record(C2ProcessResult(status: .completed, points: points(lengths) { _ in .hiddenNoFold }))
        }
        #expect(sequencer.next() == .finished(.pass))
    }

    @Test("sitting B: one collar point drawn -> provisional fail, later configurations never run")
    func confirmFailsFast() {
        var sequencer = C2ConfirmSequencer(length: 700, configurations: Array(C2Configuration.all.prefix(2)))
        guard case .run(_, let lengths) = sequencer.next() else { return }
        sequencer.record(C2ProcessResult(status: .completed, points: points(lengths) { $0 == 716 ? .stillDrawn : .hiddenNoFold }))
        #expect(sequencer.next() == .finished(.provisionalFail(configuration: "k1-long", reason: "a collar or baseline cycle failed")))
    }

    @Test("sitting B: retries the rest after an inconclusive process; still short after three -> provisional fail; a safety stop ends it")
    func confirmRetriesAndStops() {
        var sequencer = C2ConfirmSequencer(length: 700, configurations: [C2Configuration.all[0]])
        sequencer.record(C2ProcessResult(status: .inconclusive("x"), points: points([684]) { _ in .hiddenNoFold }))
        guard case .run(_, let rest) = sequencer.next() else { return }
        #expect(rest.count == 13)
        sequencer.record(C2ProcessResult(status: .inconclusive("x"), points: []))
        sequencer.record(C2ProcessResult(status: .inconclusive("x"), points: []))
        #expect(sequencer.next() == .finished(.provisionalFail(configuration: "k1-long", reason: "ended after 1 of 14 cycles")))

        var stopped = C2ConfirmSequencer(length: 700, configurations: [C2Configuration.all[0]])
        stopped.record(C2ProcessResult(status: .safetyStop, points: []))
        #expect(stopped.next() == .finished(.safetyStop(configuration: "k1-long")))
        stopped.record(C2ProcessResult(status: .completed, points: []))
    }
}
