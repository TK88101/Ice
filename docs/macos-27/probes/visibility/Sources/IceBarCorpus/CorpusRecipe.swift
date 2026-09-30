// The corpus recipe (pre-registration section 6, deviation 1; readings D2,
// D3, D19-D25 of docs/plans/2026-10-01-icebar-c-instrument.md). Specs only:
// pixels are drawn by `CorpusRenderer`.
import IceBarOracle
import IceCore
import VZGlyphs

public enum CorpusRecipe {
    public static func specs(templates: CorpusTemplates) throws -> (items: [ItemSpec], unreachable: [String]) {
        var items = [ItemSpec]()
        var unreachable = [String]()
        for scale in CorpusGeometry.scales {
            let b = ItemBuilder(templates: templates, scale: scale)
            items += try b.s1() + b.s2() + b.s3() + b.s4() + b.s5() + b.s6() + b.s7()
            items += try b.s8() + b.s9() + b.s10() + b.s11() + b.s12()
            let (s13, missing) = try b.s13()
            items += s13
            unreachable += missing
        }
        items += try ItemBuilder(templates: templates, scale: 2).s14()
        items += KCaptures.items.map { input in
            ItemSpec(id: input.id, row: "K", scale: 2, backdrop: .uniform(.grey(0)), glyphs: [], chevrons: [],
                     capsuleXPt: 0, agentFramesPt: [], recorded: input.file,
                     expected: Expectation(helpers: nil, chevron: input.chevron, inconclusive: false))
        }
        return (items, unreachable)
    }
}

/// D20.
enum ColourCase: String, CaseIterable {
    case whiteOnDark, blackOnLight, redOnDark, redOnLight

    static let dark = RGB.grey(40)
    static let light = RGB.grey(235)

    var backdrop: Backdrop { .uniform(self == .whiteOnDark || self == .redOnDark ? Self.dark : Self.light) }
    var ink: InkSpec {
        switch self {
        case .whiteOnDark: .solid(.grey(255))
        case .blackOnLight: .solid(.grey(0))
        case .redOnDark, .redOnLight: .coloured
        }
    }
}

/// What a placed glyph must be labelled.
enum Expect {
    /// `drawn(full)` as the row says.
    case full
    /// "drawn" / "found as itself": any class.
    case any
    /// Deviation 1: by its visible on-pixel count.
    case byCount
}

struct Subject {
    let glyph: Glyph
    let xPx: Int
    let yPx: Int
    let ink: InkSpec
    let alphaFactor: Double
    let expect: Expect
}

struct ItemBuilder {
    let templates: CorpusTemplates
    let scale: Int
    static let canonicalFrames = [CorpusGeometry.capsuleFrame(xPt: CorpusGeometry.capsuleXPt)]

    var top: Int { CorpusGeometry.glyphTop(scale: scale) }
    var side: Int { CorpusGeometry.glyphSidePt * scale }
    func x(_ pt: Double) -> Int { CorpusGeometry.px(pt, scale: scale) }

    func subject(_ glyph: Glyph, xPt: Double, dy: Int = 0, ink: InkSpec = ColourCase.whiteOnDark.ink,
                 alpha: Double = 1, _ expect: Expect) -> Subject {
        Subject(glyph: glyph, xPx: x(xPt), yPx: top + dy, ink: ink, alphaFactor: alpha, expect: expect)
    }

    /// References fill their slots unless the item is empty or their glyph is
    /// placed elsewhere (D2, D3); every helper not placed is expected `none`.
    func item(_ base: String, row: String, backdrop: Backdrop, subjects: [Subject], chevrons: [ChevronPlacement] = [],
              capsuleXPt: Double = CorpusGeometry.capsuleXPt, frames: [[Double]] = canonicalFrames,
              inconclusive: Bool = false, chevron: ChevronSighting? = nil, empty: Bool = false) throws -> ItemSpec {
        let placedGlyphs = Set(subjects.map(\.glyph))
        var glyphs = subjects.map {
            GlyphPlacement(glyph: $0.glyph, role: .test, xPx: $0.xPx, yPx: $0.yPx, ink: $0.ink, alphaFactor: $0.alphaFactor)
        }
        var helpers = [String: ExpectedLabel]()
        for glyph in Glyph.allCases { helpers[glyph.rawValue] = ExpectedLabel.none }
        if !empty {
            for slot in CorpusGeometry.referenceSlots where !placedGlyphs.contains(slot.glyph) {
                let placement = GlyphPlacement(glyph: slot.glyph, role: .reference, xPx: x(slot.xPt), yPx: top,
                                               ink: inkFor(backdrop), alphaFactor: 1)
                glyphs.append(placement)
                helpers[slot.glyph.rawValue] = .drawn([.full], xPt: CorpusGeometry.labelX(placement.xPx, scale: scale), zone: .rightOfReferences)
            }
        }
        let context = OracleContext(notch: CorpusGeometry.notch, agentFrames: frames.map { PtSpan(lo: $0[0], hi: $0[1]) },
                                    leftmostReferenceOriginPt: CorpusGeometry.leftmostReferencePt)
        let geometry = OracleGeometry(widthPx: CorpusGeometry.widthPx(scale: scale), heightPx: CorpusGeometry.heightPx(scale: scale),
                                      scale: Double(scale), context: context)
        for s in subjects {
            helpers[s.glyph.rawValue] = try expected(s, geometry: geometry)
        }
        return ItemSpec(
            id: "\(base)-\(scale)x", row: row, scale: scale, backdrop: backdrop, glyphs: glyphs, chevrons: chevrons,
            capsuleXPt: capsuleXPt, agentFramesPt: frames, recorded: nil,
            expected: Expectation(helpers: helpers, chevron: chevron ?? (scale == 2 ? .absent : .notEvaluable), inconclusive: inconclusive)
        )
    }

    /// The references' ink follows the bar: white on a dark backdrop, black on the light one.
    func inkFor(_ backdrop: Backdrop) -> InkSpec {
        backdrop == .uniform(ColourCase.light) ? ColourCase.blackOnLight.ink : ColourCase.whiteOnDark.ink
    }

    func expected(_ s: Subject, geometry: OracleGeometry) throws -> ExpectedLabel {
        let at = CorpusGeometry.labelX(s.xPx, scale: scale)
        let zone = CorpusGeometry.zone(x0: s.xPx, width: side, scale: scale)
        switch s.expect {
        case .full:
            return .drawn([.full], xPt: at, zone: zone)
        case .any:
            return .drawn([.full, .partial, .edge], xPt: at, zone: zone)
        case .byCount:
            let template = try templates.helper(s.glyph, scale: scale)
            let n = geometry.visibleOnCount(template, x0: s.xPx, y0: s.yPx)
            if n == template.onCount { return .drawn([.full], xPt: at, zone: zone) }
            if n >= 16 { return .drawn([.partial], xPt: at, zone: zone) }
            if n >= 4 { return .drawn([.edge], xPt: at, zone: zone) }
            return .none
        }
    }
}
