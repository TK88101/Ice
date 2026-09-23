// Pixels.locate tests, with their locate-only pattern/template/strip
// fixtures.
import Testing
@testable import SafeWidthCore

// MARK: - locate

/// Builds a distinct, non-repeating pixel pattern so matches can't happen by accident.
private func patternPixel(_ x: Int, _ y: Int) -> RGBA {
    RGBA(UInt8((50 + x * 7) % 256), UInt8((60 + y * 23) % 256), UInt8((70 + x + y * 5) % 256))
}

private func templateBitmap(width: Int, height: Int, scale: Double) -> Bitmap {
    var rows: [[RGBA]] = []
    for y in 0..<height {
        rows.append((0..<width).map { patternPixel($0, y) })
    }
    return makeBitmap(rows, scale: scale)
}

/// A full strip filled with `background`, with the template pattern stamped at
/// column `stampAt` (top-left), for `width`/`height` matching the template.
private func stripWithStamp(stripWidth: Int, height: Int, scale: Double, stampAt: Int, templateWidth: Int) -> Bitmap {
    var rows: [[RGBA]] = []
    for y in 0..<height {
        var row = Array(repeating: bg, count: stripWidth)
        for x in 0..<templateWidth {
            row[stampAt + x] = patternPixel(x, y)
        }
        rows.append(row)
    }
    return makeBitmap(rows, scale: scale)
}

@Test func locate_foundAtOffsetZero() {
    let scale = 2.0
    let templateWidth = 4, height = 2
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    let originX = 5.0 // originPx = 10
    let strip = stripWithStamp(stripWidth: 30, height: height, scale: scale, stampAt: 10, templateWidth: templateWidth)
    let itemTemplate = ItemTemplate(id: "a", originX: originX, bitmap: template)

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 5, channelTolerance: 0, maxMismatch: 0.0)

    #expect(result == .found(offset: 0.0))
}

@Test func locate_foundAtPositiveOffset() {
    let scale = 2.0
    let templateWidth = 4, height = 2
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    let originX = 5.0 // originPx = 10, +3pt = +6px -> stamp at 16
    let strip = stripWithStamp(stripWidth: 30, height: height, scale: scale, stampAt: 16, templateWidth: templateWidth)
    let itemTemplate = ItemTemplate(id: "a", originX: originX, bitmap: template)

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 5, channelTolerance: 0, maxMismatch: 0.0)

    #expect(result == .found(offset: 3.0))
}

@Test func locate_foundAtNegativeOffset() {
    let scale = 2.0
    let templateWidth = 4, height = 2
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    let originX = 10.0 // originPx = 20, -3pt = -6px -> stamp at 14
    let strip = stripWithStamp(stripWidth: 30, height: height, scale: scale, stampAt: 14, templateWidth: templateWidth)
    let itemTemplate = ItemTemplate(id: "a", originX: originX, bitmap: template)

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 5, channelTolerance: 0, maxMismatch: 0.0)

    #expect(result == .found(offset: -3.0))
}

@Test func locate_notFound_reportsBestMismatch() {
    let scale = 2.0
    let templateWidth = 4, height = 2
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    // Strip is uniform background everywhere; template pattern never appears,
    // so every candidate mismatches on every pixel.
    var rows: [[RGBA]] = []
    for _ in 0..<height { rows.append(Array(repeating: bg, count: 30)) }
    let strip = makeBitmap(rows, scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 5.0, bitmap: template)

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 5, channelTolerance: 0, maxMismatch: 0.1)

    #expect(result == .notFound(bestMismatch: 1.0))
}

@Test func locate_notFound_reportsBestAmongVaryingMismatches() {
    let scale = 2.0
    let templateWidth = 4, height = 1 // area = 4
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    // Candidate at d=+2 (col 12) mismatches on only 1 of 4 pixels (fraction
    // 0.25); every other reachable candidate is pure background (fraction
    // 1.0). A mutant reporting the WORST mismatch instead of the best would
    // report 1.0 here instead of 0.25.
    var row = Array(repeating: bg, count: 30)
    row[12] = patternPixel(0, 0)
    row[13] = patternPixel(1, 0)
    row[14] = patternPixel(2, 0)
    row[15] = RGBA(255, 255, 255) // deliberately not patternPixel(3, 0)
    let strip = makeBitmap([row], scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 5.0, bitmap: template) // originPx = 10

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 2, channelTolerance: 0, maxMismatch: 0.1)

    #expect(result == .notFound(bestMismatch: 0.25))
}

