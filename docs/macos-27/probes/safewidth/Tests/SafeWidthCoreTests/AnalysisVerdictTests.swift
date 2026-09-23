// Analysis.verdict, Analysis.headline, and Analysis.intersection tests
// (VerdictTests, HeadlineTests, IntersectionTests suites).
import Testing
@testable import SafeWidthCore

// MARK: - Analysis.verdict(hide:bound:tolerance:)

@Suite("Analysis.verdict")
struct VerdictTests {

    @Test("holds with the expected margin when brackets are cleanly separated")
    func holdsWithMargin() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 20, hi: 30)],
            bound: [.at(lo: 50, hi: 60)],
            tolerance: 1
        )
        #expect(verdict == .holds(margin: 20, gridScoped: false))
    }

    @Test("holds gridScoped when the bound was never observed")
    func holdsGridScopedWhenBoundNeverObserved() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 20, hi: 30)],
            bound: [.notObserved(maxTested: 500)],
            tolerance: 1
        )
        #expect(verdict == .holds(margin: 470, gridScoped: true))
    }

    @Test("insufficient when the tested grid ends too close to W_hide")
    func insufficientWhenGridEndsTooClose() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 20, hi: 30)],
            bound: [.notObserved(maxTested: 30.5)],
            tolerance: 1
        )
        // Exact spec wording, not just the case: finding 8 (P2).
        #expect(verdict == .insufficient(reason: "tested grid ends too close to W_hide"))
    }

    @Test("insufficient when there is no bound data at all")
    func insufficientWhenNoBoundData() {
        let verdict = Analysis.verdict(hide: [.at(lo: 20, hi: 30)], bound: [], tolerance: 1)
        #expect(verdict == .insufficient(reason: "no bound data"))
    }

    @Test("fails when the bound's hi is at or before hide's lo")
    func failsWhenBoundHiAtOrBeforeHideLo() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 20, hi: 30)],
            bound: [.at(lo: 5, hi: 15)],
            tolerance: 1
        )
        // Finding 8 (P2): pin that the reason names the bound's hi, not just the case.
        guard case .fails(let reason) = verdict else {
            Issue.record("expected fails, got \(verdict)")
            return
        }
        #expect(reason.contains("15"))
    }

    @Test("insufficient when hide and bound brackets overlap")
    func insufficientOnOverlap() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 20, hi: 30)],
            bound: [.at(lo: 25, hi: 35)],
            tolerance: 1
        )
        // Finding 8 (P2): pin that the reason mentions the overlap, not just the case.
        guard case .insufficient(let reason) = verdict else {
            Issue.record("expected insufficient, got \(verdict)")
            return
        }
        #expect(reason.contains("overlap"))
    }

    @Test("insufficient when repeats disagree on whether the target overflowed")
    func insufficientWhenRepeatsDisagreeOnHide() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 10, hi: 20), .notObserved(maxTested: 50)],
            bound: [.at(lo: 60, hi: 70)],
            tolerance: 1
        )
        #expect(verdict == .insufficient(reason: "repeats disagree on whether the target overflowed"))
    }

    @Test("fails when every repeat never overflowed")
    func failsWhenAllHidesNotObserved() {
        let verdict = Analysis.verdict(
            hide: [.notObserved(maxTested: 10), .notObserved(maxTested: 20)],
            bound: [.at(lo: 60, hi: 70)],
            tolerance: 1
        )
        #expect(verdict == .fails(reason: "target never overflowed on the tested grid"))
    }

    @Test("insufficient when hide repeats array is empty")
    func insufficientWhenNoRepeats() {
        let verdict = Analysis.verdict(hide: [], bound: [.at(lo: 60, hi: 70)], tolerance: 1)
        #expect(verdict == .insufficient(reason: "no repeats"))
    }

    @Test("a bound observed at the smallest tested length (nil lo) never crashes and resolves via hi alone")
    func boundAtSmallestLengthWithNilLo() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 50, hi: 60)],
            bound: [.at(lo: nil, hi: 40)],
            tolerance: 1
        )
        // Finding 8 (P2): pin that the reason names the bound's hi.
        guard case .fails(let reason) = verdict else {
            Issue.record("expected fails, got \(verdict)")
            return
        }
        #expect(reason.contains("40"))
    }

    @Test("gridScoped is true when only some repeats observed the bound")
    func gridScopedWhenPartiallyObserved() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 20, hi: 30), .at(lo: 20, hi: 30)],
            bound: [.at(lo: 50, hi: 60), .notObserved(maxTested: 500)],
            tolerance: 1
        )
        #expect(verdict == .holds(margin: 20, gridScoped: true))
    }

    // MARK: A repeat that ended before reaching the bound still limits the margin.
    // Review round 4: the observed repeats alone used to decide it, so a leg cut
    // short just above W_hide could not pull the margin down.

    @Test("a repeat cut short just above W_hide makes a mixed verdict insufficient")
    func censoredRepeatTooCloseIsInsufficient() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 16, hi: 20), .at(lo: 16, hi: 20)],
            bound: [.at(lo: 640, hi: 864), .notObserved(maxTested: 20)],
            tolerance: 4
        )
        #expect(verdict == .insufficient(reason: "a repeat's tested range ends too close to W_hide"))
    }

    @Test("a censored repeat below every observed bound sets the margin")
    func censoredRepeatBelowObservedSetsMargin() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 16, hi: 20), .at(lo: 16, hi: 20)],
            bound: [.at(lo: 640, hi: 864), .notObserved(maxTested: 300)],
            tolerance: 4
        )
        #expect(verdict == .holds(margin: 280, gridScoped: true))
    }

    // MARK: Finding 3 (P1) — repeat aggregations (min vs max) were untested.
    // Each case below is built so swapping the named aggregation's min/max
    // flips the verdict, catching the corresponding mutant.

    @Test("M (min maxTested over notObserved bound repeats) is a min, not a max")
    func mAggregationIsMin() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 20, hi: 30)],
            bound: [.notObserved(maxTested: 500), .notObserved(maxTested: 40)],
            tolerance: 20
        )
        // M=min(500,40)=40; margin=40-30=10 < tolerance 20 -> insufficient.
        // A mutant using max(500,40)=500 would give .holds(margin: 470, gridScoped: true).
        #expect(verdict == .insufficient(reason: "tested grid ends too close to W_hide"))
    }

    @Test("H (max hide.hi over repeats) is a max, not a min")
    func hAggregationIsMax() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 20, hi: 30), .at(lo: 40, hi: 50)],
            bound: [.at(lo: 55, hi: 60)],
            tolerance: 10
        )
        // H=max(30,50)=50; H+tol=60 > boundLoMin=55 -> insufficient (overlap).
        // A mutant using min(30,50)=30 would give .holds(margin: 25, gridScoped: false).
        guard case .insufficient = verdict else {
            Issue.record("expected insufficient, got \(verdict)")
            return
        }
    }

    @Test("B_lo (min lo over observed bound repeats) is a min, not a max")
    func bLoAggregationIsMin() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 0, hi: 30)],
            bound: [.at(lo: 5, hi: 60), .at(lo: 35, hi: 70)],
            tolerance: 5
        )
        // B_lo=min(5,35)=5; H+tol=35 > B_lo=5 -> insufficient (overlap).
        // A mutant using max(5,35)=35 would give .holds(margin: 5, gridScoped: false),
        // since H+tol(35) <= 35 would then hold.
        guard case .insufficient = verdict else {
            Issue.record("expected insufficient, got \(verdict)")
            return
        }
    }

    @Test("B_hiMin (min hi over observed bound repeats) is a min, not a max")
    func bHiMinAggregationIsMin() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 20, hi: 30)],
            bound: [.at(lo: 5, hi: 15), .at(lo: 50, hi: 60)],
            tolerance: 1
        )
        // B_hiMin=min(15,60)=15 <= hideLoMin=20 -> fails.
        // A mutant using max(15,60)=60 would fall through to .insufficient instead.
        guard case .fails = verdict else {
            Issue.record("expected fails, got \(verdict)")
            return
        }
    }

    @Test("hideLoMin (min hide.lo over repeats) is a min, not a max")
    func hideLoMinAggregationIsMin() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 5, hi: 20), .at(lo: 15, hi: 30)],
            bound: [.at(lo: nil, hi: 10)],
            tolerance: 1
        )
        // hideLoMin=min(5,15)=5; boundHiMin=10 > 5 -> not fails; falls through to insufficient.
        // A mutant using max(5,15)=15 would give .fails(...) since 10 <= 15.
        guard case .insufficient = verdict else {
            Issue.record("expected insufficient, got \(verdict)")
            return
        }
    }

    // MARK: Finding 4 (P1) — a missing/nil lo must map to -infinity, never to hi.

    @Test("a bound's nil lo maps to -infinity, not to its own hi")
    func boundNilLoMapsToNegativeInfinity() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 10, hi: 20)],
            bound: [.at(lo: nil, hi: 30)],
            tolerance: 1
        )
        // A mutant mapping nil lo to hi (30) would give .holds(margin: 10, gridScoped: false).
        #expect(verdict == .insufficient(reason: "the hide and bound brackets overlap"))
    }

    @Test("hide's nil lo maps to -infinity, not to its own hi")
    func hideNilLoMapsToNegativeInfinity() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: nil, hi: 5)],
            bound: [.at(lo: nil, hi: 3)],
            tolerance: 1
        )
        // A mutant mapping hide's nil lo to its hi (5) would give .fails(...) since
        // boundHiMin(3) <= hideLoMin(5) would then hold.
        guard case .insufficient = verdict else {
            Issue.record("expected insufficient, got \(verdict)")
            return
        }
    }

    // MARK: Finding 8 (P2) — exact boundary values for the >= / <= comparisons.

    @Test("M - H == tolerance holds (boundary is inclusive)")
    func marginEqualToToleranceHolds() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 0, hi: 10)],
            bound: [.notObserved(maxTested: 20)],
            tolerance: 10
        )
        #expect(verdict == .holds(margin: 10, gridScoped: true))
    }

    @Test("B_hiMin == hideLoMin fails (boundary is inclusive)")
    func boundHiEqualToHideLoFails() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 20, hi: 30)],
            bound: [.at(lo: nil, hi: 20)],
            tolerance: 1
        )
        guard case .fails = verdict else {
            Issue.record("expected fails, got \(verdict)")
            return
        }
    }

    @Test("H + tolerance == B_lo holds (boundary is inclusive)")
    func marginBoundaryAtToleranceHolds() {
        let verdict = Analysis.verdict(
            hide: [.at(lo: 0, hi: 10)],
            bound: [.at(lo: 11, hi: 20)],
            tolerance: 1
        )
        #expect(verdict == .holds(margin: 1, gridScoped: false))
    }
}

