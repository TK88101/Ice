// T3 (docs/plans/2026-10-01-icebar-c-instrument.md): the oracle's match rules,
// pre-registration section 5, with the readings D5-D15 of the plan's section 3.
// The bracket shape (OracleTestSupport) has 92 on-pixels and 308 off-pixels.
@testable import IceBarOracle
import IceCore
import Testing

@Suite("Oracle rules")
struct OracleRulesTests {
    let bracket = OracleTemplate(id: "a", width: 20, height: 20, alpha: Shapes.bracket(), scale: 2)
    /// Vertical centre of a 20 px box on a 64 px strip: (64 - 20) / 2.
    let y0 = 22

    func label(_ canvas: Canvas, _ templates: [OracleTemplate]? = nil, context: OracleContext = .corpus()) throws -> CaptureLabels {
        try Oracle.label(image: canvas.image, helpers: templates ?? [bracket], chevron: nil, context: context)
    }

    @Test("the bracket has 92 on-pixels and 308 off-pixels")
    func shapeCounts() {
        #expect(bracket.onCount == 92)
        #expect(bracket.offCount == 308)
    }

    // D5: the notch columns, re-implemented from BarGeometry.
    @Test("notch columns: 1x 771..<957, 2x 1543..<1913, equal to BarGeometry column by column", arguments: [1.0, 2.0])
    func notchColumns(scale: Double) {
        let notch = PtSpan(lo: 771.5, hi: 956.5)
        let columns = OracleGeometry.notchColumns(notch, scale: scale)
        #expect(columns == (scale == 1 ? 771..<957 : 1543..<1913))
        let geometry = BarGeometry(widthPt: 1728, heightPt: 32, scale: scale, notch: notch)
        for x in 0..<geometry.widthPx {
            #expect(columns.contains(x) == !geometry.allowsSpan(fromPx: x, widthPx: 1), "column \(x)")
        }
    }

