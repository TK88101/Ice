// Pixels.count and Pixels.unusedColours tests.
import Testing
@testable import SafeWidthCore

// MARK: - count

@Test func count_insideSpan_countsMatchingPixels() {
    // width 10, scale 2. span pt [1.0, 3.0] -> cols [2, 6).
    let matchColour = RGBA(5, 5, 5)
    var row = bgRow(10)
    row[2] = matchColour
    row[3] = matchColour
    row[5] = matchColour // col 4 is not a match
    row[6] = matchColour // just past the half-open upper bound; must not be counted
    let bitmap = makeBitmap([row, row], scale: 2)
    let colour = ColorMatch(center: matchColour, tolerance: 0)

    let total = Pixels.count(colour, in: bitmap, span: Span(lo: 1.0, hi: 3.0))

    #expect(total == 6) // 3 matches per row (cols 2, 3, 5) * 2 rows; col 6 excluded
}

@Test func count_fractionalSpan_usesFloorAndCeilNotRounding() {
    // width 10, scale 2. span pt [1.25, 2.25] -> floor(2.5)=2, ceil(4.5)=5 -> cols [2, 5).
    // A mutant using .rounded() for the lower bound would give col 3 instead of 2.
    let matchColour = RGBA(5, 5, 5)
    var row = bgRow(10)
    row[2] = matchColour
    row[4] = matchColour
    row[5] = matchColour // outside [2, 5); must not be counted
    let bitmap = makeBitmap([row], scale: 2)
    let colour = ColorMatch(center: matchColour, tolerance: 0)

    let total = Pixels.count(colour, in: bitmap, span: Span(lo: 1.25, hi: 2.25))

    #expect(total == 2) // cols 2 and 4 only
}

@Test func count_clampsAtBothEdges() {
    let matchColour = RGBA(5, 5, 5)
    let bitmap = makeBitmap([run(matchColour, 10)], scale: 2)
    let colour = ColorMatch(center: matchColour, tolerance: 0)

    // span far exceeds bitmap bounds on both sides -> clamp to [0, 10)
    let total = Pixels.count(colour, in: bitmap, span: Span(lo: -50.0, hi: 50.0))

    #expect(total == 10)
}

@Test func count_clampsLowEdgeOnly() {
    // span's lo is negative (before the bitmap), hi is within range.
    let matchColour = RGBA(5, 5, 5)
    var row = bgRow(10)
    row[0] = matchColour
    row[2] = matchColour
    let bitmap = makeBitmap([row], scale: 2)
    let colour = ColorMatch(center: matchColour, tolerance: 0)

    // lo = -5 clamps to col 0; hi = 1.5 -> ceil(3) = col 3. cols [0, 3).
    let total = Pixels.count(colour, in: bitmap, span: Span(lo: -5.0, hi: 1.5))

    #expect(total == 2) // cols 0 and 2
}

@Test func count_clampsHighEdgeOnly() {
    // span's hi is beyond the bitmap, lo is within range.
    let matchColour = RGBA(5, 5, 5)
    var row = bgRow(10)
    row[8] = matchColour
    row[9] = matchColour
    let bitmap = makeBitmap([row], scale: 2)
    let colour = ColorMatch(center: matchColour, tolerance: 0)

    // lo = 4.0 -> floor(8) = col 8; hi = 50 clamps to col 10. cols [8, 10).
    let total = Pixels.count(colour, in: bitmap, span: Span(lo: 4.0, hi: 50.0))

    #expect(total == 2) // cols 8 and 9
}

@Test func count_outOfRangeSpan_isZero() {
    let matchColour = RGBA(5, 5, 5)
    let bitmap = makeBitmap([run(matchColour, 10)], scale: 2)
    let colour = ColorMatch(center: matchColour, tolerance: 0)

    // span entirely before the bitmap (5pt wide, not empty) -> clamps to an empty range.
    let total = Pixels.count(colour, in: bitmap, span: Span(lo: -10.0, hi: -5.0))

    #expect(total == 0)
}

