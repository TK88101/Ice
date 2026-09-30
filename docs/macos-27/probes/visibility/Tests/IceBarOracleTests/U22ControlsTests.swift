// U22 (pre-registration section 7) and the chevron rule of section 5: positive
// and member controls, the edge rule at 3 / 4 visible on-px, `«` (a) and (b),
// and the per-attempt verdict.
@testable import IceBarOracle
import IceCore
import Testing

@Suite("U22 controls, chevron, attempt verdict")
struct U22ControlsTests {
    let y0 = 22

    func drawn(_ id: String, x: Double, _ matchClass: MatchClass = .full) -> CaptureLabels {
        CaptureLabels(labels: [id: .drawn(matchClass, xPt: x, zone: .rightOfReferences)], matches: [:], sightings: [], inconclusive: [], chevron: .absent)
    }

    // Positive controls: within 2 pt of AX minX + 1.5 pt.
    @Test("a visible helper drawn(full) within 2 pt of AX minX + 1.5 is no miss", arguments: [1351.5, 1353.5, 1349.5])
    func positiveHit(x: Double) {
        let misses = Controls.positiveMisses(drawn("v1", x: x), visible: [VisibleHelper(id: "v1", axMinX: 1350)])
        #expect(misses.isEmpty)
    }

    @Test("a visible helper off by more than 2 pt, not full, or not found is a miss")
    func positiveMiss() {
        let visible = [VisibleHelper(id: "v1", axMinX: 1350)]
        #expect(Controls.positiveMisses(drawn("v1", x: 1353.6), visible: visible) == ["v1"])
        #expect(Controls.positiveMisses(drawn("v1", x: 1351.5, .partial), visible: visible) == ["v1"])
        let none = CaptureLabels(labels: ["v1": .none], matches: [:], sightings: [], inconclusive: [], chevron: .absent)
        #expect(Controls.positiveMisses(none, visible: visible) == ["v1"])
    }

    @Test("a visible helper not found makes the attempt inconclusive")
    func attemptInconclusiveOnControlMiss() {
        let ok = drawn("v1", x: 1351.5)
        let missed = CaptureLabels(labels: ["v1": .none], matches: [:], sightings: [], inconclusive: [], chevron: .absent)
        let visible = [VisibleHelper(id: "v1", axMinX: 1350)]
        let good = AttemptVerdict.evaluate(captures: [ok, ok], reads: [], barHeightPt: 32, members: [], visible: visible, overlap: .clear)
        #expect(!good.inconclusive)
        let bad = AttemptVerdict.evaluate(captures: [ok, missed], reads: [], barHeightPt: 32, members: [], visible: visible, overlap: .clear)
        #expect(bad.inconclusive)
        #expect(bad.controlMisses == ["v1"])
    }

    @Test("a member not drawn(full) at a rest control makes the cycle inconclusive")
    func memberControl() {
        let both = CaptureLabels(labels: ["m1": .drawn(.full, xPt: 1100, zone: .region), "m2": .drawn(.full, xPt: 1120, zone: .region)],
                                 matches: [:], sightings: [], inconclusive: [], chevron: .absent)
        let one = CaptureLabels(labels: ["m1": .drawn(.full, xPt: 1100, zone: .region), "m2": .drawn(.partial, xPt: 1120, zone: .region)],
                                matches: [:], sightings: [], inconclusive: [], chevron: .absent)
        #expect(!Controls.cycleInconclusive(restCaptures: [both, both], members: ["m1", "m2"]))
        #expect(Controls.cycleInconclusive(restCaptures: [both, one], members: ["m1", "m2"]))
        #expect(Controls.memberMisses(one, members: ["m1", "m2"]) == ["m2"])
    }

