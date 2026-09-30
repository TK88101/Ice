// Rows S1-S14 of the pre-registration's section 6, as reading D19 of the
// instrument plan expands them. Positions are image-box origins in points.
import IceBarOracle
import IceCore
import VZGlyphs

extension ItemBuilder {
    static let s1Zones: [Double] = [700, 1100, 1450]
    static let s2Fractions = [25, 50, 75]
    static let s13Counts = [3, 4, 15]
    static let texturedBackdrops: [(String, Backdrop)] = [
        ("value16", .valueNoise(amplitude: 16)), ("value32", .valueNoise(amplitude: 32)),
        ("diagonal", .diagonal), ("blueOrange", .blueOrange),
    ]
    static let texturedInks: [(String, InkSpec)] = [("white", ColourCase.whiteOnDark.ink), ("red", .coloured)]

    /// S2's box origin: `fraction` % of the 12 pt box inside the notch.
    static func straddleX(edge: String, fraction: Int) -> Double {
        let inside = 12 * Double(fraction) / 100
        return edge == "right" ? CorpusGeometry.notch.hi - inside : CorpusGeometry.notch.lo - 12 + inside
    }

    func s1() throws -> [ItemSpec] {
        try Glyph.allCases.flatMap { g in
            try Self.s1Zones.flatMap { xPt in
                try ColourCase.allCases.map { c in
                    try item("S1-\(g.rawValue)-x\(Int(xPt))-\(c.rawValue)", row: "S1", backdrop: c.backdrop,
                             subjects: [subject(g, xPt: xPt, ink: c.ink, .full)])
                }
            }
        }
    }

    func s2() throws -> [ItemSpec] {
        try Glyph.allCases.flatMap { g in
            try Self.s2Fractions.flatMap { f in
                try ["left", "right"].flatMap { edge in
                    try ColourCase.allCases.map { c in
                        try item("S2-\(g.rawValue)-\(edge)\(f)-\(c.rawValue)", row: "S2", backdrop: c.backdrop,
                                 subjects: [subject(g, xPt: Self.straddleX(edge: edge, fraction: f), ink: c.ink, .byCount)])
                    }
                }
            }
        }
    }

    func s3() throws -> [ItemSpec] {
        try Glyph.allCases.flatMap { g in
            try [("start", -6.0), ("end", Double(CorpusGeometry.widthPt) - 6)].flatMap { name, xPt in
                try ColourCase.allCases.map { c in
                    try item("S3-\(g.rawValue)-\(name)-\(c.rawValue)", row: "S3", backdrop: c.backdrop,
                             subjects: [subject(g, xPt: xPt, ink: c.ink, .byCount)])
                }
            }
        }
    }

    func s4() throws -> [ItemSpec] {
        try Glyph.allCases.flatMap { a in
            try Glyph.allCases.filter { $0 != a }.map { b in
                try item("S4-\(a.rawValue)-\(b.rawValue)", row: "S4", backdrop: ColourCase.whiteOnDark.backdrop,
                         subjects: [subject(a, xPt: 1100, .any), subject(b, xPt: 1108, .any)])
            }
        }
    }

    /// Touching: the box ends where the capsule starts; under: 2 pt under it.
    func s5() throws -> [ItemSpec] {
        try Glyph.allCases.flatMap { g in
            [
                try item("S5-\(g.rawValue)-touching", row: "S5", backdrop: ColourCase.whiteOnDark.backdrop,
                         subjects: [subject(g, xPt: CorpusGeometry.capsuleXPt - 12, .full)]),
                try item("S5-\(g.rawValue)-under", row: "S5", backdrop: ColourCase.whiteOnDark.backdrop,
                         subjects: [subject(g, xPt: CorpusGeometry.capsuleXPt - 10, .byCount)]),
            ]
        }
    }

    func s6() throws -> [ItemSpec] {
        let cases: [(String, String, ColourCase)] = [
            ("ordinary", "dark", .whiteOnDark), ("ordinary", "light", .blackOnLight),
            ("coloured", "dark", .redOnDark), ("coloured", "light", .redOnLight),
        ]
        return try Glyph.allCases.flatMap { g in
            try cases.map { variant, bg, c in
                try item("S6-\(g.rawValue)-\(variant)-\(bg)", row: "S6", backdrop: c.backdrop,
                         subjects: [subject(g, xPt: 1100, ink: c.ink, alpha: 0.5, .full)])
            }
        }
    }