// MARK: - Analysis.headline(_:)

@Suite("Analysis.headline")
struct HeadlineTests {

    @Test("empty dictionary is insufficient")
    func emptyDictionaryIsInsufficient() {
        #expect(Analysis.headline([:]) == .insufficient(reason: "no bounds"))
    }

    @Test("fails wins over insufficient regardless of Bound.allCases order")
    func failsWinsOverInsufficient() {
        let verdict = Analysis.headline([
            .edge: .insufficient(reason: "a"),
            .top: .fails(reason: "b"),
        ])
        #expect(verdict == .fails(reason: "top: b"))
    }

    @Test("among multiple fails, the first in Bound.allCases order wins")
    func firstFailingBoundInAllCasesOrderWins() {
        let verdict = Analysis.headline([
            .harm: .fails(reason: "h"),
            .edge: .fails(reason: "e"),
        ])
        #expect(verdict == .fails(reason: "edge: e"))
    }

    @Test("among multiple insufficients, the first in Bound.allCases order wins")
    func firstInsufficientBoundInAllCasesOrderWins() {
        let verdict = Analysis.headline([
            .harm: .insufficient(reason: "h"),
            .sat: .insufficient(reason: "s"),
        ])
        #expect(verdict == .insufficient(reason: "sat: s"))
    }

