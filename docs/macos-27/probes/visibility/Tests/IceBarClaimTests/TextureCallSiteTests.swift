// U9b (deviation 2 C6) and its call site (deviation 4, item 5; claim plan R10):
// rule 1 calls part 1's `TextureBound` itself, over rule 1's region with the
// notch and the canonical agent frames excluded -- the construction the corpus
// used (`CorpusRecipe.textureRegion`, notch, agent frames).
@testable import IceBarClaim
import IceBarCorpus
import IceBarOracle
import IceCore
import Testing

@Suite("U9b: texture bound in rule 1")
struct TextureCallSiteTests {
    func grey(_ d: Int) -> RGB3 { (UInt8(40 + d), UInt8(40 + d), UInt8(40 + d)) }

    @Test("U9b: a region pixel 12 from M_x is accepted, 13 refused", arguments: [(12, true), (13, false)])
    func bound(delta: Int, accepted: Bool) {
        var strip = Bar.strip()
        strip.set(400, 30, grey(delta))
        let verdict = Bar.verdict(Bar.samples(strip.image))
        #expect(verdict.failedClauses == (accepted ? [] : [.texture]))
        #expect(verdict.measurements.texture == (accepted ? .accepted(maxDeviation: delta) : .refused(maxDeviation: delta)))
    }

    @Test("U9b: deviations only in notch or agent columns are accepted")
    func exclusions() {
        var strip = Bar.strip()
        strip.set(250, 30, grey(80))
        strip.set(410, 30, grey(80))
        let reads = Array(repeating: Bar.agentFrames + [AgentFrame(minX: 200, minY: 0, width: 20)], count: 5)
        let verdict = Bar.verdict(Bar.samples(strip.image, reads: reads))
        #expect(verdict.failedClauses.isEmpty)
        #expect(verdict.measurements.texture == .accepted(maxDeviation: 0))
    }

    // MARK: the call site at the corpus geometry

    /// The corpus bar (`CorpusGeometry`): references at their slots, the
    /// capsule, and one more agent frame inside the region so its exclusion
    /// is visible.
    enum CorpusBar {
        static let geometry = BarGeometry(widthPt: Double(CorpusGeometry.widthPt), heightPt: Double(CorpusGeometry.heightPt),
                                          scale: 2, notch: CorpusGeometry.notch)
        static let frames = [
            AgentFrame(minX: 1200, minY: 0, width: 20),
            AgentFrame(minX: CorpusGeometry.capsuleXPt, minY: 0, width: CorpusGeometry.capsuleWidthPt),
        ]
        static let shapes = [Shapes.bracket(), Shapes.mirrored()]
        static let ids = CorpusGeometry.referenceSlots.map(\.glyph.rawValue)

        static func strip() -> Strip {
            var strip = Strip(widthPt: geometry.widthPt, heightPt: geometry.heightPt)
            strip.fill(1543..<1913, (0, 0, 0))
            for (slot, shape) in zip(CorpusGeometry.referenceSlots, shapes) {
                strip.stamp(shape, at: Int(slot.xPt * 2), 22)
            }
            return strip
        }

        static func verdict(_ image: StripImage) -> (BaselineVerdict, BaselineResult) {
            let items = Dictionary(uniqueKeysWithValues: zip(ids, CorpusGeometry.referenceSlots).map {
                ($0, ItemFrame(id: $0, minX: $1.xPt, minY: 0, width: 10, height: geometry.heightPt))
            })
            let samples = (0..<5).map {
                ObservationSample(time: Double($0), before: image, after: image, agentFrames: frames, itemFrames: items)
            }
            let frozen = StripAssessor.baseline(samples: samples, geometry: geometry, parameters: .preRegistered)
            let visible = zip(ids, shapes).map { OracleTemplate(id: $0, width: Shapes.side, height: Shapes.side, alpha: $1, scale: 2) }
            return (HiddenBaseline.evaluate(kept: Array(samples.dropFirst()), frozen: frozen, references: ids, visible: visible), frozen)
        }
    }

    @Test("call site: rule 1's region, notch and agent frames are the corpus's construction")
    func arguments() throws {
        let (verdict, frozen) = CorpusBar.verdict(CorpusBar.strip().image)
        guard case let .accepted(baseline) = verdict.outcome else {
            Issue.record("refused: \(verdict.outcome)")
            return
        }
        let origin = try #require(frozen.templates[CorpusBar.ids[0]]?.originXPt)
        #expect(baseline.region == PtSpan(lo: CorpusGeometry.notch.hi, hi: origin))
        #expect(origin == CorpusGeometry.leftmostReferencePt)
        #expect(baseline.notch == CorpusGeometry.notch)
        #expect(baseline.canonicalAgentFrames.map(\.span) == CorpusBar.frames.map(\.span))
    }

    @Test("call site: the texture outcome is TextureBound's with the corpus's arguments", arguments: [
        (1913, false), // the first region column
        (2633, false), // the last region column
        (2634, true), // the reference's own box, right of the region
        (2410, true), // inside the in-region agent frame
        (1700, true), // inside the notch
    ])
    func sameArguments(column: Int, accepted: Bool) {
        var strip = CorpusBar.strip()
        strip.set(column, 5, grey(13))
        let image = strip.image
        let (verdict, _) = CorpusBar.verdict(image)
        let corpus = TextureBound.evaluate(image, region: PtSpan(lo: CorpusGeometry.notch.hi, hi: CorpusGeometry.leftmostReferencePt),
                                           notch: CorpusGeometry.notch, agentFrames: CorpusBar.frames.map(\.span))
        #expect(verdict.measurements.texture == corpus)
        #expect(verdict.failedClauses == (accepted ? [] : [.texture]))
    }
}
