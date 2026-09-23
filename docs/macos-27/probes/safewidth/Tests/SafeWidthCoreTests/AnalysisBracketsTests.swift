// Analysis.brackets(for:tolerance:) tests (BracketsTests suite).
import Testing
@testable import SafeWidthCore

// MARK: - Analysis.brackets(for:tolerance:)

@Suite("Analysis.brackets")
struct BracketsTests {

    /// The realistic up leg from the spec: visible at 8/16/24, overflowed from
    /// 32 through 600, visible again at 632.
    static func realisticUpLeg() -> [LegSample] {
        [
            LegSample(length: 8, target: .visible(x: 10)),
            LegSample(length: 16, target: .visible(x: 20)),
            LegSample(length: 24, target: .visible(x: 30)),
            LegSample(length: 32, target: .overflowed),
            LegSample(length: 300, target: .overflowed),
            LegSample(length: 600, target: .overflowed),
            LegSample(length: 632, target: .visible(x: 40)),
        ]
    }

    @Test("realistic up leg gives hide .at(24, 32) and top .at(600, 632)")
    func realisticUpLegBrackets() {
        let result = Analysis.brackets(for: Self.realisticUpLeg(), tolerance: 1)
        #expect(result.hide == .at(lo: 24, hi: 32))
        #expect(result.top == .at(lo: 600, hi: 632))
    }

    @Test("shuffled order of the same samples gives identical brackets")
    func shuffledOrderGivesIdenticalBrackets() {
        let ordered = Self.realisticUpLeg()
        let shuffled = [ordered[6], ordered[0], ordered[4], ordered[3], ordered[5], ordered[1], ordered[2]]
        let orderedResult = Analysis.brackets(for: ordered, tolerance: 1)
        let shuffledResult = Analysis.brackets(for: shuffled, tolerance: 1)
        #expect(orderedResult == shuffledResult)
    }

    @Test("a down leg (samples taken in descending length order) gives identical brackets")
    func downLegGivesIdenticalBrackets() {
        let ordered = Self.realisticUpLeg()
        let descending = Array(ordered.reversed())
        let orderedResult = Analysis.brackets(for: ordered, tolerance: 1)
        let descendingResult = Analysis.brackets(for: descending, tolerance: 1)
        #expect(orderedResult == descendingResult)
    }

    @Test("unsettled samples are ignored")
    func unsettledSamplesIgnored() {
        let samples = [
            LegSample(length: 10, target: .visible(x: 1)),
            LegSample(length: 15, target: .overflowed, unsettled: true),
            LegSample(length: 20, target: .overflowed),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.hide == .at(lo: 10, hi: 20))
    }

    @Test("ambiguous and invisibleUnconfirmed samples are never used as lo, nor count as hide's new state")
    func ambiguousAndUnconfirmedNeverCountForHide() {
        let samples = [
            LegSample(length: 0, target: .visible(x: 1)),
            LegSample(length: 5, target: .invisibleUnconfirmed),
            LegSample(length: 10, target: .ambiguous),
            LegSample(length: 15, target: .overflowed),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.hide == .at(lo: 0, hi: 15))
    }

    @Test("hide observed at the smallest tested length has a nil lo")
    func hideAtSmallestLengthHasNilLo() {
        let samples = [
            LegSample(length: 5, target: .overflowed),
            LegSample(length: 10, target: .visible(x: 1)),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.hide == .at(lo: nil, hi: 5))
    }

