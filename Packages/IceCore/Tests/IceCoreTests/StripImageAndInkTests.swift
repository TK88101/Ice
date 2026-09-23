import Testing
@testable import IceCore

@Suite("StripImage and BarGeometry")
struct StripImageTests {
    @Test("a pixel is read back where it was written, top row first")
    func pixelRoundTrip() {
        var canvas = Canvas(widthPt: 4, heightPt: 2, scale: 2)
        canvas.set(x: 7, y: 3, Paint.white)
        let image = canvas.image
        #expect(image.pixel(x: 7, y: 3) == Paint.white)
        #expect(image.pixel(x: 0, y: 0) == Paint.darkBar)
        #expect(image.width == 8 && image.height == 4 && image.scale == 2)
    }

    @Test("points and pixels convert through the scale")
    func pointPixelConversion() {
        let geometry = Canvas(widthPt: 100, heightPt: 12, scale: 2).geometry()
        #expect(geometry.widthPx == 200)
        #expect(geometry.heightPx == 24)
        #expect(geometry.pt(fromPx: 21) == 10.5)
    }

    @Test("a template span that touches the notch is not searchable; one beside it is")
    func notchExclusion() {
        let geometry = Canvas(widthPt: 100, heightPt: 12, scale: 2).geometry(notch: PtSpan(lo: 40, hi: 60))
        // Notch covers px [80, 120).
        #expect(geometry.allowsSpan(fromPx: 70, widthPx: 10))
        #expect(!geometry.allowsSpan(fromPx: 71, widthPx: 10))
        #expect(!geometry.allowsSpan(fromPx: 100, widthPx: 4))
        #expect(!geometry.allowsSpan(fromPx: 119, widthPx: 4))
        #expect(geometry.allowsSpan(fromPx: 120, widthPx: 4))
        #expect(!geometry.allowsSpan(fromPx: 197, widthPx: 4)) // past the right edge
        #expect(!geometry.allowsSpan(fromPx: -1, widthPx: 4))
    }

    @Test("without a notch every in-range span is searchable")
    func noNotch() {
        let geometry = Canvas(widthPt: 100, heightPt: 12, scale: 2).geometry()
        #expect(geometry.allowsSpan(fromPx: 0, widthPx: 200))
        #expect(!geometry.allowsSpan(fromPx: 0, widthPx: 201))
    }

    @Test("PtSpan overlap is strict: touching edges do not overlap")
    func spanOverlap() {
        #expect(PtSpan(lo: 0, hi: 10).overlaps(PtSpan(lo: 9.5, hi: 12)))
        #expect(!PtSpan(lo: 0, hi: 10).overlaps(PtSpan(lo: 10, hi: 12)))
        #expect(PtSpan(lo: 0, hi: 10).contains(10))
    }
}

@Suite("Ink")
struct InkTests {
    let params = DetectorParameters.preRegistered

    @Test("a dark bar is drawn in white ink")
    func darkBarWhiteInk() {
        var canvas = Canvas(backdrop: Paint.darkBar)
        canvas.draw(.flag, atPt: 150)
        let ink = Ink.calibrated(from: canvas.image, geometry: canvas.geometry(), glyphFrames: [PtSpan(lo: 150, hi: 155)], parameters: params)
        #expect(ink?.isInk(Paint.white) == true)
        #expect(ink?.isInk(Paint.darkBar) == false)
    }

    @Test("a light bar is drawn in black ink")
    func lightBarBlackInk() {
        var canvas = Canvas(backdrop: Paint.lightBar)
        canvas.draw(.flag, atPt: 150, colour: Paint.black)
        let ink = Ink.calibrated(from: canvas.image, geometry: canvas.geometry(), glyphFrames: [PtSpan(lo: 150, hi: 155)], parameters: params)
        #expect(ink?.isInk(Paint.black) == true)
        #expect(ink?.isInk(Paint.lightBar) == false)
    }

    @Test("a mid-tone bar is decided by the glyphs inside the frames, not the median")
    func midToneBarDecidedByGlyphs() {
        // Deviation 1: median luma 125 on a red bar with white glyphs.
        var canvas = Canvas(backdrop: Paint.midGrey)
        canvas.draw(.flag, atPt: 150)
        canvas.draw(.box, atPt: 170)
        let frames = [PtSpan(lo: 150, hi: 155), PtSpan(lo: 170, hi: 175)]
        let ink = Ink.calibrated(from: canvas.image, geometry: canvas.geometry(), glyphFrames: frames, parameters: params)
        #expect(ink?.isInk(Paint.white) == true)
        #expect(ink?.isInk(Paint.black) == false)
    }

    @Test("a mid-tone bar with no glyph in any frame yields no ink at all")
    func midToneWithoutGlyphs() {
        let canvas = Canvas(backdrop: Paint.midGrey)
        let ink = Ink.calibrated(from: canvas.image, geometry: canvas.geometry(), glyphFrames: [PtSpan(lo: 150, hi: 155)], parameters: params)
        #expect(ink == nil)
    }

    @Test("the notch is ignored when calibrating, even when it is most of the bar")
    func notchIgnoredInCalibration() {
        // A light bar whose notch (pure black) would drag the median below 128.
        var canvas = Canvas(widthPt: 200, backdrop: Paint.lightBar)
        canvas.fill(xPx: 0..<300, yPx: 0..<canvas.heightPx, Paint.black)
        canvas.draw(.flag, atPt: 170, colour: Paint.black)
        let geometry = canvas.geometry(notch: PtSpan(lo: 0, hi: 150))
        let ink = Ink.calibrated(from: canvas.image, geometry: geometry, glyphFrames: [PtSpan(lo: 170, hi: 175)], parameters: params)
        #expect(ink?.isInk(Paint.black) == true)
    }

    @Test("clearly background is farther than twice the tolerance from every ink colour")
    func clearlyBackground() {
        let white = Ink(colours: [ColorMatch(center: Paint.white, tolerance: 70)])
        #expect(white.isClearlyBackground(Paint.darkBar))
        #expect(white.isClearlyBackground(Paint.redBar)) // g and b far below 115
        #expect(!white.isClearlyBackground(RGBA(200, 200, 200))) // within 140: an edge
        #expect(!white.isClearlyBackground(Paint.white))
    }

    @Test("extra colours count as ink alongside the calibrated one")
    func extraColours() {
        let ink = Ink(colours: [ColorMatch(center: Paint.white, tolerance: 70)]).adding(ColorMatch(center: RGBA(0, 200, 0), tolerance: 30))
        #expect(ink.isInk(RGBA(10, 190, 10)))
        #expect(ink.isInk(Paint.white))
    }

    @Test("an ink map classifies every pixel once")
    func inkMap() {
        var canvas = Canvas(widthPt: 10, heightPt: 6)
        canvas.set(x: 3, y: 4, Paint.white)
        let map = Ink(colours: [ColorMatch(center: Paint.white, tolerance: 70)]).map(canvas.image)
        #expect(map[3, 4])
        #expect(!map[4, 4])
        #expect(map.width == 20 && map.height == 12)
    }
}