@Test func count_zeroWidthSpan_isZero() {
    // lo == hi: a genuinely empty span must return 0 even though floor/ceil
    // could otherwise pick up the fractional pixel straddling the point.
    let matchColour = RGBA(5, 5, 5)
    var row = bgRow(10)
    row[2] = matchColour // would be included by floor(2.5)=2..<ceil(2.5)=3 if not guarded
    let bitmap = makeBitmap([row], scale: 2)
    let colour = ColorMatch(center: matchColour, tolerance: 0)

    let total = Pixels.count(colour, in: bitmap, span: Span(lo: 1.25, hi: 1.25))

    #expect(total == 0)
}

@Test func count_zeroWidthSpanAtIntegerBoundary_isZero() {
    let matchColour = RGBA(5, 5, 5)
    var row = bgRow(10)
    row[2] = matchColour
    let bitmap = makeBitmap([row], scale: 2)
    let colour = ColorMatch(center: matchColour, tolerance: 0)

    let total = Pixels.count(colour, in: bitmap, span: Span(lo: 1.0, hi: 1.0))

    #expect(total == 0)
}

// MARK: - unusedColours

@Test func unusedColours_filtersOutUsedColours_keepsOrder() {
    let a = RGBA(255, 0, 0)
    let b = RGBA(0, 255, 0)
    let c = RGBA(0, 0, 255)
    let bitmap = makeBitmap([[a, bg, c]], scale: 2)

    let result = Pixels.unusedColours([c, b, a], tolerance: 0, in: [bitmap])

    #expect(result == [b])
}

@Test func unusedColours_allUnused_keepsInputOrder() {
    let x = RGBA(1, 2, 3)
    let y = RGBA(4, 5, 6)
    let z = RGBA(7, 8, 9)
    let bitmap = makeBitmap([[bg, bg]], scale: 2)

    let result = Pixels.unusedColours([x, y, z], tolerance: 0, in: [bitmap])

    #expect(result == [x, y, z])
}

@Test func unusedColours_emptyBitmapsList_returnsAllCandidates() {
    let a = RGBA(255, 0, 0)
    let b = RGBA(0, 255, 0)

    let result = Pixels.unusedColours([a, b], tolerance: 0, in: [])

    #expect(result == [a, b])
}

@Test func unusedColours_toleranceFiltersNearbyColours() {
    let candidate = RGBA(100, 100, 100)
    let justInside = RGBA(103, 100, 100) // diff 3, tolerance 3 -> within
    let justOutside = RGBA(104, 100, 100) // diff 4, tolerance 3 -> outside

    let insideBitmap = makeBitmap([[justInside]], scale: 2)
    #expect(Pixels.unusedColours([candidate], tolerance: 3, in: [insideBitmap]) == [])

    let outsideBitmap = makeBitmap([[justOutside]], scale: 2)
    #expect(Pixels.unusedColours([candidate], tolerance: 3, in: [outsideBitmap]) == [candidate])
}

@Test func unusedColours_checksAllBitmapsNotJustFirst() {
    let a = RGBA(255, 0, 0)
    let firstBitmap = makeBitmap([[bg]], scale: 2)
    let secondBitmap = makeBitmap([[a]], scale: 2)

    let result = Pixels.unusedColours([a], tolerance: 0, in: [firstBitmap, secondBitmap])

    #expect(result == [])
}

@Test func unusedColours_alphaIgnored_filtersColourWithDifferentAlpha() {
    let candidate = RGBA(255, 0, 0, 255)
    let capturedWithDifferentAlpha = RGBA(255, 0, 0, 0)
    let bitmap = makeBitmap([[capturedWithDifferentAlpha]], scale: 2)

    let result = Pixels.unusedColours([candidate], tolerance: 0, in: [bitmap])

    #expect(result == [])
}
