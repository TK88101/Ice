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
                            textureRegionPt: [KCaptures.textureRegion.lo, KCaptures.textureRegion.hi],
                            textureFramesPt: refused ? [[KCaptures.k2ChevronFramePt.lo, KCaptures.k2ChevronFramePt.hi]] : [],
                            mode: refused ? .textureRefused : .exact,
                            expected: .unasserted(chevron: refused ? nil : input.chevron))
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

struct Subject {
    let glyph: Glyph
    let xPx: Int
    let yPx: Int
    let ink: InkSpec
    let alphaFactor: Double
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

    /// Expectations come from each glyph's visible on-pixel count (C6, D3.2),
    /// not from the row.
    func subject(_ glyph: Glyph, xPt: Double, dy: Int = 0, ink: InkSpec = ColourCase.whiteOnDark.ink, alpha: Double = 1) -> Subject {
        Subject(glyph: glyph, xPx: x(xPt), yPx: top + dy, ink: ink, alphaFactor: alpha)
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
        if mode == .textureRefused {
            expected = .unasserted()
        } else if twin || overlapping {
            expected = .unasserted(inconclusive: true)
        } else {
            expected = try expectation(glyphs, geometry: geometry, chevron: chevron ?? (scale == 2 ? .absent : .notEvaluable))
        }
        return ItemSpec(id: id, row: row, scale: scale, backdrop: backdrop, glyphs: glyphs, chevrons: chevrons,
                        capsuleXPt: capsuleXPt, agentFramesPt: frames, recorded: nil, seedSalt: salt, windows: windows,
                        visibleControls: controls, textureRegionPt: Self.textureRegion, textureFramesPt: frames,
                        mode: mode, expected: expected)
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

    /// Rule 1's region: notch right edge to the leftmost reference.
    static let textureRegion = [CorpusGeometry.notch.hi, CorpusGeometry.leftmostReferencePt]

    /// C2 / D4.1: uniform backdrops are flat by construction; the rest are
    /// rendered (backdrop only) and judged by `TextureBound` over the region.
    func modeFor(_ backdrop: Backdrop, id: String, frames: [[Double]]) throws -> ExpectationMode {
        if case .uniform = backdrop { return .exact }
        let image = CorpusRenderer.backdrop(backdrop, scale: scale, seed: CorpusRenderer.seed(salt: salt, id: id))
        let outcome = TextureBound.evaluate(image, region: PtSpan(lo: Self.textureRegion[0], hi: Self.textureRegion[1]),
                                            notch: CorpusGeometry.notch, agentFrames: frames.map { PtSpan(lo: $0[0], hi: $0[1]) })
        if case .accepted = outcome { return .exact }
        return .textureRefused
    }

    func expectation(_ glyphs: [GlyphPlacement], geometry: OracleGeometry, chevron: ChevronSighting) throws -> Expectation {
        var helpers = [String: ExpectedLabel]()
        for glyph in Glyph.allCases { helpers[glyph.rawValue] = ExpectedLabel.none }
        var required = [String: [Int]]()
        var cutIdentity = [String: ExpectedLabel]()
        var placedColumns = [[Int]]()
        var memberSeen = false
        var faint = false
        for placed in glyphs {
            let template = try templates.helper(placed.glyph, scale: scale)
            let n = geometry.visibleOnCount(template, x0: placed.xPx, y0: placed.yPx)
            let columns = (placed.xPx..<(placed.xPx + side)).filter { geometry.isVisible(x: $0, y: placed.yPx) }
            if let lo = columns.first, let hi = columns.last { placedColumns.append([lo, hi + 1]) }
            let isMember = Self.members.contains(placed.glyph)
            let full = ExpectedLabel.drawn([.full], xPt: CorpusGeometry.labelX(placed.xPx, scale: scale),
                                           zone: CorpusGeometry.zone(x0: placed.xPx, width: side, scale: scale))
            if n == template.onCount {
                helpers[placed.glyph.rawValue] = full
                if isMember { memberSeen = true }
            } else if n >= 4, let lo = columns.first, let hi = columns.last {
                // D3.2: identified as itself, or sighted; a visible glyph
                // identified means no member, sighted means a member alarm.
                required[placed.glyph.rawValue] = [lo, hi + 1]
                cutIdentity[placed.glyph.rawValue] = full
                if isMember { memberSeen = true } else { faint = true }
            } else if n > 0 {
                faint = true
            }
        }
        let sees: Tri = memberSeen ? .yes : faint ? .either : .no
        return Expectation(helpers: helpers, requiredSightings: required, cutIdentity: cutIdentity, placedColumns: placedColumns, seesMember: sees,
                           inconclusive: false, chevron: chevron)
    }

    /// The references' ink follows the bar: white on a dark backdrop, black on the light one.
    func inkFor(_ backdrop: Backdrop) -> InkSpec {
        backdrop == .uniform(ColourCase.light) ? ColourCase.blackOnLight.ink : ColourCase.whiteOnDark.ink
    }
}
