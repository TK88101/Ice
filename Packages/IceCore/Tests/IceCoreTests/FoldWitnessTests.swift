import Testing
@testable import IceCore

/// The fold witness. Every refusal here is a way the 2026-09-18 runs could have
/// been read wrongly: Accessibility lagging the pixels, a privacy pill counted
/// as a chevron, an empty read taken for an empty bar.
@Suite("FoldWitness")
struct FoldWitnessTests {
    let params = DetectorParameters.preRegistered
    let ink = Ink(colours: [ColorMatch(center: Paint.white, tolerance: 70)])
    /// The fold region: from the notch's right edge to the leftmost reference.
    let region = PtSpan(lo: 40, hi: 120)

    var geometry: BarGeometry { Canvas().geometry() }

    /// Stand-ins for the system items every recorded baseline shows.
    var systemItems: [AgentFrame] {
        [
            AgentFrame(minX: 140, minY: 0, width: 26),
            AgentFrame(minX: 170, minY: 0, width: 22),
            AgentFrame(minX: 196, minY: 0, width: 26),
        ]
    }

    var chevron: AgentFrame { AgentFrame(minX: 100, minY: 0, width: 17.5) }

    func map(_ build: (inout Canvas) -> Void = { _ in }) -> InkMap {
        var canvas = Canvas()
        build(&canvas)
        return ink.map(canvas.image)
    }

    func sample(
        time: Double,
        frames: [AgentFrame],
        referencesStable: Bool = true,
        explained: [PtSpan] = [],
        before: InkMap? = nil,
        after: InkMap? = nil
    ) -> FoldSample {
        let blank = map()
        return FoldSample(
            time: time,
            before: before ?? blank,
            after: after ?? blank,
            agentFrames: frames,
            referencesStable: referencesStable,
            explained: explained
        )
    }

    func fold(_ samples: [FoldSample], baseline: [AgentFrame]? = nil) -> Fold {
        FoldWitness.derive(samples: samples, baselineFrames: baseline ?? systemItems, region: region, geometry: geometry, parameters: params)
    }

    // MARK: - The two answers it may give

    @Test("a 17.5 pt item with ink in its span, twice, is the fold")
    func chevronIsPresent() {
        let drawn = map { $0.draw(.flag, atPt: 101) }
        let samples = (0..<2).map {
            sample(time: Double($0) * 0.4, frames: systemItems + [chevron], before: drawn, after: drawn)
        }
        #expect(fold(samples) == .present)
    }

