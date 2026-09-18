// Planner.grid, Planner.nextBisection, Planner.staircase tests, and
// the Analysis/Planner precondition trap suite.
import Testing
@testable import SafeWidthCore

// MARK: - Planner.grid

@Suite("Planner.grid")
struct GridTests {

    @Test("segments produce their stepped values, extras are added, duplicates removed")
    func segmentsExtrasAndDuplicates() {
        let segments = [
            GridSegment(from: 0, to: 20, step: 5),
            GridSegment(from: 100, to: 100, step: 0),
        ]
        let result = Planner.grid(segments, extras: [20, 50])
        #expect(result == [0, 5, 10, 15, 20, 50, 100])
    }

    // MARK: Finding 9 (P2) — values must be from + k*step, not an accumulated running total.

    @Test("a long fine-stepped grid reaches `to` exactly instead of drifting past it")
    func longFineGridReachesToExactly() {
        // The `value += step` accumulation drifts past `to + 1e-9` before k reaches
        // 300000 and silently drops `to` (ends at 2999.9900000190623 instead of 3000).
        let result = Planner.grid([GridSegment(from: 0, to: 3000, step: 0.01)], extras: [])
        #expect(result.last == 3000)
        #expect(result.count == 300_001)
    }

    // MARK: Finding 8 (P2) — the 1e-9 end slop and the dedup tolerance.

    @Test("the 1e-9 end slop includes a value that float arithmetic pushes just past `to`")
    func gridEndSlopIncludesFloatDriftedValue() {
        let result = Planner.grid([GridSegment(from: 0, to: 0.3, step: 0.1)], extras: [])
        let expectedLast = 3 * 0.1 // == 0.30000000000000004, strictly greater than the 0.3 literal
        #expect(result.count == 4)
        #expect(result.last == expectedLast)
    }

    @Test("values within the 1e-9 dedup tolerance collapse even without being exact duplicates")
    func dedupCollapsesNearDuplicates() {
        // 0.1 + 0.2 == 0.30000000000000004, not exactly 0.3, but within 1e-9 of it.
        let result = Planner.grid([], extras: [0.3, 0.1 + 0.2])
        #expect(result.count == 1)
    }

    @Test("a step > 0 segment with from > to adds nothing")
    func stepPositiveSegmentWithFromGreaterThanToAddsNothing() {
        let result = Planner.grid([GridSegment(from: 10, to: 5, step: 1)], extras: [])
        #expect(result == [])
    }

    @Test("a negative step contributes only from")
    func negativeStepContributesOnlyFrom() {
        let segments = [GridSegment(from: 7, to: 20, step: -1)]
        #expect(Planner.grid(segments, extras: []) == [7])
    }

    @Test("no segments and no extras yields an empty grid")
    func noSegmentsNoExtrasIsEmpty() {
        #expect(Planner.grid([], extras: []) == [])
    }

    @Test("extras alone are sorted and deduplicated")
    func extrasAloneAreSortedAndDeduplicated() {
        #expect(Planner.grid([], extras: [5, 1, 5, 3]) == [1, 3, 5])
    }
}

// MARK: - Planner.nextBisection

@Suite("Planner.nextBisection")
struct NextBisectionTests {

    @Test("requires lo < hi")
    func requiresLoLessThanHi() {
        #expect(Planner.nextBisection(lo: 5, hi: 5, resolution: 0) == nil)
        #expect(Planner.nextBisection(lo: 6, hi: 5, resolution: 0) == nil)
    }

    @Test("nil when the span is already at or below resolution")
    func nilWhenSpanAtResolution() {
        #expect(Planner.nextBisection(lo: 0, hi: 5, resolution: 5) == nil)
    }

    @Test("returns the rounded midpoint when it lies strictly inside the span")
    func returnsRoundedMidpoint() {
        #expect(Planner.nextBisection(lo: 0, hi: 3, resolution: 1) == 2)
    }