@Test func locate_tieBreak_prefersSmallerAbsoluteOffset() {
    let scale = 2.0
    let templateWidth = 4, height = 2
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    // originPx = 10. Stamp an exact match at both -2px (col 8) and +2px (col 12);
    // stamping overwrites cols 8-15 combined since they overlap in this small width,
    // so instead stamp them far enough apart but both still exact matches.
    var rows: [[RGBA]] = []
    for y in 0..<height {
        var row = Array(repeating: bg, count: 30)
        for x in 0..<templateWidth {
            row[8 + x] = patternPixel(x, y)  // -2px offset, i.e. -1pt
            row[12 + x] = patternPixel(x, y) // +2px offset, i.e. +1pt
        }
        rows.append(row)
    }
    let strip = makeBitmap(rows, scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 5.0, bitmap: template)

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 5, channelTolerance: 0, maxMismatch: 0.0)

    #expect(result == .found(offset: -1.0))
}

@Test func locate_tieBreak_prefersZeroOverNonZero() {
    let scale = 2.0
    let templateWidth = 4, height = 2
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    // originPx = 10. Exact matches at d=0 (cols 10-13) and d=-4px=-2pt (cols
    // 6-9), written in separate, non-overlapping loops so neither stamp
    // overwrites the other — a genuine tie in mismatch count (both 0) between
    // offset 0 and a nonzero offset.
    var rows: [[RGBA]] = []
    for y in 0..<height {
        var row = Array(repeating: bg, count: 30)
        for x in 0..<templateWidth { row[10 + x] = patternPixel(x, y) }
        for x in 0..<templateWidth { row[6 + x] = patternPixel(x, y) }
        rows.append(row)
    }
    let strip = makeBitmap(rows, scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 5.0, bitmap: template)

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 5, channelTolerance: 0, maxMismatch: 0.0)

    #expect(result == .found(offset: 0.0))
}

@Test func locate_offsetsOutsideBitmap_areSkipped() {
    let scale = 2.0
    let templateWidth = 6, height = 2
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    // Strip is only 10px wide. originPx would be 10 (originX=5pt), which alone
    // already leaves no room (10+6 > 10), so only smaller (negative) offsets fit.
    // Stamp the exact pattern at the only valid location: x0 = 4 (d = -6px = -3pt).
    var rows: [[RGBA]] = []
    for y in 0..<height {
        var row = Array(repeating: bg, count: 10)
        for x in 0..<templateWidth { row[4 + x] = patternPixel(x, y) }
        rows.append(row)
    }
    let strip = makeBitmap(rows, scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 5.0, bitmap: template)

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 5, channelTolerance: 0, maxMismatch: 0.0)

    #expect(result == .found(offset: -3.0))
}

@Test func locate_channelTolerance_absorbsSmallNoise() {
    let scale = 2.0
    let templateWidth = 4, height = 2
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    var rows: [[RGBA]] = []
    for y in 0..<height {
        var row = Array(repeating: bg, count: 30)
        for x in 0..<templateWidth {
            let p = patternPixel(x, y)
            row[10 + x] = RGBA(p.r &+ 2, p.g &- 2, p.b &+ 1) // small noise, within tolerance 5
        }
        rows.append(row)
    }
    let strip = makeBitmap(rows, scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 5.0, bitmap: template)

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 5, channelTolerance: 5, maxMismatch: 0.0)

    #expect(result == .found(offset: 0.0))
}

@Test func locate_maxMismatchThreshold_honouredAtBoundary() {
    let scale = 2.0
    let templateWidth = 4, height = 1 // area = 4
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    // Stamp 3 of 4 pixels matching, 1 pixel very different -> mismatch fraction 0.25.
    var row = Array(repeating: bg, count: 30)
    for x in 0..<templateWidth { row[10 + x] = patternPixel(x, 0) }
    row[10] = RGBA(255, 255, 255) // force a mismatch in the first pixel
    let strip = makeBitmap([row], scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 5.0, bitmap: template)

    let atBoundary = Pixels.locate(itemTemplate, in: strip, searchRadius: 0, channelTolerance: 0, maxMismatch: 0.25)
    #expect(atBoundary == .found(offset: 0.0))

    let belowBoundary = Pixels.locate(itemTemplate, in: strip, searchRadius: 0, channelTolerance: 0, maxMismatch: 0.24)
    #expect(belowBoundary == .notFound(bestMismatch: 0.25))
}

