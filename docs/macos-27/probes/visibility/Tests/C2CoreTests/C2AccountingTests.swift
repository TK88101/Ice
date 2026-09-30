// T1 (docs/plans/2026-09-28-c2-protocol.md section 1, 6.2): retries, the two
// sittings' verdicts, and the stop-at-first-failure rule.
import C2Core
import Testing

@Suite("C2Accounting")
struct C2AccountingTests {
    // MARK: - retries (6.2: an inconclusive repeat is re-run at most twice)

    @Test("the first decisive attempt settles; inconclusive attempts before it are retried")
    func retrySettles() {
        #expect(C2Retry.settle([]) == nil)
        #expect(C2Retry.settle([.inconclusive]) == nil)
        #expect(C2Retry.settle([.inconclusive, .inconclusive]) == nil)
        #expect(C2Retry.settle([.inconclusive, .pass]) == .pass)
        #expect(C2Retry.settle([.fail]) == .fail)
        #expect(C2Retry.settle([.inconclusive, .inconclusive, .inconclusive]) == .notShown)
    }

    // MARK: - sitting A (brackets)

    @Test("every configuration bracketed with a wide enough intersection -> the length")
    func sittingAPicksLength() {
        let verdict = C2Accounting.sittingA([
            .init(configuration: "k1-short", outcome: .bracketed(C2Span(lo: 600, hi: 840))),
            .init(configuration: "k2-short", outcome: .bracketed(C2Span(lo: 640, hi: 800))),
        ])
        #expect(verdict == .length(720, intersection: C2Span(lo: 640, hi: 800)))
    }

    @Test("a configuration without a band -> provisional fail naming it, even if later ones exist")
    func sittingANoBand() {
        let verdict = C2Accounting.sittingA([
            .init(configuration: "k1-short", outcome: .bracketed(C2Span(lo: 600, hi: 840))),
            .init(configuration: "k2-short", outcome: .noBand),
            .init(configuration: "k3-short", outcome: .safetyStop),
        ])
        #expect(verdict == .provisionalFail(configuration: "k2-short", reason: "no band"))
    }

    @Test("a not-shown configuration -> provisional fail with its reason")
    func sittingANotShown() {
        let verdict = C2Accounting.sittingA([.init(configuration: "k1-long", outcome: .notShown("fold unreadable at baseline"))])
        #expect(verdict == .provisionalFail(configuration: "k1-long", reason: "not shown: fold unreadable at baseline"))
    }

    @Test("a safety stop is terminal and wins over nothing before it")
    func sittingASafetyStop() {
        let verdict = C2Accounting.sittingA([
            .init(configuration: "k1-short", outcome: .bracketed(C2Span(lo: 600, hi: 840))),
            .init(configuration: "k2-short", outcome: .safetyStop),
        ])
        #expect(verdict == .safetyStop(configuration: "k2-short"))
    }

    @Test("an intersection narrower than 32 pt, or empty, or no configuration at all -> provisional fail")
    func sittingANarrowOrEmpty() {
        let narrow = C2Accounting.sittingA([
            .init(configuration: "a", outcome: .bracketed(C2Span(lo: 600, hi: 700))),
            .init(configuration: "b", outcome: .bracketed(C2Span(lo: 680, hi: 800))),
        ])
        #expect(narrow == .provisionalFail(configuration: nil, reason: "intersection 680-700 narrower than 32 pt"))
        let empty = C2Accounting.sittingA([
            .init(configuration: "a", outcome: .bracketed(C2Span(lo: 600, hi: 650))),
            .init(configuration: "b", outcome: .bracketed(C2Span(lo: 700, hi: 800))),
        ])
        #expect(empty == .provisionalFail(configuration: nil, reason: "empty intersection"))
        #expect(C2Accounting.sittingA([]) == .provisionalFail(configuration: nil, reason: "no configuration ran"))
    }

    // MARK: - sitting B (collar + baseline)

    @Test("every collar point and every baseline cycle passes in every configuration -> pass")
    func sittingBPass() {
        let all = Array(repeating: C2Settled.pass, count: C2Accounting.cyclesPerConfigurationInSittingB)
        #expect(C2Accounting.sittingB([.init(configuration: "a", outcome: .completed(all)), .init(configuration: "b", outcome: .completed(all))]) == .pass)
    }

    @Test("one failed or not-shown cycle -> provisional fail naming the configuration")
    func sittingBFail() {
        var cycles = Array(repeating: C2Settled.pass, count: C2Accounting.cyclesPerConfigurationInSittingB)
        cycles[3] = .fail
        #expect(C2Accounting.sittingB([.init(configuration: "a", outcome: .completed(cycles))]) == .provisionalFail(configuration: "a", reason: "a collar or baseline cycle failed"))
        cycles[3] = .notShown
        #expect(C2Accounting.sittingB([.init(configuration: "a", outcome: .completed(cycles))]) == .provisionalFail(configuration: "a", reason: "a collar or baseline cycle not shown"))
    }

    @Test("a short run, a safety stop, or no configuration at all")
    func sittingBOtherPaths() {
        #expect(C2Accounting.sittingB([.init(configuration: "a", outcome: .completed([.pass]))]) == .provisionalFail(configuration: "a", reason: "ended after 1 of 14 cycles"))
        #expect(C2Accounting.sittingB([.init(configuration: "a", outcome: .safetyStop)]) == .safetyStop(configuration: "a"))
        #expect(C2Accounting.sittingB([]) == .provisionalFail(configuration: nil, reason: "no configuration ran"))
    }

    // MARK: - early stop

    @Test("the runner continues only after a bracketed or fully passing configuration")
    func continueRule() {
        #expect(C2Accounting.shouldContinue(afterA: .bracketed(C2Span(lo: 1, hi: 2))))
        #expect(!C2Accounting.shouldContinue(afterA: .noBand))
        #expect(!C2Accounting.shouldContinue(afterA: .notShown("x")))
        #expect(!C2Accounting.shouldContinue(afterA: .safetyStop))
        let all = Array(repeating: C2Settled.pass, count: C2Accounting.cyclesPerConfigurationInSittingB)
        #expect(C2Accounting.shouldContinue(afterB: .completed(all)))
        #expect(!C2Accounting.shouldContinue(afterB: .completed([.pass])))
        #expect(!C2Accounting.shouldContinue(afterB: .safetyStop))
    }
}

@Suite("C2PointRetry")
struct C2PointRetryTests {
    @Test("a point settles on its first reading; nil attempts (inconclusive) retry up to three, then notShown")
    func settleReading() {
        #expect(C2Retry.settleReading([]) == nil)
        #expect(C2Retry.settleReading([nil]) == nil)
        #expect(C2Retry.settleReading([nil, nil]) == nil)
        #expect(C2Retry.settleReading([nil, .stillDrawn]) == .stillDrawn)
        #expect(C2Retry.settleReading([.hiddenNoFold]) == .hiddenNoFold)
        #expect(C2Retry.settleReading([nil, nil, nil]) == .notShown)
    }

    @Test("sitting B: only hiddenNoFold passes; notShown stays notShown; anything else fails")
    func settledFromReading() {
        #expect(C2Settled(reading: .hiddenNoFold) == .pass)
        #expect(C2Settled(reading: .notShown) == .notShown)
        #expect(C2Settled(reading: .hiddenFolded) == .fail)
        #expect(C2Settled(reading: .stillDrawn) == .fail)
    }
}
