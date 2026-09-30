// S13 (pre-registration section 6): each glyph cut by the notch edge, the
// capsule's edge, the capsule's edge after a 1 pt shift, x = 0 and the right
// end, leaving exactly 3, 4 and 15 visible on-pixels (reading D19: every glyph
// for which the count is reachable; the rest are listed, not skipped).
import IceBarOracle
import IceCore
import VZGlyphs

extension ItemBuilder {
    /// y offsets tried in order, nearest the centre first.
    static let s13DyOrder = [0, -1, 1, -2, 2, -3, 3, -4, 4]

    func s13() throws -> ([ItemSpec], [String]) {
        var items = [ItemSpec]()
        var unreachable = [String]()
        for g in Glyph.allCases {
            let template = try templates.helper(g, scale: scale)
            for cut in S13Cut.allCases {
                let (capsuleXPt, frames) = cutContext(cut)
                let geometry = geometryFor(frames)
                for n in Self.s13Counts {
                    let base = "S13-\(g.rawValue)-\(cut.rawValue)-n\(n)"
                    guard let (x0, dy) = search(template, cut: cut, count: n, geometry: geometry) else {
                        unreachable.append("\(base)-\(scale)x")
                        continue
                    }
                    let placed = Subject(glyph: g, xPx: x0, yPx: top + dy, ink: ColourCase.whiteOnDark.ink, alphaFactor: 1, expect: .byCount)
                    items.append(try item(base, row: "S13", backdrop: ColourCase.whiteOnDark.backdrop, subjects: [placed],
                                          capsuleXPt: capsuleXPt, frames: frames))
                }
            }
        }
        return (items, unreachable)
    }

    /// The capsule's drawn x and the frames the oracle is given: for the
    /// shifted cut, the canonical frame and the attempt's own shifted one.
    func cutContext(_ cut: S13Cut) -> (Double, [[Double]]) {
        let canonical = CorpusGeometry.capsuleXPt
        guard cut == .capsuleShifted else { return (canonical, Self.canonicalFrames) }
        return (canonical + 1, [CorpusGeometry.capsuleFrame(xPt: canonical), CorpusGeometry.capsuleFrame(xPt: canonical + 1)])
    }

    func geometryFor(_ frames: [[Double]]) -> OracleGeometry {
        let context = OracleContext(notch: CorpusGeometry.notch, agentFrames: frames.map { PtSpan(lo: $0[0], hi: $0[1]) },
                                    leftmostReferenceOriginPt: CorpusGeometry.leftmostReferencePt)
        return OracleGeometry(widthPx: CorpusGeometry.widthPx(scale: scale), heightPx: CorpusGeometry.heightPx(scale: scale),
                              scale: Double(scale), context: context)
    }

    /// Box origins whose box straddles the cut's edge, the visible part on
    /// the side the cut leaves.
    func candidates(_ cut: S13Cut) -> ClosedRange<Int> {
        let edge: Int
        switch cut {
        case .notchEdge: edge = CorpusGeometry.notchColumns(scale: scale).upperBound
        case .capsuleEdge, .capsuleShifted: edge = x(CorpusGeometry.capsuleXPt)
        case .stripStart: edge = 0
        case .stripEnd: edge = CorpusGeometry.widthPx(scale: scale)
        }
        return (edge - side + 1)...(edge - 1)
    }

    func search(_ template: OracleTemplate, cut: S13Cut, count: Int, geometry: OracleGeometry) -> (Int, Int)? {
        for dy in Self.s13DyOrder {
            for x0 in candidates(cut) where geometry.visibleOnCount(template, x0: x0, y0: top + dy) == count {
                return (x0, dy)
            }
        }
        return nil
    }
}