    // The edge rule at 3 and 4 visible on-px (S13): the bracket's column 16
    // holds 4 on-px; without its top-row pixel it holds 3.
    @Test("edge rule: 3 visible on-px is none, 4 is drawn(edge)", arguments: [(3, false), (4, true)])
    func edgeThreeFour(count: Int, found: Bool) throws {
        var alpha = Shapes.bracket()
        if count == 3 { alpha[2 * 20 + 16] = 0 }
        let template = OracleTemplate(id: "a", width: 20, height: 20, alpha: alpha, scale: 2)
        var canvas = Canvas()
        canvas.stamp(alpha, side: 20, at: 1897, y0)
        canvas.fillColumns(1543..<1913, (0, 0, 0))
        let labels = try Oracle.label(image: canvas.image, helpers: [template], chevron: nil, context: .corpus())
        #expect(labels.labels["a"] == HelperLabel.none)
        let sighted = labels.sightings.contains { $0.xPx == 1897 && $0.matchClass == .edge && !$0.explained }
        #expect(sighted == found)
        if !found { #expect(labels.sightings.isEmpty) }
    }

    // `«` (a): an on-bar MenuBarAgent frame 17.5 +- 0.5 pt wide.
    @Test("chevron (a): width 17.0, 17.5, 18.0 on the bar is present", arguments: [17.0, 17.5, 18.0])
    func chevronAXPresent(width: Double) {
        #expect(ChevronRule.fromAX(reads: [[AgentFrame(minX: 976.5, minY: 0, width: width)]], barHeightPt: 32))
    }

    @Test("chevron (a): 16.9 or 18.1 wide, or off the bar, is absent")
    func chevronAXAbsent() {
        #expect(!ChevronRule.fromAX(reads: [[AgentFrame(minX: 976.5, minY: 0, width: 16.9)]], barHeightPt: 32))
        #expect(!ChevronRule.fromAX(reads: [[AgentFrame(minX: 976.5, minY: 0, width: 18.1)]], barHeightPt: 32))
        #expect(!ChevronRule.fromAX(reads: [[AgentFrame(minX: 976.5, minY: 32, width: 17.5)]], barHeightPt: 32))
        #expect(!ChevronRule.fromAX(reads: [[AgentFrame(minX: 976.5, minY: -1, width: 17.5)]], barHeightPt: 32))
        #expect(!ChevronRule.fromAX(reads: [], barHeightPt: 32))
    }

    /// A K1-like capture: red textured bar, a white "<<" in the AX frame's columns.
    func chevronCapture(scale: Double = 2, chevronAtPx x0: Int = 1956) -> (Canvas, [(Int, Int)]) {
        var canvas = Canvas(widthPt: 1728, heightPt: 33, scale: scale, backdrop: (130, 40, 40))
        for x in stride(from: 0, to: canvas.width, by: 7) {
            for y in 0..<canvas.height { canvas.set(x, y, (150, 55, 55)) }
        }
        var ink = [(Int, Int)]()
        for k in 0..<10 {
            for (dx, dy) in [(10 - k, 23 + k), (10 - k, 43 - k), (22 - k, 23 + k), (22 - k, 43 - k)] {
                for t in 0..<2 { ink.append((x0 + dx + t, dy)) }
            }
        }
        for (x, y) in ink { canvas.set(x, y, (250, 250, 250)) }
        return (canvas, ink)
    }

    // D16: the cut keeps the white chevron as P, zeroes the texture, crops
    // to the ink plus 2 px.
    @Test("chevron template cut: P is the white ink, the texture is Q, cropped with a 2 px margin")
    func chevronCut() throws {
        let (canvas, ink) = chevronCapture()
        let template = try ChevronTemplate.cut(from: canvas.image, framePt: PtSpan(lo: 976.5, hi: 994))
        let xs = ink.map(\.0)
        let ys = ink.map(\.1)
        #expect(template.width == xs.max()! - xs.min()! + 1 + 4)
        #expect(template.height == ys.max()! - ys.min()! + 1 + 4)
        #expect(template.onCount == Set(ink.map { "\($0.0),\($0.1)" }).count)
        #expect(template.onCount + template.offCount == template.width * template.height)
        #expect(template.scale == 2)
    }

    @Test("chevron (b): the K1 template finds the chevron at scale 2 and is not evaluable at scale 1")
    func chevronPixels() throws {
        let (source, _) = chevronCapture()
        let template = try ChevronTemplate.cut(from: source.image, framePt: PtSpan(lo: 976.5, hi: 994))
        let (moved, _) = chevronCapture(chevronAtPx: 2300)
        let context = OracleContext(notch: PtSpan(lo: 771.5, hi: 956.5), agentFrames: [], leftmostReferenceOriginPt: nil)
        #expect(try Oracle.label(image: moved.image, helpers: [], chevron: template, context: context).chevron == .present)
        let empty = Canvas(widthPt: 1728, heightPt: 33, scale: 2, backdrop: (130, 40, 40))
        #expect(try Oracle.label(image: empty.image, helpers: [], chevron: template, context: context).chevron == .absent)
        let oneX = Canvas(widthPt: 1728, heightPt: 33, scale: 1)
        #expect(try Oracle.label(image: oneX.image, helpers: [], chevron: template, context: context).chevron == .notEvaluable)
    }

    @Test("a cut with no ink in the frame is refused")
    func chevronCutEmpty() {
        let empty = Canvas(widthPt: 1728, heightPt: 33, scale: 2, backdrop: (130, 40, 40))
        #expect(throws: OracleError.emptyChevronCut) {
            try ChevronTemplate.cut(from: empty.image, framePt: PtSpan(lo: 976.5, hi: 994))
        }
    }

