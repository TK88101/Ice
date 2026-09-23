import Testing
@testable import IceCore

/// Cutting a template and searching for it. Both work on the trimap: where the
/// glyph's ink is, and where it clearly is not. The backdrop's colour is not
/// compared, because the bar is translucent over whatever window is under it and
/// that changed 17-23 % of the status area's pixels in 2 s on 2026-09-19.
@Suite("ItemTemplate.cut")
struct TemplateCutTests {
    let params = DetectorParameters.preRegistered
    let ink = Ink(colours: [ColorMatch(center: Paint.white, tolerance: 70)])

    func canvasWithFlag(backdrop: RGBA = Paint.darkBar) -> Canvas {
        var canvas = Canvas(backdrop: backdrop)
        canvas.draw(.flag, atPt: 150)
        return canvas
    }

    func frame(_ id: String = "target", minX: Double = 149, minY: Double = 0, width: Double = 7, height: Double = 12) -> ItemFrame {
        ItemFrame(id: id, minX: minX, minY: minY, width: width, height: height)
    }

    @Test("a cut is taken at the glyph's ink bounding box, not the whole frame")
    func cutAtInkBoundingBox() throws {
        let canvas = canvasWithFlag()
        let template = try #require(ItemTemplate.cut(frame(), from: canvas.image, ink: ink, geometry: canvas.geometry(), parameters: params).template)
        // The flag is 10 px wide from 300 px; the margin adds 2 px on each side.
        #expect(template.originXPt == 149)
        #expect(template.widthPx == 14)
        #expect(template.inkCount > 0 && template.backgroundCount > 0)
    }

    @Test("a frame below the bar is rejected: a parked item's frame is at y 1104")
    func parkedFrameRejected() {
        let canvas = canvasWithFlag()
        let result = ItemTemplate.cut(frame(minY: 1104), from: canvas.image, ink: ink, geometry: canvas.geometry(), parameters: params)
        #expect(result.rejection == .offBar)
    }

    @Test("a frame outside the strip or not finite is rejected")
    func outOfRangeFrameRejected() {
        let canvas = canvasWithFlag()
        let geometry = canvas.geometry()
        #expect(ItemTemplate.cut(frame(minX: 198, width: 10), from: canvas.image, ink: ink, geometry: geometry, parameters: params).rejection == .outsideStrip)
        #expect(ItemTemplate.cut(frame(minX: -1), from: canvas.image, ink: ink, geometry: geometry, parameters: params).rejection == .outsideStrip)
        #expect(ItemTemplate.cut(frame(minX: .nan), from: canvas.image, ink: ink, geometry: geometry, parameters: params).rejection == .nonFiniteFrame)
    }

    @Test("a frame narrower than the minimum is rejected")
    func narrowFrameRejected() {
        let canvas = canvasWithFlag()
        let result = ItemTemplate.cut(frame(minX: 150, width: 3), from: canvas.image, ink: ink, geometry: canvas.geometry(), parameters: params)
        #expect(result.rejection == .tooNarrow)
    }

    @Test("a frame with no ink in it is rejected")
    func noInkRejected() {
        let canvas = canvasWithFlag()
        let result = ItemTemplate.cut(frame(minX: 20, width: 10), from: canvas.image, ink: ink, geometry: canvas.geometry(), parameters: params)
        #expect(result.rejection == .noInk)
    }

    @Test("a glyph too thin to outweigh an empty slot is rejected")
    func thinGlyphRejected() {
        // Two lone pixels: an empty slot would mismatch by less than the threshold.
        var canvas = Canvas()
        canvas.draw(.thin, atPt: 150)
        let result = ItemTemplate.cut(frame(minX: 149, width: 8), from: canvas.image, ink: ink, geometry: canvas.geometry(), parameters: params)
        #expect(result.rejection == .tooLittleInk)
    }

    @Test("a cut that is almost all ink is rejected: drawn must rest on the surroundings too")
    func allInkRejected() {
        var canvas = Canvas()
        canvas.fill(xPx: 300..<320, yPx: 0..<24, Paint.white)
        let result = ItemTemplate.cut(frame(minX: 150, width: 10), from: canvas.image, ink: ink, geometry: canvas.geometry(), parameters: params)
        #expect(result.rejection == .tooLittleBackground)
    }

