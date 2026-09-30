// Deviation 2 of the pre-registration (docs/plans/2026-10-01-icebar-c-deviation2.md),
// instrument plan section 7a: U9b (texture bound), U22b (sightings), U22d
// (overlap guard), U22e (live `«` (b) control).
@testable import IceBarOracle
import IceCore
import Testing

@Suite("Deviation 2 kernels")
struct Deviation2KernelsTests {
    let y0 = 22
    let region = PtSpan(lo: 956.5, hi: 1317)

    // U9b: every region pixel outside notch and agent columns within 12 of M_x.
    @Test("texture bound: a deviation of 12 is accepted, 13 refused", arguments: [(12, true), (13, false)])
    func textureBound(delta: Int, accepted: Bool) {
        var canvas = Canvas(backdrop: (90, 90, 90))
        canvas.set(2100, 30, (UInt8(90 + delta), 90, 90))
        let outcome = TextureBound.evaluate(canvas.image, region: region, notch: PtSpan(lo: 771.5, hi: 956.5), agentFrames: [])
        #expect(outcome == (accepted ? .accepted(maxDeviation: delta) : .refused(maxDeviation: delta)))
    }

    @Test("texture bound: deviations only in notch or agent columns, or outside the region, are accepted")
    func textureBoundExclusions() {
        var canvas = Canvas(backdrop: (90, 90, 90))
        canvas.fillColumns(1543..<1913, (0, 0, 0))
        canvas.fillColumns(2760..<2800, (130, 90, 250))
        canvas.fillColumns(3000..<3010, (255, 255, 255))
        let outcome = TextureBound.evaluate(canvas.image, region: PtSpan(lo: 771.5, hi: 1450), notch: PtSpan(lo: 771.5, hi: 956.5),
                                            agentFrames: [PtSpan(lo: 1380, hi: 1400)])
        #expect(outcome == .accepted(maxDeviation: 0))
    }

    // U22d: the overlap guard over every helper.
    @Test("overlap guard: 0.5 pt of overlap is clear, 0.6 pt overlaps")
    func overlapGuard() {
        let a = WindowBounds(x: 1100, y: 0, width: 12, height: 24)
        #expect(OverlapGuard.evaluate(roster: ["a", "b"], bounds: ["a": a, "b": WindowBounds(x: 1111.5, y: 0, width: 12, height: 24)]) == .clear)
        #expect(OverlapGuard.evaluate(roster: ["a", "b"], bounds: ["a": a, "b": WindowBounds(x: 1111.4, y: 0, width: 12, height: 24)]) == .overlap("a", "b"))
    }

    @Test("overlap guard: a helper with no bounds is missing; a hidden helper listed off-screen is clear")
    func overlapGuardMissing() {
        let a = WindowBounds(x: 1100, y: 0, width: 12, height: 24)
        #expect(OverlapGuard.evaluate(roster: ["a", "hidden"], bounds: ["a": a]) == .missing("hidden"))
        #expect(OverlapGuard.evaluate(roster: ["a", "hidden"], bounds: ["a": a, "hidden": WindowBounds(x: -500, y: 0, width: 12, height: 24)]) == .clear)
    }

    @Test("a guard outcome other than clear makes the attempt inconclusive")
    func guardInconclusive() {
        let clean = CaptureLabels(labels: [:], matches: [:], sightings: [], inconclusive: [], chevron: .absent)
        let clear = AttemptVerdict.evaluate(captures: [clean], reads: [], barHeightPt: 32, members: [], visible: [], overlap: .clear)
        #expect(!clear.inconclusive)
        let overlap = AttemptVerdict.evaluate(captures: [clean], reads: [], barHeightPt: 32, members: [], visible: [], overlap: .overlap("a", "b"))
        #expect(overlap.inconclusive)
    }

    // U22e: (a) implies (b), >= 10 captures, >= 2 episodes; a mismatch first.
    @Test("live (b) control: valid, mismatch, too few captures, too few episodes")
    func bControl() {
        let ten = (0..<10).map { BObservation(episode: $0 < 5 ? 1 : 2, axChevron: true, pixels: .present) }
        #expect(BControl.evaluate(ten) == .valid(captures: 10, episodes: 2))
        #expect(BControl.evaluate(ten + [BObservation(episode: 3, axChevron: false, pixels: .absent)]) == .valid(captures: 10, episodes: 2))
        var missed = ten
        missed[3] = BObservation(episode: 1, axChevron: true, pixels: .absent)
        #expect(BControl.evaluate(missed) == .mismatch(index: 3))
        #expect(BControl.evaluate(Array(ten.prefix(9))) == .insufficientCaptures(9))
        #expect(BControl.evaluate(ten.map { BObservation(episode: 1, axChevron: $0.axChevron, pixels: $0.pixels) }) == .insufficientEpisodes(1))
    }