    // Verdict per attempt: any capture, any read.
    @Test("the attempt sees a member identified in any capture, or any unexplained sighting")
    func seesMember() {
        let clean = CaptureLabels(labels: ["m1": .none], matches: [:], sightings: [], inconclusive: [], chevron: .absent)
        let edge = CaptureLabels(labels: ["m1": .none], matches: [:],
                                 sightings: [Sighting(templateID: "zz", xPx: 1910, yPx: 22, width: 24, matchClass: .edge, explained: false)],
                                 inconclusive: [], chevron: .absent)
        let explained = CaptureLabels(labels: ["m1": .none], matches: [:],
                                      sightings: [Sighting(templateID: "zz", xPx: 1910, yPx: 22, width: 24, matchClass: .edge, explained: true)],
                                      inconclusive: [], chevron: .absent)
        #expect(!AttemptVerdict.evaluate(captures: [explained], reads: [], barHeightPt: 32, members: ["m1"], visible: [], overlap: .clear).seesMember)
        #expect(!AttemptVerdict.evaluate(captures: [clean, clean], reads: [], barHeightPt: 32, members: ["m1"], visible: [], overlap: .clear).seesMember)
        #expect(AttemptVerdict.evaluate(captures: [clean, edge], reads: [], barHeightPt: 32, members: ["m1"], visible: [], overlap: .clear).seesMember)
    }

    @Test("the attempt sees `«` from any read (a) or any capture (b)")
    func seesChevron() {
        let clean = CaptureLabels(labels: [:], matches: [:], sightings: [], inconclusive: [], chevron: .absent)
        let pixels = CaptureLabels(labels: [:], matches: [:], sightings: [], inconclusive: [], chevron: .present)
        let chevronRead = [[AgentFrame(minX: 976.5, minY: 0, width: 17.5)]]
        #expect(!AttemptVerdict.evaluate(captures: [clean], reads: [], barHeightPt: 32, members: [], visible: [], overlap: .clear).seesChevron)
        #expect(AttemptVerdict.evaluate(captures: [clean], reads: chevronRead, barHeightPt: 32, members: [], visible: [], overlap: .clear).seesChevron)
        #expect(AttemptVerdict.evaluate(captures: [clean, pixels], reads: [], barHeightPt: 32, members: [], visible: [], overlap: .clear).seesChevron)
    }

    @Test("an inconclusive capture makes the attempt inconclusive")
    func inconclusiveCapture() {
        let clean = CaptureLabels(labels: [:], matches: [:], sightings: [], inconclusive: [], chevron: .absent)
        let twin = CaptureLabels(labels: [:], matches: [:], sightings: [], inconclusive: [.spreadPlacements("m1")], chevron: .absent)
        #expect(AttemptVerdict.evaluate(captures: [clean, twin], reads: [], barHeightPt: 32, members: [], visible: [], overlap: .clear).inconclusive)
    }
}
