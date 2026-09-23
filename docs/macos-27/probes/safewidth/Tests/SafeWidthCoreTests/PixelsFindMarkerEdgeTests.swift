// Pixels.findMarker edge cases: transitive row chains, excluding
// spans, left-never-counts-as-right, first-qualifying-right-run,
// gaps containing non-qualifying runs, and markers touching the
// bitmap edges.
import Testing
@testable import SafeWidthCore

@Test func findMarker_transitiveChainAcrossNonAdjacentRows_mergesIntoOneGroup() {
    // Row0 hit px[0,5], row2 hit px[5,10], row4 hit px[10,15]: each only
    // touches its neighbour, so a comparison against only the first hit's end
    // would fail to merge row4's hit in. Rows are non-adjacent (0, 2, 4) to
    // also confirm grouping does not depend on row adjacency.
    let row0 = run(leftColour, 3) + run(rightColour, 3) + bgRow(10)
    let bgOnly = bgRow(16)
    let row2 = bgRow(5) + run(leftColour, 3) + run(rightColour, 3) + bgRow(5)
    let row4 = bgRow(10) + run(leftColour, 3) + run(rightColour, 3)
    let bitmap = makeBitmap([row0, bgOnly, row2, bgOnly, row4], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 0, minRows: 3
    )

    let result = Pixels.findMarker(spec, in: bitmap)

    guard case .unique(let span) = result else {
        Issue.record("expected unique, got \(result)")
        return
    }
    #expect(span.lo == 0.0)
    #expect(span.hi == 8.0) // (15+1)/2
}

@Test func findMarker_exclusion_dropsMatchWhoseMidIsInside_keepsOthers() {
    let row = bgRow(2) + run(leftColour, 3) + bgRow(1) + run(rightColour, 3)
        + bgRow(5) + run(leftColour, 3) + bgRow(1) + run(rightColour, 3) + bgRow(2)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 1, minRows: 1
    )
    // first span is lo:1.0 hi:4.5 mid:2.75 -> excluded by [2.0, 3.5]
    let excluding = [Span(lo: 2.0, hi: 3.5)]

    let result = Pixels.findMarker(spec, in: bitmap, excluding: excluding)

    guard case .unique(let span) = result else {
        Issue.record("expected unique, got \(result)")
        return
    }
    #expect(span.lo == 7.0)
    #expect(span.hi == 10.5)
}

@Test func findMarker_exclusion_overlappingButMidOutside_isKept() {
    let row = bgRow(2) + run(leftColour, 3) + bgRow(1) + run(rightColour, 3)
        + bgRow(5) + run(leftColour, 3) + bgRow(1) + run(rightColour, 3) + bgRow(2)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 1, minRows: 1
    )
    // first span [1.0, 4.5] mid 2.75; excluding [4.0, 10.0] overlaps this span
    // (shares [4.0, 4.5]) but does not contain its mid -> must be kept, not
    // dropped by an "any overlap" rule. Second span [7.0, 10.5] mid 8.75 is
    // genuinely inside the exclusion and is dropped either way.
    let excluding = [Span(lo: 4.0, hi: 10.0)]

    let result = Pixels.findMarker(spec, in: bitmap, excluding: excluding)

    guard case .unique(let span) = result else {
        Issue.record("expected unique (first span kept), got \(result)")
        return
    }
    #expect(span.lo == 1.0)
    #expect(span.hi == 4.5)
}

@Test func findMarker_exclusion_midExactlyAtExcludingUpperBound_isDropped() {
    let row = bgRow(2) + run(leftColour, 3) + bgRow(1) + run(rightColour, 3)
        + bgRow(5) + run(leftColour, 3) + bgRow(1) + run(rightColour, 3) + bgRow(2)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 1, minRows: 1
    )
    // first span [1.0, 4.5] has mid 2.75, exactly at excluding.hi -> Span.contains
    // is inclusive, so this must be dropped, not kept by a strict `<` boundary.
    let excluding = [Span(lo: 2.0, hi: 2.75)]

    let result = Pixels.findMarker(spec, in: bitmap, excluding: excluding)

    guard case .unique(let span) = result else {
        Issue.record("expected unique (second span kept), got \(result)")
        return
    }
    #expect(span.lo == 7.0)
    #expect(span.hi == 10.5)
}

