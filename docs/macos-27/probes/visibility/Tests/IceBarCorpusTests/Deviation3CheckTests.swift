// Deviation 3 (docs/plans/2026-10-01-icebar-c-deviation3.md): D3.2's
// disjunction in the corpus check, and S14's regression on the development
// corpus (a cut chevron alone still yields `«`).
@testable import IceBarCorpus
import IceBarOracle
import IceCore
import Testing
import VZGlyphs

@Suite("Deviation 3 check")
struct Deviation3CheckTests {
    /// A cut `hook` at x0 1370 (2x), columns 2740..<2760 visible.
    let expected = Expectation(
        helpers: ["hook": .none, "tee": .none], requiredSightings: ["hook": [2740, 2760]],
        cutIdentity: ["hook": .drawn([.full], xPt: 1371.5, zone: .rightOfReferences)],
        placedColumns: [[2740, 2760]], seesMember: .yes, inconclusive: false, chevron: .absent
    )

    func verdict(_ labels: CaptureLabels) -> AttemptVerdict {
        AttemptVerdict.evaluate(captures: [labels], reads: [], barHeightPt: 32, members: ["hook", "tee"], visible: [], overlap: .clear)
    }

    @Test("the cut glyph identified as itself within 2 pt meets its expectation")
    func sameGlyphFull() {
        let labels = CaptureLabels(labels: ["hook": .drawn(.full, xPt: 1370.5, zone: .rightOfReferences), "tee": .none], matches: [:],
                                   sightings: [], inconclusive: [], chevron: .absent)
        #expect(CorpusCheck.exactProblems(expected, labels: labels, verdict: verdict(labels)).isEmpty)
    }

    @Test("an unexplained sighting over the cut glyph meets its expectation")
    func sighting() {
        let labels = CaptureLabels(labels: ["hook": .none, "tee": .none], matches: [:],
                                   sightings: [Sighting(templateID: "tee", xPx: 2742, yPx: 20, width: 24, matchClass: .partial, explained: false)],
                                   inconclusive: [], chevron: .absent)
        #expect(CorpusCheck.exactProblems(expected, labels: labels, verdict: verdict(labels)).isEmpty)
    }

    @Test("another helper identified, or neither identity nor sighting, fails")
    func failures() {
        let other = CaptureLabels(labels: ["hook": .none, "tee": .drawn(.full, xPt: 1371.5, zone: .rightOfReferences)], matches: [:],
                                  sightings: [], inconclusive: [], chevron: .absent)
        #expect(!CorpusCheck.exactProblems(expected, labels: other, verdict: verdict(other)).isEmpty)
        let neither = CaptureLabels(labels: ["hook": .none, "tee": .none], matches: [:], sightings: [], inconclusive: [], chevron: .absent)
        #expect(!CorpusCheck.exactProblems(expected, labels: neither, verdict: verdict(neither)).isEmpty)
        let far = CaptureLabels(labels: ["hook": .drawn(.full, xPt: 1374, zone: .rightOfReferences), "tee": .none], matches: [:],
                                sightings: [], inconclusive: [], chevron: .absent)
        #expect(!CorpusCheck.exactProblems(expected, labels: far, verdict: verdict(far)).isEmpty)
    }

    @Test("S14 on the development corpus: every case yields `«` present and meets its expectation")
    func s14Regression() throws {
        let templates = try CorpusTemplates(kDirectory: KCaptures.directory)
        let specs = try ItemBuilder(templates: templates, scale: 2, salt: "dev").s14()
        #expect(specs.count == 3)
        for spec in specs {
            let item = try CorpusRenderer.render(spec, templates: templates)
            #expect(try CorpusCheck.label(item, templates: templates).chevron == .present, "\(spec.id)")
            #expect(try CorpusCheck.problems(item, templates: templates).isEmpty, "\(spec.id)")
        }
    }
}