    @Test("an exact .5 midpoint rounds away from zero, not to even (finding 8, P2)")
    func exactHalfMidpointRoundsAwayFromZero() {
        // mid = 2.5; "round half away from zero" gives 3, "round half to even" gives 2.
        #expect(Planner.nextBisection(lo: 0, hi: 5, resolution: 1) == 3)
    }

    @Test("nil when the rounded midpoint collapses onto an endpoint")
    func nilWhenMidpointCollapsesOntoEndpoint() {
        #expect(Planner.nextBisection(lo: 0, hi: 1, resolution: 0) == nil)
    }
}

// MARK: - Planner.staircase

@Suite("Planner.staircase")
struct StaircaseTests {

    @Test("from == to yields a single-element result")
    func fromEqualsToYieldsSingleElement() {
        #expect(Planner.staircase(from: 50, to: 50, coarse: 10, fine: 2, fineAround: [50], radius: 5) == [50])
    }

    @Test("ascending run slows to fine near a center and speeds back up to coarse")
    func ascendingRunSlowsNearCenter() {
        let result = Planner.staircase(from: 0, to: 100, coarse: 10, fine: 5, fineAround: [50], radius: 5)
        #expect(result == [10, 20, 30, 40, 45, 50, 55, 60, 70, 80, 90, 100])
    }

    @Test("ascending run clamps the final coarse step to `to`")
    func ascendingRunClampsFinalStep() {
        let result = Planner.staircase(from: 0, to: 95, coarse: 10, fine: 5, fineAround: [], radius: 0)
        #expect(result == [10, 20, 30, 40, 50, 60, 70, 80, 90, 95])
    }

    @Test("descending run steps downward and ends exactly at `to`")
    func descendingRunStepsDownward() {
        let result = Planner.staircase(from: 100, to: 0, coarse: 10, fine: 5, fineAround: [], radius: 0)
        #expect(result == [90, 80, 70, 60, 50, 40, 30, 20, 10, 0])
    }

    @Test("descending run clamps the final coarse step to `to`")
    func descendingRunClampsFinalStep() {
        let result = Planner.staircase(from: 25, to: 7, coarse: 10, fine: 5, fineAround: [], radius: 0)
        #expect(result == [15, 7])
    }

    @Test("the result is strictly monotone with no duplicates")
    func resultIsStrictlyMonotone() {
        let result = Planner.staircase(from: 0, to: 100, coarse: 10, fine: 5, fineAround: [50], radius: 5)
        let increasing = zip(result, result.dropFirst()).allSatisfy { $0 < $1 }
        #expect(increasing)
        #expect(Set(result).count == result.count)
    }

    // MARK: Finding 7 (P1) — the spec explicitly asks for staircase-down-with-fine tests.

    @Test("descending run slows to fine near a center and speeds back up to coarse")
    func descendingRunSlowsNearCenter() {
        let result = Planner.staircase(from: 100, to: 0, coarse: 10, fine: 5, fineAround: [50], radius: 5)
        #expect(result == [90, 80, 70, 60, 55, 50, 45, 40, 30, 20, 10, 0])
    }

    @Test("the lookahead uses the coarse step, not the fine step, so it can tell them apart")
    func lookaheadUsesCoarseStepNotFineStep() {
        // At current=40, looking ahead by coarse (+10 -> 50) lands exactly on the
        // center, so fine steps begin at 40. A mutant that looks ahead by the fine
        // step (+4 -> 44) would miss the region there and jump straight to 50
        // instead, producing [10, 20, 30, 50, 54, 58, 68, 78, 88, 98, 100].
        let result = Planner.staircase(from: 0, to: 100, coarse: 10, fine: 4, fineAround: [50], radius: 5)
        #expect(result == [10, 20, 30, 40, 44, 48, 52, 56, 66, 76, 86, 96, 100])
    }
}