    @Test("a cut whose surroundings are neither ink nor clearly background is rejected")
    func edgeOnlySurroundingsRejected() {
        // A backdrop 100 levels from white: every non-glyph pixel is an edge.
        var canvas = Canvas(backdrop: RGBA(155, 155, 155))
        canvas.draw(.flag, atPt: 150)
        let result = ItemTemplate.cut(frame(), from: canvas.image, ink: ink, geometry: canvas.geometry(), parameters: params)
        #expect(result.rejection == .tooLittleBackground)
    }
}

@Suite("TemplateMatcher")
struct TemplateMatcherTests {
    let params = DetectorParameters.preRegistered
    let ink = Ink(colours: [ColorMatch(center: Paint.white, tolerance: 70)])

    /// A template of the flag glyph cut at 150 pt on a dark bar.
    func flagTemplate(id: String = "target") throws -> ItemTemplate {
        var canvas = Canvas()
        canvas.draw(.flag, atPt: 150)
        let frame = ItemFrame(id: id, minX: 149, minY: 0, width: 7, height: 12)
        return try #require(ItemTemplate.cut(frame, from: canvas.image, ink: ink, geometry: canvas.geometry(), parameters: params).template)
    }

    func match(_ template: ItemTemplate, in canvas: Canvas) -> Match {
        TemplateMatcher.match(template, in: ink.map(canvas.image), geometry: canvas.geometry(), parameters: params)
    }

    @Test("a glyph where it was baselined is a unique, strong match")
    func uniqueAtBaseline() throws {
        let template = try flagTemplate()
        var canvas = Canvas()
        canvas.draw(.flag, atPt: 150)
        guard case .unique(let x, let mismatch) = match(template, in: canvas) else {
            Issue.record("expected unique"); return
        }
        #expect(x == 149)
        #expect(mismatch == 0)
    }

    @Test("a glyph that moved is found where it moved to")
    func uniqueAfterMoving() throws {
        let template = try flagTemplate()
        var canvas = Canvas()
        canvas.draw(.flag, atPt: 170)
        guard case .unique(let x, let mismatch) = match(template, in: canvas) else {
            Issue.record("expected unique"); return
        }
        #expect(x == 169)
        #expect(mismatch <= params.maxMismatch)
    }

    @Test("the same glyph in two places cannot identify the item")
    func twinsAreAmbiguous() throws {
        let template = try flagTemplate()
        var canvas = Canvas()
        canvas.draw(.flag, atPt: 150)
        canvas.draw(.flag, atPt: 170)
        #expect(match(template, in: canvas) == .ambiguous(count: 2))
    }

    @Test("two glyphs a few pixels apart stay two: suppression never merges them")
    func suppressionIsNotTransitive() throws {
        let template = try flagTemplate()
        var canvas = Canvas()
        canvas.draw(.flag, atPt: 150)
        canvas.draw(.flag, atPt: 155.5) // 11 px apart, over the 2 px radius
        #expect(match(template, in: canvas) == .ambiguous(count: 2))
    }

    @Test("an empty bar is absent, and the best mismatch says how far off it was")
    func emptyBarIsAbsent() throws {
        let template = try flagTemplate()
        let canvas = Canvas()
        guard case .absent(let best) = match(template, in: canvas) else {
            Issue.record("expected absent"); return
        }
        #expect(best > params.foundThreshold)
    }

    @Test("a changed backdrop under a present glyph still reads as drawn")
    func backdropChangeDoesNotHideAGlyph() throws {
        // The measured case: the window under the translucent bar changed.
        let template = try flagTemplate()
        var canvas = Canvas(backdrop: Paint.redBar)
        canvas.draw(.flag, atPt: 150)
        guard case .unique(let x, let mismatch) = match(template, in: canvas) else {
            Issue.record("expected unique"); return
        }
        #expect(x == 149)
        #expect(mismatch <= params.maxMismatch)
    }

