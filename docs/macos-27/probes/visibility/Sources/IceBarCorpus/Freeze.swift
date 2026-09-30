// The corpus freeze record (`freeze.json`, instrument plan section 4) and the
// check that runs the oracle on a frozen corpus (D25).
import Foundation
import IceBarOracle
import IceCore
import VZGlyphs

public struct FreezeManifest: Codable, Equatable, Sendable {
    public struct Rendering: Codable, Equatable, Sendable {
        public let glyph: String
        public let scale: Int
        public let alphaSHA256: String
        public let colouredRGBSHA256: String
    }

    public struct ChevronRecord: Codable, Equatable, Sendable {
        public let sourceFile: String
        public let sourceSHA256: String
        public let framePt: [Double]
        public let floor: Double
        public let width: Int
        public let height: Int
        public let alphaSHA256: String
    }

    public struct KRecord: Codable, Equatable, Sendable {
        public let id: String
        public let file: String
        public let expectedSHA256: String
        public let measuredSHA256: String
    }

    public struct ItemRecord: Codable, Equatable, Sendable {
        public let spec: ItemSpec
        public let rawSHA256: String
        public let pngSHA256: String
    }

    public let runId: String
    public let gitRevision: String
    public let preregistrationSHA256: String
    public let sources: [String: String]
    public let renderings: [Rendering]
    public let chevronTemplate: ChevronRecord
    public let kInputs: [KRecord]
    public let items: [ItemRecord]
    public let unreachable: [String]
}

public enum FreezeBuilder {
    /// Renders every item once; `pngSHA256` receives it (vzcorpus writes the
    /// PNG there) and returns the PNG's sha256.
    public static func manifest(
        runId: String, gitRevision: String, preregistrationSHA256: String, sources: [String: String],
        items: [ItemSpec], templates: CorpusTemplates, unreachable: [String],
        kDirectory: URL = KCaptures.directory, pngSHA256: (CorpusItem) throws -> String
    ) throws -> FreezeManifest {
        var renderings = [FreezeManifest.Rendering]()
        for scale in CorpusGeometry.scales {
            for glyph in Glyph.allCases {
                let ordinary = try templates.coverage(glyph, scale: scale)
                let coloured = try templates.coverage(glyph, scale: scale, coloured: true)
                renderings.append(.init(glyph: glyph.rawValue, scale: scale, alphaSHA256: Digest.sha256(ordinary.alpha),
                                        colouredRGBSHA256: Digest.sha256(coloured.rgb ?? [])))
            }
        }
        let chevron = templates.chevron
        let chevronRecord = FreezeManifest.ChevronRecord(
            sourceFile: KCaptures.inputs[0].file, sourceSHA256: templates.k1SHA256,
            framePt: [KCaptures.chevronFramePt.lo, KCaptures.chevronFramePt.hi], floor: ChevronTemplate.floor,
            width: chevron.width, height: chevron.height, alphaSHA256: Digest.sha256(chevron.alpha)
        )
        let kInputs = try KCaptures.inputs.map { input in
            let data = try Data(contentsOf: kDirectory.appendingPathComponent(input.file))
            return FreezeManifest.KRecord(id: input.id, file: input.file, expectedSHA256: input.sha256, measuredSHA256: Digest.sha256(data))
        }
        let records = try items.map { spec in
            let item = try CorpusRenderer.render(spec, templates: templates, kDirectory: kDirectory)
            return FreezeManifest.ItemRecord(spec: spec, rawSHA256: Digest.sha256(item.image.bytes), pngSHA256: try pngSHA256(item))
        }
        return FreezeManifest(runId: runId, gitRevision: gitRevision, preregistrationSHA256: preregistrationSHA256, sources: sources,
                              renderings: renderings, chevronTemplate: chevronRecord, kInputs: kInputs, items: records,
                              unreachable: unreachable)
    }
}

public enum CorpusCheck {
    /// The oracle on one item: every helper template at the item's scale
    /// (none for K items, D18), the chevron template at scale 2 only (D17).
    public static func label(_ item: CorpusItem, templates: CorpusTemplates) throws -> CaptureLabels {
        let helpers = item.spec.expected.helpers == nil ? [] : try templates.helpers(scale: item.spec.scale)
        let chevron = item.spec.scale == 2 ? templates.chevron : nil
        return try Oracle.label(image: item.image, helpers: helpers, chevron: chevron, context: item.context)
    }

    /// D25: class, zone, helper exact; x within 2 pt; S9 by inconclusive alone.
    public static func mismatches(_ expected: Expectation, _ got: CaptureLabels, tolerancePt: Double = OracleParameters.preRegistered.positionTolerancePt) -> [String] {
        if expected.inconclusive {
            return got.isInconclusive ? [] : ["expected inconclusive, got conclusive"]
        }
        var problems = [String]()
        if got.isInconclusive { problems.append("inconclusive: \(got.inconclusive)") }
        if got.chevron != expected.chevron { problems.append("chevron: expected \(expected.chevron), got \(got.chevron)") }
        for (id, want) in (expected.helpers ?? [:]).sorted(by: { $0.key < $1.key }) {
            let have = got.labels[id] ?? HelperLabel.none
            if !agrees(want, have, tolerancePt: tolerancePt) { problems.append("\(id): expected \(want), got \(have)") }
        }
        return problems
    }

    static func agrees(_ want: ExpectedLabel, _ have: HelperLabel, tolerancePt: Double) -> Bool {
        switch (want, have) {
        case (.none, .none):
            return true
        case let (.drawn(classes, x, zone), .drawn(gotClass, gotX, gotZone)):
            return classes.contains(gotClass) && zone == gotZone && abs(x - gotX) <= tolerancePt
        default:
            return false
        }
    }
}
