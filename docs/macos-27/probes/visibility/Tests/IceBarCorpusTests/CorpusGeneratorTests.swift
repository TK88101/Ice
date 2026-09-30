// T5 (docs/plans/2026-10-01-icebar-c-instrument.md): the corpus generator,
// tested without any oracle matching (the corpus is frozen before the oracle
// first runs on it). Visible on-pixel counts come from the oracle's own
// visibility function only.
import Foundation
import IceBarCorpus
import IceBarOracle
import IceCore
import Testing
import VZGlyphs

@Suite("Corpus generator", .serialized)
struct CorpusGeneratorTests {
    static let templates = Result { try CorpusTemplates(kDirectory: KCaptures.directory) }
    static let recipe = Result { try CorpusRecipe.specs(templates: templates.get()) }

    func spec(_ id: String) throws -> ItemSpec {
        try #require(Self.recipe.get().items.first { $0.id == id }, "no item \(id)")
    }

    @Test("item ids are unique and every registered row S1-S14 and K is present")
    func rows() throws {
        let items = try Self.recipe.get().items
        #expect(Set(items.map(\.id)).count == items.count)
        let rows = Set(items.map(\.row))
        #expect(rows == Set((1...14).map { "S\($0)" } + ["K"]))
    }

    @Test("K inputs have the pre-registered sha256; K2 and K3 are one item")
    func kInputs() throws {
        for input in KCaptures.inputs {
            let data = try Data(contentsOf: KCaptures.directory.appendingPathComponent(input.file))
            #expect(Digest.sha256(data) == input.sha256, "\(input.id)")
        }
        let k = try Self.recipe.get().items.filter { $0.row == "K" }.map(\.id)
        #expect(k == ["K1", "K2", "K4"])
    }

    @Test("rendering is deterministic, seeded noise included")
    func deterministic() throws {
        let templates = try Self.templates.get()
        for id in ["S7-noise6-2x", "S10-value32-empty-2x", "S1-zed-x1100-redOnLight-1x"] {
            let a = try CorpusRenderer.render(spec(id), templates: templates)
            let b = try CorpusRenderer.render(spec(id), templates: templates)
            #expect(a.image.bytes == b.image.bytes, "\(id)")
        }
        let n16 = try CorpusRenderer.render(spec("S10-value16-empty-2x"), templates: templates)
        let n32 = try CorpusRenderer.render(spec("S10-value32-empty-2x"), templates: templates)
        #expect(n16.image.bytes != n32.image.bytes)
    }

    @Test("every S13 cut and count is reached by some glyph at each scale, exactly")
    func s13Counts() throws {
        let (items, _) = try Self.recipe.get()
        let templates = try Self.templates.get()
        let s13 = items.filter { $0.row == "S13" }
        for cut in S13Cut.allCases {
            for count in [3, 4, 15] {
                for scale in [1, 2] {
                    let found = s13.filter { $0.id.contains("-\(cut.rawValue)-n\(count)-") && $0.scale == scale }
                    #expect(!found.isEmpty, "\(cut) n=\(count) \(scale)x unreachable for every glyph")
                }
            }
        }
        for item in s13 {
            let placed = try #require(item.glyphs.first { $0.role == .test })
            let n = try visibleOn(item, placed, templates)
            #expect(item.id.contains("-n\(n)-"), "\(item.id): visible \(n)")
        }
    }

    // Deviation 1 of the pre-registration: by visible on-px n.
    @Test("S2, S3, S5, S13 expected labels follow the visible on-pixel count")
    func countRule() throws {
        let (items, _) = try Self.recipe.get()
        let templates = try Self.templates.get()
        for item in items where ["S2", "S3", "S5", "S13"].contains(item.row) {
            for placed in item.glyphs where placed.role == .test {
                let n = try visibleOn(item, placed, templates)
                let all = try templates.helper(placed.glyph, scale: item.scale).onCount
                let expected = try #require(item.expected.helpers?[placed.glyph.rawValue])
                switch expected {
                case .none:
                    #expect(n < 4, "\(item.id)")
                case let .drawn(classes, _, _):
                    let want: MatchClass = n == all ? .full : n >= 16 ? .partial : .edge
                    #expect(n >= 4 && classes == [want], "\(item.id): n=\(n) expected \(classes)")
                }
            }
        }
    }