    @Test("top is notObserved when hide itself was never observed")
    func topNotObservedWhenHideNotObserved() {
        let samples = [
            LegSample(length: 10, target: .visible(x: 1)),
            LegSample(length: 20, target: .visible(x: 2)),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        if case .notObserved(let maxTested) = result.hide {
            #expect(maxTested == 20)
        } else {
            Issue.record("expected hide to be notObserved")
        }
        #expect(result.top == .notObserved(maxTested: 20))
    }

    @Test("top is notObserved when there is no visible sample above hide's hi")
    func topNotObservedWhenNoVisibleAboveHideHi() {
        let samples = [
            LegSample(length: 10, target: .visible(x: 1)),
            LegSample(length: 20, target: .overflowed),
            LegSample(length: 30, target: .overflowed),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.hide == .at(lo: 10, hi: 20))
        #expect(result.top == .notObserved(maxTested: 30))
    }

    @Test("edge plateau with fewer than 2 samples is notObserved")
    func edgePlateauTooSmallIsNotObserved() {
        let samples = [
            LegSample(length: 10, target: .overflowed, spacerLeft: 100),
            LegSample(length: 20, target: .overflowed, spacerLeft: 50),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.edge == .notObserved(maxTested: 20))
    }

    @Test("edge with fewer than 2 spacerLeft samples is notObserved")
    func edgeWithFewerThanTwoObservationsIsNotObserved() {
        let samples = [
            LegSample(length: 10, target: .overflowed, spacerLeft: 50),
            LegSample(length: 20, target: .overflowed, spacerLeft: nil),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.edge == .notObserved(maxTested: 20))
    }

    @Test("edge plateau within tolerance brackets the transition")
    func edgePlateauWithinTolerance() {
        let samples = [
            LegSample(length: 10, target: .overflowed, spacerLeft: 100),
            LegSample(length: 20, target: .overflowed, spacerLeft: 50.5),
            LegSample(length: 30, target: .overflowed, spacerLeft: 50),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.edge == .at(lo: 10, hi: 20))
    }

    @Test("sat plateau within tolerance brackets the transition")
    func satPlateauWithinTolerance() {
        let samples = [
            LegSample(length: 10, target: .overflowed, spacerAppKitWidth: 10),
            LegSample(length: 20, target: .overflowed, spacerAppKitWidth: 99.5),
            LegSample(length: 30, target: .overflowed, spacerAppKitWidth: 100),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.sat == .at(lo: 10, hi: 20))
    }

    @Test("sat with fewer than 2 width samples is notObserved")
    func satWithFewerThanTwoObservationsIsNotObserved() {
        let samples = [
            LegSample(length: 10, target: .overflowed, spacerAppKitWidth: 10),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.sat == .notObserved(maxTested: 10))
    }

    @Test("selfov skips samples with nil spacerDrawn")
    func selfovSkipsNilSamples() {
        let samples = [
            LegSample(length: 10, target: .overflowed, spacerDrawn: true),
            LegSample(length: 20, target: .overflowed, spacerDrawn: nil),
            LegSample(length: 30, target: .overflowed, spacerDrawn: false),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.selfov == .at(lo: 10, hi: 30))
    }

    @Test("harm brackets true against false")
    func harmBracketsTrueAgainstFalse() {
        let samples = [
            LegSample(length: 10, target: .overflowed, harm: false),
            LegSample(length: 20, target: .overflowed, harm: true),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.harm == .at(lo: 10, hi: 20))
    }

    @Test("an empty leg makes every bracket notObserved at zero")
    func emptyLegIsAllNotObserved() {
        let result = Analysis.brackets(for: [], tolerance: 1)
        let expected = Bracket.notObserved(maxTested: 0)
        #expect(result.hide == expected)
        #expect(result.edge == expected)
        #expect(result.sat == expected)
        #expect(result.selfov == expected)
        #expect(result.top == expected)
        #expect(result.harm == expected)
    }

    // MARK: Finding 5 (P1) — "unknown observation is never used as lo" was
    // only exercised for hide/selfov; top, edge and sat had no such test.

    @Test("top's old state requires overflowed, not merely non-visible")
    func topOldStateRequiresOverflowedNotMerelyNonVisible() {
        let samples = [
            LegSample(length: 10, target: .visible(x: 1)),
            LegSample(length: 32, target: .overflowed),
            LegSample(length: 600, target: .ambiguous),
            LegSample(length: 632, target: .visible(x: 2)),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.hide == .at(lo: 10, hi: 32))
        // A mutant treating "ambiguous" as an old-state match would raise lo to 600.
        #expect(result.top == .at(lo: 32, hi: 632))
    }

    @Test("edge and sat never take lo from a sample with a nil value")
    func edgeLoNeverTakenFromNilValuedSample() {
        let samples = [
            LegSample(length: 10, target: .overflowed, spacerLeft: 100),
            LegSample(length: 15, target: .overflowed, spacerLeft: nil),
            LegSample(length: 20, target: .overflowed, spacerLeft: 50.5),
            LegSample(length: 30, target: .overflowed, spacerLeft: 50),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        // A mutant reading lo from the whole sample list (not just `known`) would give 15.
        #expect(result.edge == .at(lo: 10, hi: 20))
    }

    @Test("top's lo boundary is >= hideHi, not > hideHi")
    func topLoBoundaryIsInclusiveOfHideHi() {
        let samples = [
            LegSample(length: 10, target: .visible(x: 1)),
            LegSample(length: 20, target: .overflowed),
            LegSample(length: 30, target: .visible(x: 2)),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.hide == .at(lo: 10, hi: 20))
        // A mutant using `>` instead of `>=` would give lo: nil here.
        #expect(result.top == .at(lo: 20, hi: 30))
    }

    // MARK: Finding 6 (P1) — maxTested must ignore unsettled samples.

    @Test("maxTested ignores an unsettled sample even when it is the largest length")
    func maxTestedIgnoresLargestUnsettledSample() {
        let samples = [
            LegSample(length: 10, target: .visible(x: 1)),
            LegSample(length: 20, target: .overflowed),
            LegSample(length: 1000, target: .overflowed, unsettled: true),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        // `edge` never observed any spacerLeft, so it reports maxTested; it must be
        // 20 (the largest settled length), not 1000 (the largest length overall).
        #expect(result.edge == .notObserved(maxTested: 20))
    }

    @Test("every sample unsettled behaves like an empty leg")
    func everySampleUnsettledBehavesLikeEmptyLeg() {
        let samples = [
            LegSample(length: 5, target: .overflowed, unsettled: true),
            LegSample(length: 15, target: .visible(x: 1), unsettled: true),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        let expected = Bracket.notObserved(maxTested: 0)
        #expect(result.hide == expected)
        #expect(result.edge == expected)
        #expect(result.sat == expected)
        #expect(result.selfov == expected)
        #expect(result.top == expected)
        #expect(result.harm == expected)
    }

    // MARK: Finding 8 (P2) — exact boundary values.

    @Test("top's hi must be strictly above hideHi even when a length repeats")
    func topHiStrictlyAboveHideHiWithRepeatedLength() {
        let samples = [
            LegSample(length: 10, target: .visible(x: 1)),
            LegSample(length: 20, target: .overflowed),
            LegSample(length: 20, target: .visible(x: 2)),
            LegSample(length: 30, target: .visible(x: 3)),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        #expect(result.hide == .at(lo: 10, hi: 20))
        // A mutant using `>=` for top's new-state search would give hi: 20 here.
        #expect(result.top == .at(lo: 20, hi: 30))
    }

    @Test("edge plateau boundary at exactly extreme + tolerance is included")
    func edgePlateauBoundaryIsInclusive() {
        let samples = [
            LegSample(length: 10, target: .overflowed, spacerLeft: 100),
            LegSample(length: 20, target: .overflowed, spacerLeft: 51),
            LegSample(length: 30, target: .overflowed, spacerLeft: 50),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        // extreme=50, boundary=51=extreme+tolerance. A mutant using `<` here would
        // exclude 51, leaving a plateau of size 1 and reporting .notObserved(30).
        #expect(result.edge == .at(lo: 10, hi: 20))
    }

    @Test("sat plateau boundary at exactly extreme - tolerance is included")
    func satPlateauBoundaryIsInclusive() {
        let samples = [
            LegSample(length: 10, target: .overflowed, spacerAppKitWidth: 0),
            LegSample(length: 20, target: .overflowed, spacerAppKitWidth: 99),
            LegSample(length: 30, target: .overflowed, spacerAppKitWidth: 100),
        ]
        let result = Analysis.brackets(for: samples, tolerance: 1)
        // extreme=100, boundary=99=extreme-tolerance. A mutant using `>` here would
        // exclude 99, leaving a plateau of size 1 and reporting .notObserved(30).
        #expect(result.sat == .at(lo: 10, hi: 20))
    }
}