@Test func locate_zeroAreaTemplate_hasZeroMismatchAtEveryCandidate() {
    let scale = 2.0
    // A zero-width template: mismatch must be defined as 0 everywhere, and the
    // usual tie-break (prefer offset 0) still picks the baseline position.
    let template = makeBitmap([[], []], scale: scale)
    let strip = makeBitmap([bgRow(10), bgRow(10)], scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 2.5, bitmap: template) // originPx = 5

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 1.5, channelTolerance: 0, maxMismatch: 0.0)

    #expect(result == .found(offset: 0.0))
}

@Test func locate_negativeSearchRadius_isNotFoundWithMismatchOne() {
    let scale = 2.0
    let template = templateBitmap(width: 4, height: 2, scale: scale)
    let strip = stripWithStamp(stripWidth: 30, height: 2, scale: scale, stampAt: 10, templateWidth: 4)
    let itemTemplate = ItemTemplate(id: "a", originX: 5.0, bitmap: template)

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: -1.0, channelTolerance: 0, maxMismatch: 1.0)

    #expect(result == .notFound(bestMismatch: 1.0))
}

@Test func locate_matchAtLeftEdgeOfBitmap_isFound() {
    let scale = 2.0
    let templateWidth = 4, height = 1
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    // originPx = 4; exact match stamped flush against the bitmap's left edge
    // (x0 = 0), i.e. offset d = -4px = -2pt.
    var row = Array(repeating: bg, count: 10)
    for x in 0..<templateWidth { row[x] = patternPixel(x, 0) }
    let strip = makeBitmap([row], scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 2.0, bitmap: template)

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 3.0, channelTolerance: 0, maxMismatch: 0.0)

    #expect(result == .found(offset: -2.0))
}

@Test func locate_mismatchUsesMaxOverChannels_notSum() {
    let scale = 2.0
    let templateColour = RGBA(100, 100, 100)
    let template = makeBitmap([[templateColour]], scale: scale)
    // Strip pixel differs by 3 on every channel: max diff 3 <= tolerance 5
    // (a match), but the sum of diffs is 9 > 5 (would mismatch under a
    // sum-based mutant).
    var row = bgRow(10)
    row[5] = RGBA(103, 103, 103)
    let strip = makeBitmap([row], scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 2.5, bitmap: template) // originPx = 5

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 0, channelTolerance: 5, maxMismatch: 0.0)

    #expect(result == .found(offset: 0.0))
}

@Test func locate_alphaIgnored_matchesDespiteDifferentAlpha() {
    let scale = 2.0
    let templateColour = RGBA(100, 100, 100, 255)
    let template = makeBitmap([[templateColour]], scale: scale)
    var row = bgRow(10)
    row[5] = RGBA(100, 100, 100, 10) // same rgb, very different alpha
    let strip = makeBitmap([row], scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 2.5, bitmap: template) // originPx = 5

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 0, channelTolerance: 0, maxMismatch: 0.0)

    #expect(result == .found(offset: 0.0))
}

@Test func locate_channelToleranceBoundary_matchesAtExactDiff_mismatchesJustAbove() {
    let scale = 2.0
    let templateColour = RGBA(100, 100, 100)
    let template = makeBitmap([[templateColour]], scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 2.5, bitmap: template) // originPx = 5

    var matchRow = bgRow(10)
    matchRow[5] = RGBA(105, 100, 100) // diff of exactly 5 on r
    let matchStrip = makeBitmap([matchRow], scale: scale)
    let atBoundary = Pixels.locate(itemTemplate, in: matchStrip, searchRadius: 0, channelTolerance: 5, maxMismatch: 0.0)
    #expect(atBoundary == .found(offset: 0.0))

    var mismatchRow = bgRow(10)
    mismatchRow[5] = RGBA(106, 100, 100) // diff of 6 on r, one over tolerance
    let mismatchStrip = makeBitmap([mismatchRow], scale: scale)
    let justAbove = Pixels.locate(itemTemplate, in: mismatchStrip, searchRadius: 0, channelTolerance: 5, maxMismatch: 0.0)
    #expect(justAbove == .notFound(bestMismatch: 1.0))
}

