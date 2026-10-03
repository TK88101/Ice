// U20 (pre-registration section 7) and section 4's fallback rate, as fixed by
// the runner plan's Q7-Q9.
@testable import IceBarRunCore
import Testing

enum Observations {
    static let granted = ObservationRecord(outcome: .granted, cause: nil, oracleClean: true, attempts: 1)
    static let cleanNot = ObservationRecord(outcome: .notGranted, cause: .notClear, oracleClean: true, attempts: 3)
    static let seenNot = ObservationRecord(outcome: .notGranted, cause: .notClear, oracleClean: false, attempts: 3)
    static let inconclusive = ObservationRecord(outcome: .inconclusive, cause: .inconclusive, oracleClean: true, attempts: 3)
    static let inconclusiveSeen = ObservationRecord(outcome: .inconclusive, cause: .inconclusive, oracleClean: false, attempts: 3)
    static let noGo = ObservationRecord(outcome: .noGo, cause: .noGo, oracleClean: false, attempts: 1)
    static func refused(clean: Bool) -> ObservationRecord {
        ObservationRecord(outcome: .notGranted, cause: .baselineRefused, oracleClean: clean, attempts: 3)
    }

    static func cycle(_ o: [ObservationRecord], controlMiss: Bool = false) -> CycleRecord {
        CycleRecord(observations: o, controlMiss: controlMiss)
    }

    /// Five cycles of four, `bad` of the twenty replaced by `filler`.
    static func length(bad: Int, filler: ObservationRecord) -> [CycleRecord] {
        let all = (0..<20).map { $0 < bad ? filler : granted }
        return stride(from: 0, to: 20, by: 4).map { cycle(Array(all[$0..<$0 + 4])) }
    }
}

@Suite("U20: fallback accounting")
struct FallbackTallyTests {
    typealias O = Observations

    @Test("U20: the denominator is 20, the four observations of five cycles")
    func denominator() {
        let tally = FallbackTally.tally(O.length(bad: 0, filler: O.cleanNot))
        #expect(tally.denominator == 20)
        #expect(tally.numerator == 0)
        #expect(tally.verdict == .pass)
    }

    @Test("U20: 5/20 passes, 6/20 fails")
    func ceiling() {
        #expect(FallbackTally.tally(O.length(bad: 5, filler: O.cleanNot)).verdict == .pass)
        #expect(FallbackTally.tally(O.length(bad: 6, filler: O.cleanNot)).verdict == .fail)
    }

    @Test("U20: the numerator counts not granted with the oracle clean, plus every inconclusive")
    func numerator() {
        let cycles = [O.cycle([O.cleanNot, O.seenNot, O.inconclusive, O.inconclusiveSeen])] + Array(O.length(bad: 0, filler: O.granted).prefix(4))
        let tally = FallbackTally.tally(cycles)
        #expect(tally.numerator == 3)
        #expect(tally.inconclusive == 2)
    }

    @Test("U20: 3 inconclusive of 20 -> the repeat is inconclusive; 2 -> not")
    func repeatInconclusive() {
        #expect(FallbackTally.tally(O.length(bad: 3, filler: O.inconclusive)).verdict == .inconclusive)
        #expect(FallbackTally.tally(O.length(bad: 2, filler: O.inconclusive)).verdict == .pass)
    }

    @Test("U20: a refused-baseline cycle's 4 observations are taken and counted only when oracle-clean")
    func refusedCycle() {
        let refused = O.cycle([O.refused(clean: true), O.refused(clean: false), O.refused(clean: true), O.refused(clean: false)])
        let cycles = [refused] + Array(O.length(bad: 0, filler: O.granted).prefix(4))
        let tally = FallbackTally.tally(cycles)
        #expect(tally.denominator == 20)
        #expect(tally.numerator == 2)
        #expect(tally.byCause[.baselineRefused] == 2)
    }

    @Test("Q8: a cycle with a member missed at a rest control makes each of its observations inconclusive; a NO-GO stays")
    func controlMiss() {
        let effective = FallbackTally.effective(O.cycle([O.granted, O.cleanNot, O.noGo, O.seenNot], controlMiss: true))
        #expect(effective.map(\.outcome) == [.inconclusive, .inconclusive, .noGo, .inconclusive])
        #expect(effective[0].cause == .memberControl)
        #expect(!effective[3].oracleClean)
    }

    @Test("Q9: a NO-GO anywhere decides the length")
    func noGo() {
        let tally = FallbackTally.tally(O.length(bad: 1, filler: O.noGo))
        #expect(tally.verdict == .noGo)
        #expect(tally.noGo == 1)
    }

    @Test("Q9: fewer or more than 20 observations never pass")
    func incomplete() {
        let short = Array(O.length(bad: 0, filler: O.granted).prefix(4))
        #expect(FallbackTally.tally(short).verdict == .incomplete(16))
        let long = O.length(bad: 0, filler: O.granted) + [O.cycle([O.granted])]
        #expect(FallbackTally.tally(long).verdict == .incomplete(21))
    }

    @Test("section 4: the rate split by cause, every numerator observation once")
    func causes() {
        let mix = [O.cleanNot, ObservationRecord(outcome: .notGranted, cause: .texture, oracleClean: true, attempts: 3),
                   ObservationRecord(outcome: .notGranted, cause: .timeout, oracleClean: true, attempts: 3), O.inconclusive]
        let cycles = [O.cycle(mix)] + Array(O.length(bad: 0, filler: O.granted).prefix(4))
        let tally = FallbackTally.tally(cycles)
        #expect(tally.byCause == [.notClear: 1, .texture: 1, .timeout: 1, .inconclusive: 1])
        #expect(tally.byCause.values.reduce(0, +) == tally.numerator)
    }
}
