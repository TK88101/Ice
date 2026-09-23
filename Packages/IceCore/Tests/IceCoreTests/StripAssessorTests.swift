import Testing
@testable import IceCore

/// The whole chain on synthetic pixels: a baseline, then observations, then the
/// decision layer's verdicts. Nothing here knows about screens or Accessibility
/// APIs — the adapter hands these values in.
@Suite("StripAssessor")
struct StripAssessorTests {
    let params = DetectorParameters.preRegistered
    let detector = MenuBarItemVisibility(maxMismatch: DetectorParameters.preRegistered.maxMismatch)

    /// A bar with the target at 60 pt and the reference at 150 pt. The system
    /// items sit to the right of both, as they do on a real bar.
    func canvas(targetDrawn: Bool = true, backdrop: RGBA = Paint.darkBar) -> Canvas {
        var canvas = Canvas(backdrop: backdrop)
        if targetDrawn { canvas.draw(.flag, atPt: 60) }
        canvas.draw(.box, atPt: 150)
        return canvas
    }

    var geometry: BarGeometry { Canvas().geometry(notch: PtSpan(lo: 20, hi: 40)) }

    var systemItems: [AgentFrame] {
        [AgentFrame(minX: 170, minY: 0, width: 26), AgentFrame(minX: 190, minY: 0, width: 8)]
    }

    func frames(includeTarget: Bool = true, targetX: Double = 59) -> [String: ItemFrame] {
        var frames = ["reference": ItemFrame(id: "reference", minX: 149, minY: 0, width: 7, height: 12)]
        if includeTarget {
            frames["target"] = ItemFrame(id: "target", minX: targetX, minY: 0, width: 7, height: 12)
        }
        return frames
    }

    func samples(_ canvases: [Canvas], spacing: Double = 1, itemFrames: [String: ItemFrame]? = nil, agentFrames: [AgentFrame]? = nil) -> [ObservationSample] {
        canvases.enumerated().map { index, canvas in
            ObservationSample(
                time: Double(index) * spacing,
                before: canvas.image,
                after: canvas.image,
                agentFrames: agentFrames ?? systemItems,
                itemFrames: itemFrames ?? frames()
            )
        }
    }

    func baseline(_ canvases: [Canvas]? = nil, itemFrames: [String: ItemFrame]? = nil) -> BaselineResult {
        let list = canvases ?? Array(repeating: canvas(), count: 4)
        return StripAssessor.baseline(samples: samples(list, itemFrames: itemFrames), geometry: geometry, parameters: params)
    }

    func observe(_ baseline: BaselineResult, _ canvases: [Canvas], spacing: Double = 0.4, itemFrames: [String: ItemFrame]? = nil, agentFrames: [AgentFrame]? = nil) -> StripReading {
        StripAssessor.observe(
            baseline: baseline,
            targets: ["target"],
            references: ["reference"],
            samples: samples(canvases, spacing: spacing, itemFrames: itemFrames, agentFrames: agentFrames),
            parameters: params
        )
    }

    // MARK: - The baseline

    @Test("a settled baseline accepts both items and finds no fold")
    func baselineAcceptsItems() {
        let result = baseline()
        #expect(result.acceptedIDs == ["reference", "target"])
        #expect(result.foldAtBaseline == .absent)
        #expect(result.rejections.isEmpty)
    }

    @Test("a baseline that is too short accepts nothing")
    func shortBaselineRejects() {
        let result = StripAssessor.baseline(samples: samples(Array(repeating: canvas(), count: 2)), geometry: geometry, parameters: params)
        #expect(result.templates.isEmpty)
        #expect(result.rejections["target"] == .baselineTooShort)
    }

    @Test("an item whose frame moves between reads is rejected, not averaged")
    func disagreeingReadsRejected() {
        var list = samples(Array(repeating: canvas(), count: 4))
        list[2] = ObservationSample(
            time: list[2].time,
            before: list[2].before,
            after: list[2].after,
            agentFrames: systemItems,
            itemFrames: frames(targetX: 65)
        )
        let result = StripAssessor.baseline(samples: list, geometry: geometry, parameters: params)
        #expect(result.rejections["target"] == .readsDisagree)
        #expect(result.templates["reference"] != nil)
    }