// MARK: - Preconditions (findings 10 and 11, P2)
//
// These lock down the fail-fast guards added for pathological inputs: rather
// than hang (an infinite loop that grows a result array until memory runs
// out) or silently produce NaN, the offending call now traps immediately.
// Exit tests spawn a subprocess, so they can observe the trap without taking
// this test run down with it.

@Suite("Analysis preconditions")
struct PreconditionTests {

    @Test("verdict traps on a negative tolerance")
    func verdictTrapsOnNegativeTolerance() async {
        await #expect(processExitsWith: .failure) {
            _ = Analysis.verdict(hide: [.at(lo: 20, hi: 30)], bound: [.at(lo: 25, hi: 35)], tolerance: -10)
        }
    }

    @Test("verdict traps on a non-finite tolerance")
    func verdictTrapsOnNonFiniteTolerance() async {
        await #expect(processExitsWith: .failure) {
            _ = Analysis.verdict(hide: [.at(lo: 20, hi: 30)], bound: [.at(lo: 25, hi: 35)], tolerance: .nan)
        }
    }

    @Test("verdict traps on a non-finite bracket value instead of producing NaN")
    func verdictTrapsOnNonFiniteBracketValue() async {
        await #expect(processExitsWith: .failure) {
            _ = Analysis.verdict(
                hide: [.at(lo: 0, hi: .infinity)],
                bound: [.at(lo: .infinity, hi: .infinity)],
                tolerance: 1
            )
        }
    }

    @Test("brackets traps on a non-finite tolerance")
    func bracketsTrapsOnNonFiniteTolerance() async {
        await #expect(processExitsWith: .failure) {
            _ = Analysis.brackets(for: [LegSample(length: 10, target: .overflowed)], tolerance: -1)
        }
    }

    @Test("brackets traps on a NaN sample length instead of producing NaN")
    func bracketsTrapsOnNaNSampleLength() async {
        await #expect(processExitsWith: .failure) {
            _ = Analysis.brackets(for: [LegSample(length: .nan, target: .overflowed)], tolerance: 1)
        }
    }

    @Test("staircase traps on a non-finite `from`")
    func staircaseTrapsOnNonFiniteFrom() async {
        await #expect(processExitsWith: .failure) {
            _ = Planner.staircase(from: .nan, to: 10, coarse: 1, fine: 1, fineAround: [], radius: 0)
        }
    }

    @Test("staircase traps on a non-finite `to` instead of climbing forever")
    func staircaseTrapsOnNonFiniteTo() async {
        await #expect(processExitsWith: .failure) {
            _ = Planner.staircase(from: 0, to: .infinity, coarse: 10, fine: 1, fineAround: [], radius: 0)
        }
    }

    @Test("staircase traps when the step is too small to advance, instead of stalling forever")
    func staircaseTrapsWhenStepTooSmallToAdvance() async {
        await #expect(processExitsWith: .failure) {
            // At this magnitude the double ulp is 2, so `current + 1` rounds back to `current`.
            _ = Planner.staircase(
                from: 9_007_199_254_740_992, to: 9_007_199_254_741_092,
                coarse: 10, fine: 1, fineAround: [9_007_199_254_740_992], radius: 5
            )
        }
    }

    @Test("grid traps on a non-finite `to` instead of growing forever")
    func gridTrapsOnNonFiniteTo() async {
        await #expect(processExitsWith: .failure) {
            _ = Planner.grid([GridSegment(from: 0, to: .infinity, step: 1)], extras: [])
        }
    }

    @Test("grid no longer stalls at 2^53 now that values are computed as from + k*step")
    func gridNoLongerStallsAtDoublePrecisionBoundary() {
        // Regression for finding 9: with the old `value += step` accumulation this
        // was a true infinite loop (2^53 + 1 rounds back to 2^53).
        let result = Planner.grid(
            [GridSegment(from: 9_007_199_254_740_992, to: 9_007_199_254_741_092, step: 1)],
            extras: []
        )
        #expect(result.first == 9_007_199_254_740_992)
        #expect(result.last == 9_007_199_254_741_092)
    }
}