    @Test("S5 touching keeps every on-pixel visible")
    func s5Touching() throws {
        let templates = try Self.templates.get()
        for scale in [1, 2] {
            let item = try spec("S5-hook-touching-\(scale)x")
            let placed = try #require(item.glyphs.first { $0.role == .test })
            #expect(try visibleOn(item, placed, templates) == templates.helper(.hook, scale: scale).onCount)
            #expect(item.expected.helpers?["hook"] == .drawn([.full], xPt: 1369.5, zone: .rightOfReferences))
        }
    }

    @Test("references sit in fixed slots and vacate when their glyph is placed elsewhere (D2)")
    func referenceSlots() throws {
        let plain = try spec("S1-zed-x1100-whiteOnDark-2x")
        #expect(plain.glyphs.filter { $0.role == .reference }.map(\.glyph) == [.reference, .alt])
        #expect(plain.expected.helpers?["reference"] == .drawn([.full], xPt: 1318.5, zone: .rightOfReferences))
        let moved = try spec("S1-alt-x700-whiteOnDark-2x")
        #expect(moved.glyphs.filter { $0.role == .reference }.map(\.glyph) == [.reference])
        #expect(moved.expected.helpers?["alt"] == .drawn([.full], xPt: 701.5, zone: .leftOfNotch))
        let empty = try spec("S7-dark-2x")
        #expect(empty.glyphs.isEmpty)
        #expect(empty.expected.helpers?.values.allSatisfy { $0 == .none } == true)
    }

    @Test("the notch renders black and the capsule violet")
    func notchAndCapsule() throws {
        let item = try CorpusRenderer.render(spec("S7-light-2x"), templates: Self.templates.get())
        let mid = item.image.height / 2
        #expect(item.image.pixel(x: 1600, y: mid) == RGBA(0, 0, 0))
        #expect(item.image.pixel(x: 2780, y: mid) == RGBA(130, 90, 250))
        #expect(item.image.pixel(x: 2000, y: mid) == RGBA(235, 235, 235))
        #expect(item.context.agentFrames == [PtSpan(lo: 1380, hi: 1400)])
    }

    @Test("S9 expects inconclusive, S14 and K1/K2 expect the chevron, K4 does not; scale 1 is not evaluable")
    func specialExpectations() throws {
        #expect(try spec("S9-ess-2x").expected.inconclusive)
        #expect(try spec("S14-noAX-2x").expected.chevron == .present)
        #expect(try spec("K2").expected.chevron == .present)
        #expect(try spec("K4").expected.chevron == .absent)
        #expect(try spec("K4").expected.helpers == nil)
        #expect(try spec("S1-zed-x1100-whiteOnDark-1x").expected.chevron == .notEvaluable)
        #expect(try Self.recipe.get().items.filter { $0.row == "S14" }.allSatisfy { $0.scale == 2 })
    }

    @Test("a PNG round trip keeps the raw bytes")
    func pngRoundTrip() throws {
        let item = try CorpusRenderer.render(spec("S10-blueOrange-empty-1x"), templates: Self.templates.get())
        let png = try PNGIO.encode(item.image)
        let back = try PNGIO.decode(png)
        #expect(back.bytes == item.image.bytes)
    }

    @Test("the freeze manifest has every registered key, non-empty")
    func manifestSchema() throws {
        let templates = try Self.templates.get()
        let items = try Array(Self.recipe.get().items.prefix(3))
        let manifest = try FreezeBuilder.manifest(
            runId: "test", gitRevision: "abc", preregistrationSHA256: "def",
            sources: ["Sources/x.swift": "00"], items: items, templates: templates, unreachable: ["u"],
            pngSHA256: { _ in "11" }
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any]
        for key in ["runId", "gitRevision", "preregistrationSHA256", "sources", "renderings", "chevronTemplate", "kInputs", "items", "unreachable"] {
            let value = try #require(json?[key], "missing \(key)")
            if let array = value as? [Any] { #expect(!array.isEmpty, "\(key) empty") }
            if let dict = value as? [String: Any] { #expect(!dict.isEmpty, "\(key) empty") }
        }
        #expect(manifest.renderings.count == Glyph.allCases.count * 2)
        #expect(manifest.items.count == 3)
    }

    func visibleOn(_ item: ItemSpec, _ placed: GlyphPlacement, _ templates: CorpusTemplates) throws -> Int {
        let geometry = OracleGeometry(widthPx: CorpusGeometry.widthPx(scale: item.scale), heightPx: CorpusGeometry.heightPx(scale: item.scale),
                                      scale: Double(item.scale), context: item.context)
        return try geometry.visibleOnCount(templates.helper(placed.glyph, scale: item.scale), x0: placed.xPx, y0: placed.yPx)
    }
}
