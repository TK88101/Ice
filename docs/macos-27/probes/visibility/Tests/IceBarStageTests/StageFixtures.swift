// The oracle's templates for the fake bar: the 19 real glyph renderings at
// scale 2 (`GlyphRenderer`, validated pairwise distinct by part 1) and a
// synthetic double chevron standing in for K1's (the evidence file is not a
// test input).
import IceBarOracle
@testable import IceBarStage
import VZGlyphs

enum StageFixtures {
    static let glyphOrder = Glyph.allCases.map(\.rawValue)

    static let templates: StageTemplates = {
        var helpers = [String: OracleTemplate]()
        for glyph in Glyph.allCases {
            let coverage = try! GlyphRenderer.coverage(glyph, scale: 2)
            helpers[glyph.rawValue] = OracleTemplate(id: glyph.rawValue, width: coverage.sidePx, height: coverage.sidePx, alpha: coverage.alpha, scale: 2)
        }
        return StageTemplates(helpers: helpers, chevron: chevron)
    }()

    /// Two left-pointing chevrons, 2 px strokes, 30 x 24 px.
    static let chevron: OracleTemplate = {
        let width = 30
        let height = 24
        var alpha = [UInt8](repeating: 0, count: width * height)
        for x0 in [4, 16] {
            for d in 0..<8 {
                for t in 0..<2 {
                    alpha[(12 - d) * width + x0 + d + t] = 255
                    alpha[(11 + d) * width + x0 + d + t] = 255
                }
            }
        }
        return OracleTemplate(id: ChevronTemplate.id, width: width, height: height, alpha: alpha, scale: 2)
    }()
}
