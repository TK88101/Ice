// Every rendering the corpus and the oracle share: the 19 glyphs at scale 1
// and 2 (ordinary and coloured, by `GlyphRenderer`) and the chevron template
// cut from K1 (reading D16).
import Foundation
import IceBarOracle
import IceCore
import VZGlyphs

public struct CorpusTemplates: Sendable {
    private let ordinary: [Int: [Glyph: GlyphCoverage]]
    private let coloured: [Int: [Glyph: GlyphCoverage]]
    public let chevron: OracleTemplate
    public let k1SHA256: String

    public init(kDirectory: URL) throws {
        var ordinary = [Int: [Glyph: GlyphCoverage]]()
        var coloured = [Int: [Glyph: GlyphCoverage]]()
        for scale in CorpusGeometry.scales {
            for glyph in Glyph.allCases {
                ordinary[scale, default: [:]][glyph] = try GlyphRenderer.coverage(glyph, scale: scale)
                coloured[scale, default: [:]][glyph] = try GlyphRenderer.coverage(glyph, scale: scale, coloured: true)
            }
        }
        self.ordinary = ordinary
        self.coloured = coloured
        let k1 = try Data(contentsOf: kDirectory.appendingPathComponent(KCaptures.inputs[0].file))
        k1SHA256 = Digest.sha256(k1)
        chevron = try ChevronTemplate.cut(from: PNGIO.decode(k1, scale: 2), framePt: KCaptures.chevronFramePt)
    }

    public func coverage(_ glyph: Glyph, scale: Int, coloured isColoured: Bool = false) throws -> GlyphCoverage {
        guard let coverage = (isColoured ? coloured : ordinary)[scale]?[glyph] else {
            throw CorpusError.missingRendering("\(glyph.rawValue) \(scale)x")
        }
        return coverage
    }

    /// The oracle's template for a helper drawing `glyph`; its id is the
    /// glyph's name (the corpus roster maps one helper to one glyph).
    public func helper(_ glyph: Glyph, scale: Int) throws -> OracleTemplate {
        let c = try coverage(glyph, scale: scale)
        return OracleTemplate(id: glyph.rawValue, width: c.sidePx, height: c.sidePx, alpha: c.alpha, scale: Double(scale))
    }

    public func helpers(scale: Int) throws -> [OracleTemplate] {
        try Glyph.allCases.map { try helper($0, scale: scale) }
    }
}
