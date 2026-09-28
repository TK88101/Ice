// T2 (docs/plans/2026-09-28-c2-protocol.md): every helper glyph, C2's three
// hidden-section glyphs included, is pairwise distinct under IceCore's own
// baseline rules, and the identical-twin negative control is refused.
import Testing
import VZGlyphs

@Suite("GlyphCheck")
struct GlyphCheckTests {
    @Test("all six glyphs are accepted and the twin control is refused as not unique")
    func glyphsPairwiseDistinct() {
        let result = GlyphCheck.run()
        #expect(result.passed, "\(result.lines.joined(separator: "\n"))")
    }
}
