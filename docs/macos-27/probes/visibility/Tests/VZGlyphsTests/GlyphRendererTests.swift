// T1 (docs/plans/2026-10-01-icebar-c-instrument.md): the scale-parameterized
// coverage renderer the oracle's templates come from (pre-registration
// section 5, "Rendering"), and the coloured (255, 0, 0) path.
import CryptoKit
import Foundation
import Testing
import VZGlyphs

@Suite("GlyphRenderer")
struct GlyphRendererTests {
    /// sha256 of the alpha bytes `GlyphCheck.coverage` produced at scale 2
    /// before the renderer existed (commit 40c7f7c), computed from a verbatim
    /// copy of that function: the renderer must reproduce them exactly.
    static let scale2Golden: [Glyph: String] = [
        .target: "7fb268cefb2b998c7011f3acf6c17a08903bb0a880ba9cd896bd8a822187eef8",
        .reference: "b73433b4009ee369775a41cdab122cd1e350094b291bcc4bc243e512de68517c",
        .alt: "49ec7d087e4ecd3d1e4585698382be82999b43cc64413fc1ec7df7ff2c83ad43",
        .hidden2: "bd5a8cd6b1774767f79f39520397afaf811e693bbe8878eaf274f536b697ed59",
        .hidden3: "e0b2beb771351ddaa23a180d5d4bf01ff3cb9a85dbbaa23535c5d5f0cd7c2620",
        .hidden4: "5a5333c245e18c8e319417f8fdcc0e2e7f79510db6226f7105877d7cdf65c12f",
    ]

    static func sha256(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }

    @Test("scale 1 renders 12 x 12 px and scale 2 renders 24 x 24 px", arguments: [1, 2])
    func sizePerScale(scale: Int) throws {
        let coverage = try GlyphRenderer.coverage(.target, scale: scale)
        #expect(coverage.sidePx == 12 * scale)
        #expect(coverage.alpha.count == coverage.sidePx * coverage.sidePx)
        #expect(coverage.scale == scale)
    }

    @Test("scale 2 reproduces the pre-renderer GlyphCheck coverage byte for byte", arguments: Array(scale2Golden.keys))
    func scale2MatchesGolden(glyph: Glyph) throws {
        let coverage = try GlyphRenderer.coverage(glyph, scale: 2)
        #expect(Self.sha256(coverage.alpha) == Self.scale2Golden[glyph])
    }

    @Test("a scale other than 1 or 2 is refused", arguments: [0, 3, -1])
    func unsupportedScale(scale: Int) {
        #expect(throws: GlyphRenderer.Failure.unsupportedScale(scale)) {
            try GlyphRenderer.coverage(.target, scale: scale)
        }
    }

    @Test("the coloured variant has the ordinary variant's shape", arguments: Glyph.allCases, [1, 2])
    func colouredSameShape(glyph: Glyph, scale: Int) throws {
        let ordinary = try GlyphRenderer.coverage(glyph, scale: scale)
        let coloured = try GlyphRenderer.coverage(glyph, scale: scale, coloured: true)
        #expect(coloured.alpha == ordinary.alpha)
        #expect(ordinary.rgb == nil)
        #expect(coloured.rgb?.count == coloured.alpha.count * 3)
    }

    @Test("the coloured variant is sRGB (255, 0, 0) wherever it is mostly opaque", arguments: Glyph.allCases, [1, 2])
    func colouredIsRed(glyph: Glyph, scale: Int) throws {
        let coloured = try GlyphRenderer.coverage(glyph, scale: scale, coloured: true)
        let rgb = try #require(coloured.rgb)
        var checked = 0
        for i in coloured.alpha.indices where coloured.alpha[i] >= 128 {
            let (r, g, b) = (Int(rgb[i * 3]), Int(rgb[i * 3 + 1]), Int(rgb[i * 3 + 2]))
            #expect(abs(r - 255) <= 1 && g <= 1 && b <= 1, "pixel \(i): (\(r), \(g), \(b))")
            checked += 1
        }
        #expect(checked > 0)
    }

    @Test("the coloured image is not a template and the ordinary one is")
    func templateFlag() {
        #expect(Glyphs.image(.target, side: 12).isTemplate)
        #expect(!Glyphs.image(.target, side: 12, coloured: true).isTemplate)
    }

    @Test("on-set and off-set follow section 5: P is alpha >= 0.5, Q is alpha = 0")
    func onAndOffSets() throws {
        let coverage = try GlyphRenderer.coverage(.hidden3, scale: 2)
        #expect(coverage.onSet.count == coverage.alpha.filter { $0 >= 128 }.count)
        #expect(coverage.offSet.count == coverage.alpha.filter { $0 == 0 }.count)
        #expect(Set(coverage.onSet).isDisjoint(with: coverage.offSet))
    }
}
