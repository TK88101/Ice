import Testing
@testable import IceCore

/// The hidden-length calibrator (plan 2026-10-03-icebar-build, D1 and section
/// 8). The T0 band, 632-840 pt on a 16 pt grid from 408, is the world most of
/// these tests walk; every give-up is a way Ice would otherwise hide items it
/// has not seen hidden cleanly.
@Suite("HiddenLengthCalibrator")
struct HiddenLengthCalibratorTests {
    /// The outcome T0 measured at each length: folded below the band, clean
    /// inside it, drawn above it.
    func t0World(_ length: Double) -> HiddenLengthOutcome {
        if length < 632 { return .folded }
        if length > 840 { return .drawn }
        return .hiddenClean
    }

    func next(_ observations: [HiddenLengthObservation], lastGood: Double? = nil, parameters: HiddenLengthParameters = .standard) -> HiddenLengthProposal {
        HiddenLengthCalibrator.next(observations: observations, lastGood: lastGood, parameters: parameters)
    }

    /// For fractional steps, where the rest length is not exact.
    func expectRest(_ proposal: HiddenLengthProposal, near expected: Double) {
        guard case .rest(let length) = proposal else {
            Issue.record("expected rest, got \(proposal)")
            return
        }
        #expect(abs(length - expected) < 1e-9)
    }

    func obs(_ length: Double, _ outcome: HiddenLengthOutcome) -> HiddenLengthObservation {
        HiddenLengthObservation(length: length, outcome: outcome)
    }

    /// Follows the calibrator's proposals against a world until it rests or
    /// gives up, returning the final proposal and the lengths it tried.
    func run(
        lastGood: Double? = nil,
        parameters: HiddenLengthParameters = .standard,
        world: (Double) -> HiddenLengthOutcome
    ) -> (HiddenLengthProposal, [Double]) {
        var observations = [HiddenLengthObservation]()
        var tried = [Double]()
        while true {
            let proposal = next(observations, lastGood: lastGood, parameters: parameters)
            guard case .tryLength(let length) = proposal else { return (proposal, tried) }
            tried.append(length)
            observations.append(obs(length, world(length)))
            if tried.count > 100 { return (proposal, tried) }
        }
    }

    // MARK: - Where it starts

    @Test("with nothing observed it tries the default start, T0's midpoint")
    func firstProposalIsDefaultStart() {
        #expect(next([]) == .tryLength(736))
    }

    @Test("a valid last good length is where it starts again")
    func restartsFromLastGood() {
        #expect(next([], lastGood: 704) == .tryLength(704))
    }

    @Test("a non-finite or out-of-range last good falls back to the default", arguments: [Double.nan, .infinity, 100, 2000])
    func invalidLastGoodFallsBack(lastGood: Double) {
        #expect(next([], lastGood: lastGood) == .tryLength(736))
    }

    // MARK: - Walking the T0 band

    /// The grid is anchored at 736, 8 pt off T0's 408 + 16n, so the edges
    /// found are 624 (folded) and 848 (drawn).
    @Test("a clean start walks down, then up, and rests at the band's midpoint")
    func cleanStartRestsAtMidpoint() throws {
        let (proposal, tried) = run(world: t0World)
        #expect(proposal == .rest(736))
        #expect(tried.first == 736)
        let down = try #require(tried.firstIndex(of: 624))
        let up = try #require(tried.firstIndex(of: 848))
        #expect(down < up)
    }

    @Test("a folded start walks up into the band and rests at its midpoint")
    func foldedStartWalksUp() {
        let (proposal, tried) = run(lastGood: 520, world: t0World)
        #expect(proposal == .rest(736))
        #expect(Array(tried.prefix(3)) == [520, 536, 552])
    }

    @Test("a drawn start walks down into the band and rests at its midpoint")
    func drawnStartWalksDown() {
        let (proposal, tried) = run(lastGood: 936, world: t0World)
        #expect(proposal == .rest(736))
        #expect(Array(tried.prefix(3)) == [936, 920, 904])
    }

    @Test("a run reaching a limit is bracketed by the limit")
    func limitBracketsRun() {
        let (proposal, tried) = run(lastGood: 968, world: { $0 < 952 ? .folded : .hiddenClean })
        #expect(proposal == .rest((952 + 1000) / 2))
        #expect(!tried.contains { $0 > 1000 })
    }