    @Test("an item that changes during the baseline is kept, but marked dynamic")
    func changingItemIsDynamic() {
        var list = Array(repeating: canvas(), count: 4)
        list[3].draw(.box, atPt: 60) // the target redrew itself
        let result = baseline(list)
        #expect(result.templates["target"]?.isDynamic == true)
        #expect(result.templates["reference"]?.isDynamic == false)
    }

    @Test("a baseline taken with the fold up accepts nothing")
    func foldUpAtBaselineRejects() {
        let chevron = AgentFrame(minX: 45, minY: 0, width: 17.5)
        var list = Array(repeating: canvas(), count: 4)
        for index in list.indices { list[index].draw(.box, atPt: 46) }
        let result = StripAssessor.baseline(
            samples: samples(list, agentFrames: systemItems + [chevron]),
            geometry: geometry,
            parameters: params
        )
        #expect(result.foldAtBaseline == .present)
        #expect(result.rejections["target"] == .foldNotAbsentAtBaseline)
        #expect(result.templates.isEmpty)
    }

    // MARK: - Hiding and restoring

    @Test("drawn, then hidden without a fold, then restored")
    func hideAndRestore() throws {
        let base = baseline()
        let present = Array(repeating: canvas(), count: 2)
        let gone = Array(repeating: canvas(targetDrawn: false), count: 2)

        let before = observe(base, present)
        #expect(before.captureStable)
        let sighting = try #require(before.sightings.first { $0.id == "target" })
        #expect(detector.verdict(for: sighting, captureStable: before.captureStable) == .drawn(x: 59))

        let hidden = observe(base, gone, itemFrames: frames(includeTarget: false))
        #expect(detector.hiding(of: "target", in: hidden) == .hidden(folded: false))

        let back = observe(base, present)
        #expect(detector.restoration(of: "target", in: back) == .restored(x: 59))
    }

    @Test("an item the baseline rejected is never reported as hidden")
    func rejectedItemIsNotObserved() {
        // The target was not drawn when the baseline was taken, so it has no
        // template. Its later absence proves nothing about hiding.
        let base = baseline(Array(repeating: canvas(targetDrawn: false), count: 4))
        #expect(base.rejections["target"] == .noInk)
        #expect(base.templates["reference"] != nil)
        let reading = observe(base, Array(repeating: canvas(targetDrawn: false), count: 2))
        #expect(reading.captureStable)
        #expect(detector.hiding(of: "target", in: reading) == .unverifiable(.notObserved))
    }

    @Test("a target that says different things in two samples is unstable")
    func unsettledTargetIsUnstable() {
        let base = baseline()
        let reading = observe(base, [canvas(), canvas(targetDrawn: false)])
        #expect(!reading.captureStable)
        #expect(detector.hiding(of: "target", in: reading) == .unverifiable(.captureUnstable))
    }

    @Test("a reference that moved makes the whole reading unverifiable")
    func movedReferenceIsUnstable() {
        let base = baseline()
        var moved = Canvas()
        moved.draw(.flag, atPt: 60)
        moved.draw(.box, atPt: 156) // the reference slid
        let reading = observe(base, [moved, moved])
        #expect(!reading.captureStable)
    }

    @Test("a changed backdrop under everything still reads as drawn")
    func backdropChangeSurvives() {
        let base = baseline()
        let reading = observe(base, Array(repeating: canvas(backdrop: Paint.redBar), count: 2))
        #expect(reading.captureStable)
        #expect(detector.hiding(of: "target", in: reading) == .stillDrawn)
    }

    @Test("samples too close together decide nothing")
    func samplesTooCloseRefuse() {
        let base = baseline()
        let reading = observe(base, Array(repeating: canvas(), count: 2), spacing: 0.1)
        #expect(!reading.captureStable)
        #expect(reading.fold == .unreadable)
    }

    @Test("a glyph found far from the item's own frame is vetoed, not reported as restored")
    func placementVetoInTheChain() {
        let base = baseline()
        var elsewhere = Canvas()
        elsewhere.draw(.flag, atPt: 100)
        elsewhere.draw(.box, atPt: 150)
        let reading = observe(base, [elsewhere, elsewhere])
        let sighting = reading.sightings.first { $0.id == "target" }
        #expect(sighting?.placement == .inconsistent)
        #expect(detector.restoration(of: "target", in: reading) == .unverifiable(.contradictsAccessibility))
    }
}