    @Test("a solid patch of ink over an empty slot is not the glyph: absent")
    func inkBackdropOverEmptySlotIsAbsent() {
        // Until the first live run, pass 2 asked only "is this glyph's ink
        // still here", and a patch like this answered yes. It now has to match
        // the glyph's negative space too, which a solid block cannot.
        let template = try! flagTemplate()
        var canvas = Canvas()
        canvas.fill(xPx: 294..<324, yPx: 0..<24, Paint.white)
        #expect({ if case .absent = match(template, in: canvas) { return true } else { return false } }())
    }

    @Test("a denser glyph elsewhere does not keep a hidden item from reading as gone")
    func densePatchElsewhereDoesNotBlockAbsence() throws {
        // MEASURED on the live run of 2026-09-19: with the old one-sided pass 2,
        // the helper's own ink was found inside another item's glyph and the
        // hidden helper read `weakMatch` for ever.
        let template = try flagTemplate()
        var canvas = Canvas()
        canvas.draw(.box, atPt: 60)      // another item, denser
        canvas.fill(xPx: 700..<740, yPx: 4..<20, Paint.white) // a filled badge
        #expect({ if case .absent = match(template, in: canvas) { return true } else { return false } }())
    }

    @Test("a glyph that lost some of its ink is weak, not gone")
    func partlyDimmedGlyphIsWeak() throws {
        let template = try flagTemplate()
        var canvas = Canvas()
        canvas.draw(.flag, atPt: 150)
        // Take out a third of the glyph's ink: over the decision layer's
        // tolerance, under pass 2's looser one.
        let toBreak = max(1, template.inkCount / 3)
        var broken = 0
        for y in 0..<canvas.heightPx where broken < toBreak {
            for x in 300..<312 where broken < toBreak {
                if canvas.image.pixel(x: x, y: y) == Paint.white {
                    canvas.set(x: x, y: y, Paint.darkBar)
                    broken += 1
                }
            }
        }
        guard case .unique(_, let mismatch) = match(template, in: canvas) else {
            Issue.record("expected a weak unique match"); return
        }
        #expect(mismatch > params.maxMismatch)
    }

    @Test("residual A, pinned: a backdrop that reproduces the glyph reads as drawn")
    func forgedGlyphReadsAsDrawn() throws {
        // Pixels cannot say who drew a pattern. The Accessibility veto in the
        // decision layer is what keeps this from becoming `restored`.
        let template = try flagTemplate()
        var canvas = Canvas()
        canvas.draw(.flag, atPt: 150) // stands in for a window drawing the same shape
        guard case .unique(_, let mismatch) = match(template, in: canvas) else {
            Issue.record("expected unique"); return
        }
        #expect(mismatch <= params.maxMismatch)
    }

    @Test("residual C, pinned: a glyph that loses most of its ink reads as absent")
    func dimmedGlyphReadsAsAbsent() throws {
        let template = try flagTemplate()
        var canvas = Canvas()
        canvas.draw(.flag, atPt: 150, colour: Paint.midGrey) // dimmed: no longer ink
        #expect({ if case .absent = match(template, in: canvas) { return true } else { return false } }())
    }

    @Test("the notch is never searched")
    func notchIsSkipped() throws {
        let template = try flagTemplate()
        var canvas = Canvas()
        canvas.draw(.flag, atPt: 50)
        let geometry = canvas.geometry(notch: PtSpan(lo: 40, hi: 70))
        let result = TemplateMatcher.match(template, in: ink.map(canvas.image), geometry: geometry, parameters: params)
        #expect({ if case .absent = result { return true } else { return false } }())
    }

    @Test("parameters that would let a weak match read as drawn are invalid")
    func parametersGuardTheWeakBand() {
        #expect(DetectorParameters(maxMismatch: 0.1, foundThreshold: 0.05).isValid == false)
        // Pass 2 must stay under the ink share a vacated slot mismatches by.
        #expect(DetectorParameters(weakThreshold: 0.16).isValid == false)
        #expect(DetectorParameters(weakThreshold: 0.07).isValid == false)
        #expect(DetectorParameters(suppressionRadiusPx: 2, minTemplateWidthPt: 4).isValid)
        #expect(DetectorParameters(suppressionRadiusPx: 3, minTemplateWidthPt: 4).isValid == false)
        #expect(DetectorParameters.preRegistered.isValid)
    }
}
