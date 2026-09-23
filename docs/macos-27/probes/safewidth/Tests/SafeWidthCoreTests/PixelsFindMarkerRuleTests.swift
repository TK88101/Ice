// Pixels.findMarker basic rules: span/scale conversion, absent cases,
// minRun, maxGap, minRows, and row grouping.
import Testing
@testable import SafeWidthCore

// MARK: - findMarker

@Test func findMarker_uniqueMarker_hasCorrectPointSpanAtScale2() {
    // Row: 2 bg, 3 left (cols 2-4), 3 right (cols 5-7), 6 bg. Same on both rows.
    let row = bgRow(2) + run(leftColour, 3) + run(rightColour, 3) + bgRow(6)
    let bitmap = makeBitmap([row, row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 1, minRows: 2
    )

    let result = Pixels.findMarker(spec, in: bitmap)

    guard case .unique(let span) = result else {
        Issue.record("expected unique, got \(result)")
        return
    }
    #expect(span.lo == 1.0)
    #expect(span.hi == 4.0)
}

@Test func findMarker_noPattern_isAbsent() {
    let bitmap = makeBitmap([bgRow(10), bgRow(10)], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 1, minRows: 1
    )

    #expect(Pixels.findMarker(spec, in: bitmap) == .absent)
}

@Test func findMarker_twoSeparateMarkers_areAmbiguousSortedByLo() {
    // cols: 0-1 bg, 2-4 left, 5 gap, 6-8 right, 9-13 bg, 14-16 left, 17 gap, 18-20 right, 21-22 bg
    let row = bgRow(2) + run(leftColour, 3) + bgRow(1) + run(rightColour, 3)
        + bgRow(5) + run(leftColour, 3) + bgRow(1) + run(rightColour, 3) + bgRow(2)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 1, minRows: 1
    )

    let result = Pixels.findMarker(spec, in: bitmap)

    guard case .ambiguous(let spans) = result else {
        Issue.record("expected ambiguous, got \(result)")
        return
    }
    #expect(spans.count == 2)
    #expect(spans[0].lo == 1.0)
    #expect(spans[0].hi == 4.5)
    #expect(spans[1].lo == 7.0)
    #expect(spans[1].hi == 10.5)
    #expect(spans[0].lo < spans[1].lo)
}

@Test func findMarker_leftColourAlone_isAbsent() {
    let row = bgRow(2) + run(leftColour, 3) + bgRow(5)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 5, minRows: 1
    )

    #expect(Pixels.findMarker(spec, in: bitmap) == .absent)
}

@Test func findMarker_rightColourAlone_isAbsent() {
    let row = bgRow(2) + run(rightColour, 3) + bgRow(1)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 5, minRows: 1
    )

    #expect(Pixels.findMarker(spec, in: bitmap) == .absent)
}

@Test func findMarker_leftRunShorterThanMinRun_isAbsent() {
    // Left run only 2 long (< minRun 4), then a fine right run.
    let row = bgRow(2) + run(leftColour, 2) + bgRow(1) + run(rightColour, 4) + bgRow(2)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 4, maxGap: 5, minRows: 1
    )

    #expect(Pixels.findMarker(spec, in: bitmap) == .absent)
}

@Test func findMarker_rightRunShorterThanMinRun_isAbsent() {
    // Right run only 2 long (< minRun 4), left run is fine.
    let row = bgRow(2) + run(leftColour, 4) + bgRow(1) + run(rightColour, 2) + bgRow(2)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 4, maxGap: 5, minRows: 1
    )

    #expect(Pixels.findMarker(spec, in: bitmap) == .absent)
}

@Test func findMarker_gapLargerThanMaxGap_isAbsent() {
    // left cols 2-4, gap of 2 (cols 5-6), right cols 7-9. gap=2 > maxGap=1.
    let row = bgRow(2) + run(leftColour, 3) + bgRow(2) + run(rightColour, 3) + bgRow(2)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 1, minRows: 1
    )

    #expect(Pixels.findMarker(spec, in: bitmap) == .absent)
}

