// Q17, Q20: S-adv's order across step processes -- each variant's two sweeps
// (an inconclusive sweep re-run at most twice), then the `«` rest state -- and
// the `«` episodes of several processes numbered as one sitting (Q14).
import IceBarOracle
@testable import IceBarRunCore
import Testing

@Suite("Q17: S-adv across step processes")
struct SAdvSequencerTests {
    @Test("two passing sweeps per variant, the four variants in order, then the `«` rest state")
    func order() {
        var sequencer = SAdvSequencer()
        var steps = [SAdvStep]()
        while true {
            let step = sequencer.next()
            steps.append(step)
            switch step {
            case .sweep: sequencer.record(.pass)
            case .chevron: sequencer.record(.pass)
            case .finished: break
            }
            if case .finished = step { break }
        }
        let sweeps = steps.compactMap { step -> String? in if case .sweep(let v) = step { return v.name } else { return nil } }
        #expect(sweeps == SAdvVariant.all.flatMap { [$0.name, $0.name] })
        #expect(steps.suffix(2) == [.chevron(SAdvVariant.all[0]), .finished(.pass)])
    }

    @Test("an inconclusive sweep is re-run; a third in a row is not shown; a NO-GO ends S-adv")
    func repeats() {
        var sequencer = SAdvSequencer()
        _ = sequencer.next()
        sequencer.record(.inconclusive)
        #expect(sequencer.next() == .sweep(SAdvVariant.all[0]))
        sequencer.record(.inconclusive)
        sequencer.record(.inconclusive)
        #expect(sequencer.next() == .finished(.notShown("dark-ordinary: inconclusive three times")))
        var noGo = SAdvSequencer()
        _ = noGo.next()
        noGo.record(.noGo)
        #expect(noGo.next() == .finished(.noGo))
    }

    @Test("a NO-GO in the `«` rest state ends S-adv as NO-GO; an inconclusive one is re-run")
    func chevronStep() {
        var sequencer = SAdvSequencer()
        for _ in 0..<(SAdvVariant.all.count * SAdvVariant.sweepsPerVariant) {
            _ = sequencer.next()
            sequencer.record(.pass)
        }
        #expect(sequencer.next() == .chevron(SAdvVariant.all[0]))
        sequencer.record(.inconclusive)
        #expect(sequencer.next() == .chevron(SAdvVariant.all[0]))
        sequencer.record(.noGo)
        #expect(sequencer.next() == .finished(.noGo))
    }

    @Test("Q14: episodes from several processes are renumbered to continue across the sitting")
    func merge() {
        let first = [BObservation(episode: 0, axChevron: false, pixels: .absent), BObservation(episode: 1, axChevron: true, pixels: .present)]
        let second = [BObservation(episode: 1, axChevron: true, pixels: .present), BObservation(episode: 2, axChevron: true, pixels: .present)]
        let merged = ChevronEpisodes.merged([first, second])
        #expect(merged.map(\.episode) == [0, 1, 2, 3])
        #expect(ChevronEpisodes.merged([]) == [])
    }
}