@Test func locate_originAndRadiusRounding_withFractionalPxValues() {
    let scale = 2.0
    let templateWidth = 2, height = 1
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    // originX = 5.25pt -> originPx = round(10.5) = 11.
    // searchRadius = 1.75pt -> radiusPx = floor(3.5) = 3, so d ranges -3...3 (x0 in 8...14).
    let originX = 5.25
    let searchRadius = 1.75
    let itemTemplate = ItemTemplate(id: "a", originX: originX, bitmap: template)

    // Exact match placed at x0 = 11 (d = 0 under the correct originPx). Under
    // a truncating originPx bug (Int(10.5) = 10), this would be read as d = 1.
    var originRows: [[RGBA]] = []
    for y in 0..<height {
        var row = Array(repeating: bg, count: 20)
        for x in 0..<templateWidth { row[11 + x] = patternPixel(x, y) }
        originRows.append(row)
    }
    let originStrip = makeBitmap(originRows, scale: scale)
    let originResult = Pixels.locate(itemTemplate, in: originStrip, searchRadius: searchRadius, channelTolerance: 0, maxMismatch: 0.0)
    #expect(originResult == .found(offset: 0.0))

    // Exact match placed only at x0 = 15 (d = +4), one px beyond the correct
    // radiusPx = 3. A `.rounded()` bug (giving radiusPx = 4) would find this;
    // the correct `.rounded(.down)` must not.
    var radiusRows: [[RGBA]] = []
    for y in 0..<height {
        var row = Array(repeating: bg, count: 20)
        for x in 0..<templateWidth { row[15 + x] = patternPixel(x, y) }
        radiusRows.append(row)
    }
    let radiusStrip = makeBitmap(radiusRows, scale: scale)
    let radiusResult = Pixels.locate(itemTemplate, in: radiusStrip, searchRadius: searchRadius, channelTolerance: 0, maxMismatch: 0.0)
    #expect(radiusResult == .notFound(bestMismatch: 1.0))
}

@Test func locate_largeSearchRadius_boundedByBitmapNotRadius() {
    let scale = 2.0
    let templateWidth = 4, height = 1
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    let strip = stripWithStamp(stripWidth: 30, height: height, scale: scale, stampAt: 10, templateWidth: templateWidth)
    let itemTemplate = ItemTemplate(id: "a", originX: 5.0, bitmap: template)

    // searchRadius is far larger than the bitmap could ever use; the
    // candidate range must be clamped to what the bitmap can hold rather than
    // iterating a number of candidates proportional to the radius.
    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 100_000, channelTolerance: 0, maxMismatch: 0.0)

    #expect(result == .found(offset: 0.0))
}

@Test func locate_nonFiniteInputs_areNotFoundWithoutTrapping() {
    let scale = 2.0
    let template = templateBitmap(width: 4, height: 2, scale: scale)
    let strip = stripWithStamp(stripWidth: 30, height: 2, scale: scale, stampAt: 10, templateWidth: 4)
    let itemTemplate = ItemTemplate(id: "a", originX: 5.0, bitmap: template)

    #expect(Pixels.locate(itemTemplate, in: strip, searchRadius: .infinity, channelTolerance: 0, maxMismatch: 1.0) == .notFound(bestMismatch: 1.0))
    #expect(Pixels.locate(itemTemplate, in: strip, searchRadius: .nan, channelTolerance: 0, maxMismatch: 1.0) == .notFound(bestMismatch: 1.0))

    let nanOriginTemplate = ItemTemplate(id: "a", originX: .nan, bitmap: template)
    #expect(Pixels.locate(nanOriginTemplate, in: strip, searchRadius: 5, channelTolerance: 0, maxMismatch: 1.0) == .notFound(bestMismatch: 1.0))
}

@Test func locate_noCandidate_reportsNotFoundWithMismatchOne() {
    let scale = 2.0
    let templateWidth = 4, height = 2
    let template = templateBitmap(width: templateWidth, height: height, scale: scale)
    // originX so large that originPx + width always exceeds a small strip, even
    // with radius 0 (the only candidate d=0 is invalid).
    let strip = makeBitmap([bgRow(6), bgRow(6)], scale: scale)
    let itemTemplate = ItemTemplate(id: "a", originX: 10.0, bitmap: template) // originPx = 20

    let result = Pixels.locate(itemTemplate, in: strip, searchRadius: 0, channelTolerance: 0, maxMismatch: 1.0)

    #expect(result == .notFound(bestMismatch: 1.0))
}