    @Test("no candidate and no unexplained ink in the region is no fold")
    func noChevronIsAbsent() {
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: systemItems) }
        #expect(fold(samples) == .absent)
    }

    @Test("ink a template accounts for does not stand in the way of absence")
    func explainedInkStillAbsent() {
        let drawn = map { $0.draw(.flag, atPt: 60) }
        let samples = (0..<2).map {
            sample(time: Double($0) * 0.4, frames: systemItems, explained: [PtSpan(lo: 59, hi: 66)], before: drawn, after: drawn)
        }
        #expect(fold(samples) == .absent)
    }

    @Test("the chevron, the pill and the agent set are one rule, shared with the harnesses")
    func sharedAgentRules() {
        #expect(FoldWitness.isChevron(chevron, parameters: params))
        #expect(!FoldWitness.isChevron(AgentFrame(minX: 60, minY: 0, width: 16), parameters: params))
        #expect(FoldWitness.isPill(AgentFrame(minX: 60, minY: 0, width: 16), parameters: params))
        #expect(!FoldWitness.isPill(chevron, parameters: params))
        #expect(FoldWitness.agentSetMatches(current: systemItems + [chevron], baseline: systemItems, parameters: params))
        let moved = systemItems.map { AgentFrame(minX: $0.minX + 3, minY: $0.minY, width: $0.width) }
        #expect(!FoldWitness.agentSetMatches(current: moved, baseline: systemItems, parameters: params))
    }

    // MARK: - Refusals

    @Test("a listed system item accounts for its own ink in the region")
    func listedAgentItemExplainsItsOwnInk() {
        // Capturing the bar summons a ≈ 20 pt MenuBarAgent indicator left of
        // the third-party items (2026-09-19). It draws, it is listed, and it
        // must not read as a chevron hiding behind Accessibility's back.
        let indicator = AgentFrame(minX: 58, minY: 0, width: 20)
        let drawn = map { $0.draw(.flag, atPt: 60) }
        let samples = (0..<2).map {
            sample(time: Double($0) * 0.4, frames: systemItems + [indicator], before: drawn, after: drawn)
        }
        #expect(fold(samples, baseline: systemItems + [indicator]) == .absent)
    }

    @Test("ink in the region that nothing accounts for refuses absence")
    func unexplainedInkRefuses() {
        // A chevron drawn before Accessibility lists it.
        let drawn = map { $0.draw(.flag, atPt: 60) }
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: systemItems, before: drawn, after: drawn) }
        #expect(fold(samples) == .unreadable)
    }

    @Test("an ink speck under the cluster minimum is not mistaken for a chevron")
    func tinyInkIsNotACluster() {
        let speck = map { canvas in
            for x in 120..<127 { canvas.set(x: x, y: 10, Paint.white) } // 7 px, under 16
        }
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: systemItems, before: speck, after: speck) }
        #expect(fold(samples) == .absent)
    }

    @Test("a candidate with no ink drawn in its span is unreadable, not present")
    func candidateWithoutInkRefuses() {
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: systemItems + [chevron]) }
        #expect(fold(samples) == .unreadable)
    }

    @Test("an empty Accessibility read is unreadable: MenuBarAgent always owns items")
    func emptyReadRefuses() {
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: []) }
        #expect(fold(samples) == .unreadable)
    }

    @Test("a pill arriving mid-action is unreadable, whatever its width")
    func arrivingPillRefuses() {
        // The microphone pill: Accessibility frame 16 pt wide, in two recorded
        // baselines.
        let pill = AgentFrame(minX: 60, minY: 0, width: 16)
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: systemItems + [pill]) }
        #expect(fold(samples) == .unreadable)
    }

    @Test("a pill already there at the baseline, unchanged, does not block a verdict")
    func pillPresentThroughout() {
        let pill = AgentFrame(minX: 60, minY: 0, width: 16)
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: systemItems + [pill]) }
        #expect(fold(samples, baseline: systemItems + [pill]) == .absent)
    }

    @Test("a system item that moved three points is unreadable")
    func movedSystemItemRefuses() {
        // The clock's Accessibility x went 1592 -> 1589 after the first capture
        // on 2026-09-19, which is why it is never a reference.
        let moved = systemItems.map { AgentFrame(minX: $0.minX - 3, minY: $0.minY, width: $0.width) }
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: moved) }
        #expect(fold(samples) == .unreadable)
    }

    @Test("an item replaced by another of the same width is unreadable")
    func equalWidthSwapRefuses() {
        var swapped = systemItems
        swapped[1] = AgentFrame(minX: 176, minY: 0, width: 22)
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: swapped) }
        #expect(fold(samples) == .unreadable)
    }

    @Test("two chevron-sized candidates are unreadable")
    func twoCandidatesRefuse() {
        let second = AgentFrame(minX: 60, minY: 0, width: 17.5)
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: systemItems + [chevron, second]) }
        #expect(fold(samples) == .unreadable)
    }

    @Test("references that moved during a sample make it unreadable")
    func unstableReferencesRefuse() {
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: systemItems, referencesStable: false) }
        #expect(fold(samples) == .unreadable)
    }

    @Test("a fold region that changed between the two captures is unreadable")
    func regionChangedBetweenBracketsRefuses() {
        let before = map()
        let after = map { $0.draw(.box, atPt: 60) }
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: systemItems, before: before, after: after) }
        #expect(fold(samples) == .unreadable)
    }

    @Test("one sample is never enough")
    func oneSampleRefuses() {
        #expect(fold([sample(time: 0, frames: systemItems)]) == .unreadable)
    }

    @Test("samples taken too close together are unreadable")
    func samplesTooCloseRefuse() {
        let samples = [sample(time: 0, frames: systemItems), sample(time: 0.1, frames: systemItems)]
        #expect(fold(samples) == .unreadable)
    }

    @Test("samples that disagree are unreadable")
    func disagreeingSamplesRefuse() {
        let drawn = map { $0.draw(.flag, atPt: 101) }
        let withChevron = sample(time: 0, frames: systemItems + [chevron], before: drawn, after: drawn)
        let without = sample(time: 0.4, frames: systemItems)
        #expect(fold([withChevron, without]) == .unreadable)
    }

    @Test("an agent item below the bar is ignored, not counted as a chevron")
    func parkedAgentItemIgnored() {
        let parked = AgentFrame(minX: 7, minY: 1104, width: 17.5)
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: systemItems + [parked]) }
        #expect(fold(samples) == .absent)
    }

    @Test("at the baseline there is nothing to compare frames against, and the rest still applies")
    func baselineWithoutPriorFrames() {
        let samples = (0..<2).map { sample(time: Double($0) * 0.4, frames: systemItems) }
        #expect(FoldWitness.derive(samples: samples, baselineFrames: nil, region: region, geometry: geometry, parameters: params) == .absent)
        let drawn = map { $0.draw(.flag, atPt: 101) }
        let raised = (0..<2).map { sample(time: Double($0) * 0.4, frames: systemItems + [chevron], before: drawn, after: drawn) }
        #expect(FoldWitness.derive(samples: raised, baselineFrames: nil, region: region, geometry: geometry, parameters: params) == .present)
    }
}