@Test func findMarker_gapWithinMaxGap_isFound() {
    // left cols 2-4, gap of 2 (cols 5-6), right cols 7-9. gap=2 <= maxGap=2.
    let row = bgRow(2) + run(leftColour, 3) + bgRow(2) + run(rightColour, 3) + bgRow(2)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 2, minRows: 1
    )

    let result = Pixels.findMarker(spec, in: bitmap)
    guard case .unique(let span) = result else {
        Issue.record("expected unique, got \(result)")
        return
    }
    #expect(span.lo == 1.0) // 2/2
    #expect(span.hi == 5.0) // (9+1)/2
}

@Test func findMarker_gapOfZero_isFound() {
    // left cols 2-4, right immediately at col 5-7, gap=0.
    let row = bgRow(2) + run(leftColour, 3) + run(rightColour, 3) + bgRow(2)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 0, minRows: 1
    )

    let result = Pixels.findMarker(spec, in: bitmap)
    guard case .unique(let span) = result else {
        Issue.record("expected unique, got \(result)")
        return
    }
    #expect(span.lo == 1.0) // 2/2
    #expect(span.hi == 4.0) // (7+1)/2
}

@Test func findMarker_hitsOnFewerRowsThanMinRows_isAbsent() {
    let row0 = bgRow(2) + run(leftColour, 3) + run(rightColour, 3) + bgRow(6)
    let row1 = bgRow(6) + run(leftColour, 3) + run(rightColour, 3) + bgRow(2)
    let bitmap = makeBitmap([row0, row1], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 0, minRows: 3
    )

    #expect(Pixels.findMarker(spec, in: bitmap) == .absent)
}

@Test func findMarker_hitsOnOverlappingRows_mergeIntoOneGroup() {
    // row0 hit px[2,7], row1 hit px[6,11]; they overlap at cols 6-7.
    let row0 = bgRow(2) + run(leftColour, 3) + run(rightColour, 3) + bgRow(6)
    let row1 = bgRow(6) + run(leftColour, 3) + run(rightColour, 3) + bgRow(2)
    let bitmap = makeBitmap([row0, row1], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 0, minRows: 2
    )

    let result = Pixels.findMarker(spec, in: bitmap)
    guard case .unique(let span) = result else {
        Issue.record("expected unique, got \(result)")
        return
    }
    #expect(span.lo == 1.0)  // 2/2
    #expect(span.hi == 6.0)  // (11+1)/2
}

@Test func findMarker_twoLeftRunsShareOneRightRunOnSameRow_doesNotSatisfyMinRows() {
    // Two left runs on ONE row both resolve to the same right run, producing
    // two hits on that single row. minRows counts distinct rows, not hits, so
    // this must stay .absent even though there are 2 hits.
    let row = run(leftColour, 3) + bgRow(1) + run(leftColour, 3) + bgRow(1) + run(rightColour, 3)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 5, minRows: 2
    )

    #expect(Pixels.findMarker(spec, in: bitmap) == .absent)
}

@Test func findMarker_touchingButNonOverlappingRangesOnDifferentRows_areTwoGroups() {
    // row0 hit spans px[2,7]; row1 hit spans px[8,13] — they touch (7,8 are
    // adjacent) but share no column, so they must stay separate groups.
    let row0 = bgRow(2) + run(leftColour, 3) + run(rightColour, 3) + bgRow(6)
    let row1 = bgRow(8) + run(leftColour, 3) + run(rightColour, 3)
    let bitmap = makeBitmap([row0, row1], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 0, minRows: 1
    )

    let result = Pixels.findMarker(spec, in: bitmap)

    guard case .ambiguous(let spans) = result else {
        Issue.record("expected ambiguous (two separate groups), got \(result)")
        return
    }
    #expect(spans.count == 2)
    #expect(spans[0].lo == 1.0)
    #expect(spans[0].hi == 4.0)
    #expect(spans[1].lo == 4.0)
    #expect(spans[1].hi == 7.0)
}