    // U22b: sightings explained only by the ink of a full-identified helper.
    @Test("a partial match on the post of an identified glyph is an explained sighting")
    func explainedSighting() throws {
        var postB = [UInt8](repeating: 0, count: 400)
        for y in 2..<18 {
            for x in [0, 1, 2, 3, 16, 17] { postB[y * 20 + x] = 255 }
            postB[y * 20 + 18] = 64
            postB[y * 20 + 19] = 64
        }
        let a = OracleTemplate(id: "a", width: 20, height: 20, alpha: Shapes.bracket(), scale: 2)
        let b = OracleTemplate(id: "b", width: 20, height: 20, alpha: postB, scale: 2)
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 2200, y0)
        canvas.fillColumns(2186..<2202, (130, 90, 250))
        let context = OracleContext(notch: PtSpan(lo: 771.5, hi: 956.5), agentFrames: [PtSpan(lo: 1093, hi: 1101)], leftmostReferenceOriginPt: 1317)
        let labels = try Oracle.label(image: canvas.image, helpers: [a, b], chevron: nil, context: context)
        #expect(labels.labels["a"] == .drawn(.full, xPt: 1101.5, zone: .region))
        #expect(labels.labels["b"] == HelperLabel.none)
        #expect(labels.sightings.contains { $0.templateID == "b" && $0.xPx == 2186 && $0.explained })
        #expect(labels.sightings.allSatisfy { $0.explained })
        let verdict = AttemptVerdict.evaluate(captures: [labels], reads: [], barHeightPt: 32, members: ["b"], visible: [], overlap: .clear)
        #expect(!verdict.seesMember)
    }

    @Test("adversarial: a member sliver touching a full visible helper is unexplained and seen")
    func adversarialSliver() throws {
        let v = OracleTemplate(id: "v", width: 20, height: 20, alpha: Shapes.bracket(), scale: 2)
        let m = OracleTemplate(id: "m", width: 20, height: 20, alpha: Shapes.mirrored(), scale: 2)
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 2200, y0)
        canvas.stamp(Shapes.mirrored(), side: 20, at: 2178, y0)
        canvas.fillColumns(2178..<2194, (130, 90, 250))
        let context = OracleContext(notch: PtSpan(lo: 771.5, hi: 956.5), agentFrames: [PtSpan(lo: 1089, hi: 1097)], leftmostReferenceOriginPt: 1317)
        let labels = try Oracle.label(image: canvas.image, helpers: [v, m], chevron: nil, context: context)
        #expect(labels.labels["v"] == .drawn(.full, xPt: 1101.5, zone: .region))
        #expect(labels.labels["m"] == HelperLabel.none)
        #expect(labels.sightings.contains { !$0.explained })
        let verdict = AttemptVerdict.evaluate(captures: [labels], reads: [], barHeightPt: 32, members: ["m"],
                                              visible: [VisibleHelper(id: "v", axMinX: 1100)], overlap: .clear)
        #expect(verdict.seesMember)
        #expect(!verdict.inconclusive)
    }

    // Deviation 3 D3.1: a chevron partial sharing hits with a helper sighting
    // is an unexplained sighting by definition, even over identified ink.
    func postTemplate(_ id: String) -> OracleTemplate {
        var alpha = [UInt8](repeating: 0, count: 400)
        for y in 2..<18 {
            for x in [0, 1, 2, 3, 16, 17] { alpha[y * 20 + x] = 255 }
            alpha[y * 20 + 18] = 64
            alpha[y * 20 + 19] = 64
        }
        return OracleTemplate(id: id, width: 20, height: 20, alpha: alpha, scale: 2)
    }

    @Test("an ambiguous chevron partial is not `«` but an unexplained sighting, never explained")
    func ambiguousChevron() throws {
        let a = OracleTemplate(id: "a", width: 20, height: 20, alpha: Shapes.bracket(), scale: 2)
        var canvas = Canvas()
        canvas.stamp(Shapes.bracket(), side: 20, at: 2200, y0)
        canvas.fillColumns(2186..<2202, (130, 90, 250))
        let context = OracleContext(notch: PtSpan(lo: 771.5, hi: 956.5), agentFrames: [PtSpan(lo: 1093, hi: 1101)], leftmostReferenceOriginPt: 1317)
        let labels = try Oracle.label(image: canvas.image, helpers: [a, postTemplate("b")], chevron: postTemplate(ChevronTemplate.id), context: context)
        #expect(labels.chevron == .absent)
        let ambiguous = labels.sightings.contains { $0.templateID == ChevronTemplate.id && !$0.explained }
        #expect(ambiguous)
        let verdict = AttemptVerdict.evaluate(captures: [labels], reads: [], barHeightPt: 32, members: ["b"], visible: [], overlap: .clear)
        #expect(verdict.seesMember)
    }

    @Test("a chevron partial no helper template sights is `«`")
    func unambiguousChevron() throws {
        var alpha = [UInt8](repeating: 0, count: 400)
        for y in 2..<18 { for x in [0, 1, 2, 3, 16, 17] { alpha[y * 20 + x] = 255 } }
        var canvas = Canvas()
        canvas.stamp(alpha, side: 20, at: 2186, y0)
        canvas.fillColumns(2190..<2202, (130, 90, 250))
        let context = OracleContext(notch: PtSpan(lo: 771.5, hi: 956.5), agentFrames: [PtSpan(lo: 1095, hi: 1101)], leftmostReferenceOriginPt: 1317)
        let labels = try Oracle.label(image: canvas.image, helpers: [], chevron: postTemplate(ChevronTemplate.id), context: context)
        #expect(labels.chevron == .present)
        #expect(labels.sightings.isEmpty)
    }
}