    @Test("all holds yields the minimum margin and ORs gridScoped")
    func allHoldsYieldsMinimumMarginAndOredGridScoped() {
        let verdict = Analysis.headline([
            .edge: .holds(margin: 10, gridScoped: false),
            .sat: .holds(margin: 5, gridScoped: true),
        ])
        #expect(verdict == .holds(margin: 5, gridScoped: true))
    }
}

// MARK: - Analysis.intersection(_:)

@Suite("Analysis.intersection")
struct IntersectionTests {

    @Test("empty input has no intersection")
    func emptyInputHasNoIntersection() {
        #expect(Analysis.intersection([]) == nil)
    }

    @Test("disjoint spans have no intersection")
    func disjointSpansHaveNoIntersection() {
        let spans = [Span(lo: 0, hi: 10), Span(lo: 20, hi: 30)]
        #expect(Analysis.intersection(spans) == nil)
    }

    @Test("overlapping spans intersect to the shared range")
    func overlappingSpansIntersect() {
        let spans = [Span(lo: 0, hi: 10), Span(lo: 5, hi: 15)]
        #expect(Analysis.intersection(spans) == Span(lo: 5, hi: 10))
    }

    @Test("a single span intersects with itself")
    func singleSpanIntersectsWithItself() {
        let span = Span(lo: 3, hi: 7)
        #expect(Analysis.intersection([span]) == span)
    }

    @Test("touching spans intersect at the shared point (finding 8, P2)")
    func touchingSpansIntersect() {
        let spans = [Span(lo: 0, hi: 5), Span(lo: 5, hi: 10)]
        // A mutant using `lo < hi` instead of `lo <= hi` would treat this as disjoint.
        #expect(Analysis.intersection(spans) == Span(lo: 5, hi: 5))
    }
}