    func s7() throws -> [ItemSpec] {
        let backdrops: [(String, Backdrop)] = [
            ("dark", .uniform(ColourCase.dark)), ("light", .uniform(ColourCase.light)),
            ("gradient", .gradientX(from: 40, to: 80)), ("noise6", .noise6(ColourCase.dark)),
        ]
        return try backdrops.map { name, backdrop in
            try item("S7-\(name)", row: "S7", backdrop: backdrop, subjects: [], empty: true)
        }
    }

    /// The 17 glyphs without a slot in the region, 20 pt apart; the slot
    /// glyphs in their slots.
    func s8() throws -> [ItemSpec] {
        let slotted = Set(CorpusGeometry.referenceSlots.map(\.glyph))
        let rest = Glyph.allCases.filter { !slotted.contains($0) }
        return try [ColourCase.whiteOnDark, .blackOnLight].map { c in
            let subjects = rest.enumerated().map { i, g in subject(g, xPt: 970 + 20 * Double(i), ink: c.ink, .any) }
            return try item("S8-\(c == .whiteOnDark ? "dark" : "light")", row: "S8", backdrop: c.backdrop, subjects: subjects)
        }
    }

    func s9() throws -> [ItemSpec] {
        try Glyph.allCases.map { g in
            try item("S9-\(g.rawValue)", row: "S9", backdrop: ColourCase.whiteOnDark.backdrop,
                     subjects: [subject(g, xPt: 1100, .any), subject(g, xPt: 1130, .any)], inconclusive: true)
        }
    }

    func s10() throws -> [ItemSpec] {
        var items = [ItemSpec]()
        for (name, backdrop) in Self.texturedBackdrops {
            items.append(try item("S10-\(name)-empty", row: "S10", backdrop: backdrop, subjects: [], empty: true))
            for g in Glyph.allCases {
                for (inkName, ink) in Self.texturedInks {
                    for xPt in Self.s1Zones {
                        items.append(try item("S10-\(name)-S1-\(g.rawValue)-x\(Int(xPt))-\(inkName)", row: "S10", backdrop: backdrop,
                                              subjects: [subject(g, xPt: xPt, ink: ink, .full)]))
                    }
                    for f in Self.s2Fractions {
                        for edge in ["left", "right"] {
                            items.append(try item("S10-\(name)-S2-\(g.rawValue)-\(edge)\(f)-\(inkName)", row: "S10", backdrop: backdrop,
                                                  subjects: [subject(g, xPt: Self.straddleX(edge: edge, fraction: f), ink: ink, .byCount)]))
                        }
                    }
                }
            }
        }
        return items
    }

    func s11() throws -> [ItemSpec] {
        try Glyph.allCases.flatMap { g in
            try [-4, 0, 4].map { dy in
                try item("S11-\(g.rawValue)-dy\(dy)", row: "S11", backdrop: ColourCase.whiteOnDark.backdrop,
                         subjects: [subject(g, xPt: 1100, dy: dy, .full)])
            }
        }
    }

    /// Cyclic triples 1 pt apart; cyclic (ordinary, coloured) pairs adjacent.
    func s12() throws -> [ItemSpec] {
        let all = Glyph.allCases
        var items = [ItemSpec]()
        for c in [ColourCase.whiteOnDark, .blackOnLight] {
            let bg = c == .whiteOnDark ? "dark" : "light"
            for i in all.indices {
                let triple = (0..<3).map { all[(i + $0) % all.count] }
                items.append(try item("S12-triple-\(i)-\(bg)", row: "S12", backdrop: c.backdrop,
                                      subjects: triple.enumerated().map { k, g in subject(g, xPt: 1100 + 13 * Double(k), ink: c.ink, .any) }))
                items.append(try item("S12-pair-\(i)-\(bg)", row: "S12", backdrop: c.backdrop,
                                      subjects: [subject(all[i], xPt: 1100, ink: c.ink, .any),
                                                 subject(all[(i + 1) % all.count], xPt: 1112, ink: .coloured, .any)]))
            }
        }
        return items
    }

    func s14() throws -> [ItemSpec] {
        let chevron = templates.chevron
        let y = (CorpusGeometry.heightPx(scale: scale) - chevron.height) / 2
        let notchHi = CorpusGeometry.notchColumns(scale: scale).upperBound
        let placements: [(String, Int)] = [
            ("noAX", x(1100)),
            ("notchCut", notchHi - chevron.width / 2),
            ("underCapsule", x(CorpusGeometry.capsuleXPt + 4) - chevron.width),
        ]
        return try placements.map { name, x0 in
            try item("S14-\(name)", row: "S14", backdrop: ColourCase.whiteOnDark.backdrop, subjects: [],
                     chevrons: [ChevronPlacement(xPx: x0, yPx: y)], chevron: .present)
        }
    }
}