    @Test("a one-length band rests on that length")
    func oneLengthBand() {
        let (proposal, _) = run(world: { $0 < 736 ? .folded : ($0 > 736 ? .drawn : .hiddenClean) })
        #expect(proposal == .rest(736))
    }

    // MARK: - Giving up (the section stays shown)

    @Test("unknown anywhere gives up at once")
    func unknownGivesUp() {
        #expect(next([obs(736, .hiddenClean), obs(720, .unknown)]) == .giveUp(.unknownOutcome))
        #expect(next([obs(736, .unknown)]) == .giveUp(.unknownOutcome))
    }

    @Test("an observation length that is non-finite or out of range gives up", arguments: [Double.nan, .infinity, -.infinity, 392, 1016])
    func invalidObservationLengthGivesUp(length: Double) {
        #expect(next([obs(736, .hiddenClean), obs(length, .hiddenClean)]) == .giveUp(.unknownOutcome))
    }

    @Test("folded below and drawn above with nothing clean between is no band")
    func foldedThenDrawnIsNoBand() {
        #expect(next([obs(736, .folded), obs(752, .drawn)]) == .giveUp(.noBand))
    }

    @Test("walking off a limit without a clean length is no band")
    func walkingOffLimitIsNoBand() {
        let (upward, _) = run(world: { _ in .folded })
        #expect(upward == .giveUp(.noBand))
        let (downward, _) = run(world: { _ in .drawn })
        #expect(downward == .giveUp(.noBand))
    }

    @Test("a non-clean length between clean ones is inconsistent")
    func nonCleanBetweenCleansIsInconsistent() {
        let observations = [obs(736, .hiddenClean), obs(752, .drawn), obs(768, .hiddenClean)]
        #expect(next(observations) == .giveUp(.inconsistent))
    }

    @Test("a missing interior grid point is tried, not assumed clean")
    func missingInteriorPointIsTried() {
        let observations = [obs(736, .hiddenClean), obs(768, .hiddenClean)]
        #expect(next(observations) == .tryLength(752))
    }

    @Test("an observation off the start's grid is inconsistent")
    func offGridIsInconsistent() {
        #expect(next([obs(736, .hiddenClean), obs(728, .hiddenClean)]) == .giveUp(.inconsistent))
    }

    @Test("reaching the observation bound without resting gives up")
    func stepBoundGivesUp() {
        let tight = HiddenLengthParameters(step: 16, minLength: 408, maxLength: 1000, defaultStart: 736, maxObservations: 4)
        let (proposal, tried) = run(parameters: tight, world: t0World)
        #expect(proposal == .giveUp(.stepBound))
        #expect(tried.count == 4)
    }

    // MARK: - Reading the history

    @Test("a repeated length keeps its latest outcome")
    func latestOutcomeWins() {
        let observations = [obs(736, .folded), obs(736, .hiddenClean)]
        #expect(next(observations) == .tryLength(720))
    }

    @Test("a fractional step rests at the exact midpoint, inside the run")
    func fractionalStepExactMidpoint() {
        let fine = HiddenLengthParameters(step: 0.3, minLength: 0, maxLength: 3, defaultStart: 0.3, maxObservations: 24)
        let world: (Double) -> HiddenLengthOutcome = { $0 < 0.29 ? .folded : ($0 > 0.61 ? .drawn : .hiddenClean) }
        let (proposal, _) = run(parameters: fine, world: world)
        expectRest(proposal, near: 0.45)
    }

    /// 0 + 3 * 0.1 is 0.30000000000000004: proposed as the upper limit, it
    /// must be accepted back, not refused as out of range.
    @Test("a grid point a rounding error past a limit is accepted back")
    func roundedLimitPointAccepted() {
        let fine = HiddenLengthParameters(step: 0.1, minLength: 0, maxLength: 0.3, defaultStart: 0, maxObservations: 24)
        let (proposal, tried) = run(parameters: fine, world: { _ in .hiddenClean })
        #expect(tried.count == 4)
        expectRest(proposal, near: 0.15)
    }
}