    @Test("a glyph drawn in the region is drawn(full) at its box origin + 1.5 pt")
    func fullInRegion() throws {
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 2200, y0)
        let labels = try label(canvas)
        #expect(labels.labels["a"] == .drawn(.full, xPt: 1101.5, zone: .region))
        #expect(labels.inconclusive.isEmpty)
        #expect(labels.chevron == .notEvaluable)
    }

    @Test("an empty strip labels every helper none")
    func emptyStrip() throws {
        let labels = try label(Canvas())
        #expect(labels.labels["a"] == HelperLabel.none)
        #expect(labels.matches["a"]?.isEmpty ?? true)
    }

    @Test("hits: 9 of 92 on-pixels missing is full (>= 90 %), 10 missing is none", arguments: [(9, true), (10, false)])
    func hitBoundary(missing: Int, found: Bool) throws {
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 2200, y0)
        // Erase from the bottom bar, right to left.
        for i in 0..<missing { canvas.set(2200 + 16 - i % 15, y0 + 17 - i / 15, (40, 40, 40)) }
        let labels = try label(canvas)
        #expect((labels.labels["a"] == .drawn(.full, xPt: 1101.5, zone: .region)) == found)
        if !found { #expect(labels.labels["a"] == HelperLabel.none) }
    }

    @Test("false: 30 of 308 off-pixels inked is full (<= 10 %), 31 is none", arguments: [(30, true), (31, false)])
    func falseBoundary(inked: Int, found: Bool) throws {
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 2200, y0)
        // Rows 0, 1 and 19 of the box are all off-pixels.
        let rows = [0, 1, 19]
        for i in 0..<inked { canvas.set(2200 + i % 20, y0 + rows[i / 20], (255, 255, 255)) }
        let labels = try label(canvas)
        #expect((labels.labels["a"] == .drawn(.full, xPt: 1101.5, zone: .region)) == found)
        if !found { #expect(labels.labels["a"] == HelperLabel.none) }
    }

    @Test("zones: left of the notch, the region, right of the references")
    func zones() throws {
        for (x0, zone) in [(1400, Zone.leftOfNotch), (2200, .region), (2900, .rightOfReferences)] {
            var canvas = Canvas()
            canvas.stamp(Shapes.bracket(), side: 20, at: x0, y0)
            let labels = try label(canvas)
            #expect(labels.labels["a"] == .drawn(.full, xPt: Double(x0) / 2 + 1.5, zone: zone))
        }
    }

    // Box at 1900: columns 0-12 in the notch (1543..<1913), 13-19 visible, 16 on-px.
    @Test("partial: 16 visible on-px with one miss is drawn(partial, notchEdge)")
    func partialAtNotch() throws {
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 1900, y0)
        canvas.fillColumns(1543..<1913, (0, 0, 0))
        canvas.set(1900 + 16, y0 + 2, (40, 40, 40))
        let labels = try label(canvas)
        #expect(labels.labels["a"] == .drawn(.partial, xPt: 951.5, zone: .notchEdge))
    }

    // Box at 1899: columns 14-19 visible, 12 on-px; one miss makes it
    // neither partial (< 16 px) nor edge (not 100 %).
    @Test("fewer than 16 visible on-px with a miss is neither partial nor edge")
    func belowPartialWithMiss() throws {
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 1899, y0)
        canvas.fillColumns(1543..<1913, (0, 0, 0))
        canvas.set(1899 + 16, y0 + 2, (40, 40, 40))
        let labels = try label(canvas)
        #expect(labels.labels["a"] == HelperLabel.none)
    }

    // Box at 1897: only column 16 visible, 4 on-px, all hits, no false.
    @Test("edge: 4 visible on-px, all hits and no false, is drawn(edge)")
    func edgeFour() throws {
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 1897, y0)
        canvas.fillColumns(1543..<1913, (0, 0, 0))
        let labels = try label(canvas)
        #expect(labels.labels["a"] == .drawn(.edge, xPt: 950, zone: .notchEdge))
    }

    @Test("edge: one false off-pixel in the visible part refuses it")
    func edgeFalse() throws {
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 1897, y0)
        canvas.fillColumns(1543..<1913, (0, 0, 0))
        canvas.set(1897 + 18, y0 + 10, (255, 255, 255))
        let labels = try label(canvas)
        #expect(labels.labels["a"] == HelperLabel.none)
    }

    // D6: agent-frame columns (2760..<2800 at 2x) are not visible.
    @Test("a glyph partly under an agent frame is drawn(partial)")
    func underAgentFrame() throws {
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 2744, y0)
        canvas.fillColumns(2760..<2800, (130, 90, 250))
        let labels = try label(canvas)
        #expect(labels.labels["a"] == .drawn(.partial, xPt: 1373.5, zone: .rightOfReferences))
    }

    @Test("a glyph touching an agent frame (0 pt gap) is drawn(full)")
    func touchingAgentFrame() throws {
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 2740, y0)
        canvas.fillColumns(2760..<2800, (130, 90, 250))
        let labels = try label(canvas)
        #expect(labels.labels["a"] == .drawn(.full, xPt: 1371.5, zone: .rightOfReferences))
    }

    // D10: windows of +-1.5 pt around each edge; the notch's right edge is
    // 956.5 pt = 1913 px, so its window is 1910...1916 px.
    @Test("edge eligibility: a box reaching into the +-1.5 pt window is eligible")
    func edgeWindow() {
        let geometry = OracleGeometry(widthPx: 3456, heightPx: 64, scale: 2, context: .corpus())
        #expect(!geometry.isEdgeEligible(x0: 1890, width: 20))
        #expect(geometry.isEdgeEligible(x0: 1891, width: 20))
        #expect(geometry.isEdgeEligible(x0: 1915, width: 20))
        #expect(!geometry.isEdgeEligible(x0: 1916, width: 20))
        #expect(geometry.isEdgeEligible(x0: 2, width: 20))
        #expect(!geometry.isEdgeEligible(x0: 3, width: 20))
    }

    @Test("the local backdrop is the per-channel lower median")
    func lowerMedian() {
        var histogram = [Int](repeating: 0, count: 256)
        for v in [5, 1, 3, 2] { histogram[v] += 1 }
        #expect(Oracle.lowerMedian(histogram, count: 4) == 2)
        histogram[9] += 1
        #expect(Oracle.lowerMedian(histogram, count: 5) == 3)
    }

    // D14: two different helpers matching one placement.
    @Test("two helpers whose templates match the same box make the capture inconclusive")
    func sharedPlacement() throws {
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 2200, y0)
        let twin = OracleTemplate(id: "b", width: 20, height: 20, alpha: Shapes.bracket(), scale: 2)
        let labels = try label(canvas, [bracket, twin])
        #expect(labels.inconclusive.contains(.sharedPlacement("a", "b")))
    }

    @Test("two different glyphs far apart are both found and nothing is inconclusive")
    func twoDistinct() throws {
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 2200, y0)
        canvas.stamp(Shapes.mirrored(), side: 20, at: 2400, y0)
        let mirror = OracleTemplate(id: "b", width: 20, height: 20, alpha: Shapes.mirrored(), scale: 2)
        let labels = try label(canvas, [bracket, mirror])
        #expect(labels.labels["a"] == .drawn(.full, xPt: 1101.5, zone: .region))
        #expect(labels.labels["b"] == .drawn(.full, xPt: 1201.5, zone: .region))
        #expect(labels.inconclusive.isEmpty)
    }

    // D15: one helper matching two placements more than 2 pt apart.
    @Test("the same glyph twice makes the capture inconclusive")
    func spread() throws {
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 2200, y0)
        canvas.stamp(Shapes.bracket(), side: 20, at: 2260, y0)
        let labels = try label(canvas)
        #expect(labels.inconclusive.contains(.spreadPlacements("a")))
    }

    @Test("a template at a scale other than the image's is refused")
    func scaleMismatch() {
        let oneX = OracleTemplate(id: "a", width: 20, height: 20, alpha: Shapes.bracket(), scale: 1)
        #expect(throws: OracleError.scaleMismatch(id: "a")) {
            try Oracle.label(image: Canvas().image, helpers: [oneX], chevron: nil, context: .corpus())
        }
    }

    @Test("the range prune never changes a result", arguments: [UInt64(11), 23, 47])
    func pruneIsSound(seed: UInt64) throws {
        var rng = TestRNG(seed: seed)
        var canvas = Canvas(widthPt: 120, heightPt: 16, scale: 2, backdrop: (90, 90, 90))
        for x in 0..<canvas.width {
            for y in 0..<canvas.height where rng.next() % 3 == 0 {
                let v = UInt8(60 + rng.next() % 61)
                canvas.set(x, y, (v, v, v))
            }
        }
        canvas.stamp(Shapes.bracket(), side: 20, at: 30, 6)
        canvas.stamp(Shapes.bracket(), side: 20, at: 150, 7, ink: (200, 200, 200))
        let context = OracleContext(notch: PtSpan(lo: 60, hi: 70), agentFrames: [PtSpan(lo: 100, hi: 110)], leftmostReferenceOriginPt: 90)
        let pruned = try Oracle.matches(image: canvas.image, template: bracket, context: context, prune: true)
        let exhaustive = try Oracle.matches(image: canvas.image, template: bracket, context: context, prune: false)
        #expect(pruned == exhaustive)
        #expect(!exhaustive.isEmpty)
    }
}

struct TestRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
