// The corpus recipe (pre-registration section 6, deviation 1; readings D2,
// D3, D19-D25 of docs/plans/2026-10-01-icebar-c-instrument.md). Specs only:
// pixels are drawn by `CorpusRenderer`.
import IceBarOracle
import IceCore
import VZGlyphs

public enum CorpusRecipe {
    /// `salt` seeds every item's noise (deviation 2 C6: `corpus-2`; `dev` for
    /// development runs; "" reproduces freeze 1's seeds).
    public static func specs(templates: CorpusTemplates, salt: String) throws -> (items: [ItemSpec], unreachable: [String]) {
        var items = [ItemSpec]()
        var unreachable = [String]()
        for scale in CorpusGeometry.scales {
            let b = ItemBuilder(templates: templates, scale: scale, salt: salt)
            items += try b.s1() + b.s2() + b.s3() + b.s4() + b.s5() + b.s6() + b.s7()
            items += try b.s8() + b.s9() + b.s10() + b.s11() + b.s12()
            let (s13, missing) = try b.s13()
            items += s13
            unreachable += missing
        }
        items += try ItemBuilder(templates: templates, scale: 2, salt: salt).s14()
        items += KCaptures.items.map { input in
            let refused = input.id == "K2"
            return ItemSpec(id: input.id, row: "K", scale: 2, backdrop: .uniform(.grey(0)), glyphs: [], chevrons: [],
                            capsuleXPt: 0, agentFramesPt: [], recorded: input.file, seedSalt: salt, windows: [:], visibleControls: [],
                            mode: refused ? .textureRefused : .exact,
                            expected: Expectation(helpers: nil, requiredSightings: [:], placedColumns: [], seesMember: nil, inconclusive: nil,
                                                  chevron: refused ? nil : input.chevron, memberVisiblyDrawn: false))
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
    let salt: String
    static let canonicalFrames = [CorpusGeometry.capsuleFrame(xPt: CorpusGeometry.capsuleXPt)]
    static let members = Set(Glyph.allCases.filter { !CorpusGeometry.visibleGlyphs.contains($0) })

    var top: Int { CorpusGeometry.glyphTop(scale: scale) }
    var side: Int { CorpusGeometry.glyphSidePt * scale }
    func x(_ pt: Double) -> Int { CorpusGeometry.px(pt, scale: scale) }

    func subject(_ glyph: Glyph, xPt: Double, dy: Int = 0, ink: InkSpec = ColourCase.whiteOnDark.ink,
                 alpha: Double = 1, _ expect: Expect) -> Subject {
        Subject(glyph: glyph, xPx: x(xPt), yPx: top + dy, ink: ink, alphaFactor: alpha, expect: expect)
    }

    /// References fill their slots unless the item is empty or their glyph is
    /// placed elsewhere (D2, D3). Expectations per section 7a, T12.
    func item(_ base: String, row: String, backdrop: Backdrop, subjects: [Subject], chevrons: [ChevronPlacement] = [],
              capsuleXPt: Double = CorpusGeometry.capsuleXPt, frames: [[Double]] = canonicalFrames,
              twin: Bool = false, chevron: ChevronSighting? = nil, empty: Bool = false) throws -> ItemSpec {
        let id = "\(base)-\(scale)x"
        let placedGlyphs = Set(subjects.map(\.glyph))
        var glyphs = subjects.map {
            GlyphPlacement(glyph: $0.glyph, role: .test, xPx: $0.xPx, yPx: $0.yPx, ink: $0.ink, alphaFactor: $0.alphaFactor)
        }
        var controls = [VisibleControl]()
        if !empty {
            for slot in CorpusGeometry.referenceSlots where !placedGlyphs.contains(slot.glyph) {
                glyphs.append(GlyphPlacement(glyph: slot.glyph, role: .reference, xPx: x(slot.xPt), yPx: top, ink: inkFor(backdrop), alphaFactor: 1))
                controls.append(VisibleControl(id: slot.glyph.rawValue, axMinX: slot.xPt))
            }
        }
        let windows = windowsFor(glyphs)
        let geometry = geometryFor(frames)
        let mode = try modeFor(backdrop, id: id, frames: frames)
        let overlapping = OverlapGuard.evaluate(roster: Glyph.allCases.map(\.rawValue), bounds: windows) != .clear
        let expected: Expectation
        if twin || overlapping {
            expected = Expectation(helpers: nil, requiredSightings: [:], placedColumns: [], seesMember: nil, inconclusive: true,
                                   chevron: nil, memberVisiblyDrawn: false)
        } else {
            expected = try expectation(glyphs, geometry: geometry, mode: mode, chevron: chevron ?? (scale == 2 ? .absent : .notEvaluable))
        }
        return ItemSpec(id: id, row: row, scale: scale, backdrop: backdrop, glyphs: glyphs, chevrons: chevrons,
                        capsuleXPt: capsuleXPt, agentFramesPt: frames, recorded: nil, seedSalt: salt, windows: windows,
                        visibleControls: controls, mode: mode, expected: expected)
    }

    /// C3's guard input for all 19 helpers: drawn ones at their image box,
    /// the rest listed off-screen and disjoint.
    func windowsFor(_ glyphs: [GlyphPlacement]) -> [String: WindowBounds] {
        var windows = [String: WindowBounds]()
        for (i, glyph) in Glyph.allCases.enumerated() {
            windows[glyph.rawValue] = WindowBounds(x: -1000 - 20 * Double(i), y: 0, width: 12, height: 24)
        }
        var seen = Set<Glyph>()
        for placed in glyphs where seen.insert(placed.glyph).inserted {
            windows[placed.glyph.rawValue] = WindowBounds(x: Double(placed.xPx) / Double(scale), y: 0, width: 12, height: 24)
        }
        return windows
    }

    /// C2: uniform backdrops are flat by construction; the rest are rendered
    /// (backdrop only) and judged by `TextureBound` over the region.
    func modeFor(_ backdrop: Backdrop, id: String, frames: [[Double]]) throws -> ExpectationMode {
        if case .uniform = backdrop { return .exact }
        var canvas = Canvas(scale: scale)
        canvas.fill(backdrop, seed: CorpusRenderer.seed(salt: salt, id: id))
        let image = StripImage(width: canvas.width, height: canvas.height, scale: Double(scale), bytes: canvas.bytes)
        let outcome = TextureBound.evaluate(image, region: PtSpan(lo: CorpusGeometry.notch.hi, hi: CorpusGeometry.leftmostReferencePt),
                                            notch: CorpusGeometry.notch, agentFrames: frames.map { PtSpan(lo: $0[0], hi: $0[1]) })
        if case .accepted = outcome { return .exact }
        return .failClosed
    }

    func expectation(_ glyphs: [GlyphPlacement], geometry: OracleGeometry, mode: ExpectationMode, chevron: ChevronSighting) throws -> Expectation {
        var helpers = [String: ExpectedLabel]()
        for glyph in Glyph.allCases { helpers[glyph.rawValue] = ExpectedLabel.none }
        var required = [String: [Int]]()
        var placedColumns = [[Int]]()
        var identifiedMember = false
        var cutSeen = false
        var faint = false
        var memberVisiblyDrawn = false
        for placed in glyphs {
            let template = try templates.helper(placed.glyph, scale: scale)
            let n = geometry.visibleOnCount(template, x0: placed.xPx, y0: placed.yPx)
            let columns = (placed.xPx..<(placed.xPx + side)).filter { geometry.isVisible(x: $0, y: placed.yPx) }
            if let lo = columns.first, let hi = columns.last { placedColumns.append([lo, hi + 1]) }
            let isMember = Self.members.contains(placed.glyph)
            if isMember && n >= 4 { memberVisiblyDrawn = true }
            if n == template.onCount {
                helpers[placed.glyph.rawValue] = .drawn([.full], xPt: CorpusGeometry.labelX(placed.xPx, scale: scale),
                                                        zone: CorpusGeometry.zone(x0: placed.xPx, width: side, scale: scale))
                if isMember { identifiedMember = true }
            } else if n >= 4, let lo = columns.first, let hi = columns.last {
                required[placed.glyph.rawValue] = [lo, hi + 1]
                cutSeen = true
            } else if n > 0 {
                faint = true
            }
        }
        if mode == .failClosed {
            return Expectation(helpers: nil, requiredSightings: [:], placedColumns: [], seesMember: nil, inconclusive: nil,
                               chevron: nil, memberVisiblyDrawn: memberVisiblyDrawn)
        }
        let sees: Tri = identifiedMember || cutSeen ? .yes : faint ? .either : .no
        return Expectation(helpers: helpers, requiredSightings: required, placedColumns: placedColumns, seesMember: sees,
                           inconclusive: false, chevron: chevron, memberVisiblyDrawn: memberVisiblyDrawn)
    }

    /// The references' ink follows the bar: white on a dark backdrop, black on the light one.
    func inkFor(_ backdrop: Backdrop) -> InkSpec {
        backdrop == .uniform(ColourCase.light) ? ColourCase.blackOnLight.ink : ColourCase.whiteOnDark.ink
    }
}