@Test func findMarker_leftMatchNeverCountsAsRight_evenWhenColoursOverlap() {
    // left and right tolerance ranges overlap: a pixel at (198,0,0) matches
    // both. It must be classified purely as left, so it can never supply a
    // right run — there is no genuine right-only pixel on this row.
    let left = ColorMatch(center: RGBA(200, 0, 0), tolerance: 10)   // matches r in 190...210
    let right = ColorMatch(center: RGBA(195, 0, 0), tolerance: 10)  // matches r in 185...205
    let leftOnlyColour = RGBA(208, 0, 0)   // in left's range only
    let overlapColour = RGBA(198, 0, 0)    // in both ranges -> must count as left
    let row = bgRow(2) + run(leftOnlyColour, 3) + bgRow(1) + run(overlapColour, 3) + bgRow(2)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(left: left, right: right, minRun: 3, maxGap: 1, minRows: 1)

    #expect(Pixels.findMarker(spec, in: bitmap) == .absent)
}

@Test func findMarker_hitEndsAtFirstQualifyingRightRun_notTheLast() {
    // left run, then a qualifying right run, then a gap pixel, then another
    // qualifying right run further away. The hit must end at the FIRST right
    // run, not extend to the last one.
    let row = run(leftColour, 3) + run(rightColour, 3) + bgRow(1) + run(rightColour, 3)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 4, minRows: 1
    )

    let result = Pixels.findMarker(spec, in: bitmap)

    guard case .unique(let span) = result else {
        Issue.record("expected unique, got \(result)")
        return
    }
    // left cols 0-2, first right run cols 3-5 -> hi = (5+1)/2 = 3.0, not the
    // last right run's end (col 9 -> 5.0).
    #expect(span.lo == 0.0)
    #expect(span.hi == 3.0)
}

@Test func findMarker_gapContainingShortNonQualifyingRightRun_isStillFound() {
    // A short right run (length 2, below minRun 3) sits inside the gap before
    // the qualifying right run; it must count as ordinary gap pixels, not
    // block the match.
    let row = run(leftColour, 3) + run(rightColour, 2) + bgRow(1) + run(rightColour, 3)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 3, minRows: 1
    )

    let result = Pixels.findMarker(spec, in: bitmap)

    guard case .unique(let span) = result else {
        Issue.record("expected unique, got \(result)")
        return
    }
    #expect(span.lo == 0.0)
    #expect(span.hi == 4.5) // (8+1)/2
}

@Test func findMarker_gapContainingLeftColourPixel_isStillFound() {
    // A stray left-colour pixel sits inside the gap; gap pixels may be
    // anything that is not the start of a qualifying right run.
    let row = run(leftColour, 3) + bgRow(1) + run(leftColour, 1) + bgRow(1) + run(rightColour, 3)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 3, minRows: 1
    )

    let result = Pixels.findMarker(spec, in: bitmap)

    guard case .unique(let span) = result else {
        Issue.record("expected unique, got \(result)")
        return
    }
    #expect(span.lo == 0.0)
    #expect(span.hi == 4.5) // (8+1)/2
}

@Test func findMarker_markerTouchingBothEdges_isFound() {
    // width 9: left cols 0-2 (touches left edge), gap 3 (cols 3-5), right cols 6-8 (touches right edge).
    let row = run(leftColour, 3) + bgRow(3) + run(rightColour, 3)
    let bitmap = makeBitmap([row], scale: 2)
    let spec = MarkerSpec(
        left: ColorMatch(center: leftColour, tolerance: 0),
        right: ColorMatch(center: rightColour, tolerance: 0),
        minRun: 3, maxGap: 3, minRows: 1
    )

    let result = Pixels.findMarker(spec, in: bitmap)
    guard case .unique(let span) = result else {
        Issue.record("expected unique, got \(result)")
        return
    }
    #expect(span.lo == 0.0)
    #expect(span.hi == 4.5) // (8+1)/2
}
