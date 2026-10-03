// T0: the band per profile from the per-length records.
import SpikeCore
import Testing

@Suite("T0: spike A band")
struct SpikeBandTests {
    func records(_ outcomes: [StepOutcome], from: Double = 400) -> [StepRecord] {
        outcomes.enumerated().map { StepRecord(length: from + Double($0.offset) * 16, outcome: $0.element) }
    }

    @Test("the widest contiguous clean run is the band, with its count")
    func widest() {
        let r = records([.folded(drawn: []), .hiddenClean, .hiddenClean, .drawn(["ell"]), .hiddenClean, .hiddenClean, .hiddenClean, .unknown("x")])
        #expect(SpikeBand.widest(r) == Band(lo: 464, hi: 496, count: 3))
    }

    @Test("no clean length: no band")
    func none() {
        #expect(SpikeBand.widest(records([.folded(drawn: []), .drawn(["ell"]), .unknown("x")])) == nil)
        #expect(SpikeBand.widest([]) == nil)
    }

    @Test("a tie goes to the lower band; the midpoint is the rounded middle")
    func tieAndMidpoint() {
        let r = records([.hiddenClean, .hiddenClean, .folded(drawn: []), .hiddenClean, .hiddenClean])
        #expect(SpikeBand.widest(r) == Band(lo: 400, hi: 416, count: 2))
        #expect(Band(lo: 616, hi: 840, count: 15).midpoint == 728)
        #expect(Band(lo: 400, hi: 416, count: 2).midpoint == 408)
    }

    @Test("an unknown length breaks a run (fail closed); records in any order")
    func unknownBreaks() {
        let r = records([.hiddenClean, .unknown("control"), .hiddenClean])
        #expect(SpikeBand.widest(r) == Band(lo: 400, hi: 400, count: 1))
        #expect(SpikeBand.widest(r.reversed()) == Band(lo: 400, hi: 400, count: 1))
    }
}
