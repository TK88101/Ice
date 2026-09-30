// T2 (docs/plans/2026-10-01-icebar-c-instrument.md): route C's 19 glyphs
// (16 members + 3 visible, pre-registration section 5), pairwise distinct
// under the oracle's own rule at scale 1 and 2.
import IceBarOracle
import IceCore
import Testing
import VZGlyphs

@Suite("Glyph set")
struct GlyphSetTests {
    @Test("there are 19 glyphs, the six existing ones first and unchanged in order")
    func nineteen() {
        #expect(Glyph.allCases.count == 19)
        #expect(Array(Glyph.allCases.prefix(6)) == [.target, .reference, .alt, .hidden2, .hidden3, .hidden4])
    }

    @Test("every glyph has at least 16 on-pixels and some off-pixels at each scale", arguments: Glyph.allCases, [1, 2])
    func onAndOff(glyph: Glyph, scale: Int) throws {
        let coverage = try GlyphRenderer.coverage(glyph, scale: scale)
        #expect(coverage.onSet.count >= 16)
        #expect(!coverage.offSet.isEmpty)
    }

    /// Each glyph alone, white on (40, 40, 40), searched with all 19
    /// templates: only itself is drawn, full, and nothing is inconclusive.
    @Test("each glyph is found as itself only", arguments: Glyph.allCases, [1, 2])
    func foundAsItselfOnly(glyph: Glyph, scale: Int) throws {
        let templates = try Glyph.allCases.map { g in
            let c = try GlyphRenderer.coverage(g, scale: scale)
            return OracleTemplate(id: g.rawValue, width: c.sidePx, height: c.sidePx, alpha: c.alpha, scale: Double(scale))
        }
        let image = try GlyphStrip.single(glyph, scale: scale, xPt: 30)
        let context = OracleContext(notch: nil, agentFrames: [], leftmostReferenceOriginPt: nil)
        let labels = try Oracle.label(image: image, helpers: templates, chevron: nil, context: context)
        #expect(labels.labels[glyph.rawValue] == .drawn(.full, xPt: 31.5, zone: .region))
        for other in Glyph.allCases where other != glyph {
            #expect(labels.labels[other.rawValue] == HelperLabel.none, "\(other.rawValue) matched \(glyph.rawValue)")
        }
        #expect(labels.inconclusive.isEmpty, "\(labels.inconclusive)")
    }

    @Test("GlyphCheck: all 19 accepted by the frozen baseline rules, the twin refused")
    func glyphCheck() {
        let result = GlyphCheck.run()
        #expect(result.passed, "\(result.lines.joined(separator: "\n"))")
    }
}

/// A 72 x 32 pt strip with one glyph composited by its coverage.
enum GlyphStrip {
    static func single(_ glyph: Glyph, scale: Int, xPt: Int) throws -> StripImage {
        let coverage = try GlyphRenderer.coverage(glyph, scale: scale)
        let width = 72 * scale
        let height = 32 * scale
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let top = (height - coverage.sidePx) / 2
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                var value = 40.0
                let gx = x - xPt * scale
                let gy = y - top
                if gx >= 0, gx < coverage.sidePx, gy >= 0, gy < coverage.sidePx {
                    value += 215 * Double(coverage.alpha[gy * coverage.sidePx + gx]) / 255
                }
                let v = UInt8(value.rounded())
                bytes[i] = v
                bytes[i + 1] = v
                bytes[i + 2] = v
            }
        }
        return StripImage(width: width, height: height, scale: Double(scale), bytes: bytes)
    }
}
