// Pure pixel search over captured menu bar strips: finds our own markers and
// locates user items' baseline templates. No I/O, no screen capture — only
// arithmetic over `Bitmap` bytes handed in by the caller. See Contract.swift
// for the shared value types this module reads and returns.

/// Pixel search over a `Bitmap`: our own markers, user item templates, plain
/// colour counts, and colours safe to hand out as fresh markers.
public enum Pixels: Sendable {

    /// Finds occurrences of `spec`'s two-colour pattern (a run of `left`
    /// immediately, or within `maxGap` px, followed by a run of `right`, both
    /// at least `minRun` px long) and keeps only occurrences that recur on at
    /// least `minRows` rows whose px ranges overlap — a single stray pixel run
    /// on one row is noise, but the same run repeating down several rows is
    /// our marker's vertical stroke. A resulting span is dropped when its
    /// midpoint falls inside an `excluding` span, since that means the match
    /// is really a user item's own pixels, not ours.
    public static func findMarker(_ spec: MarkerSpec, in bitmap: Bitmap, excluding: [Span] = []) -> MarkerResult {
        let hits = (0..<bitmap.height).flatMap { hitsInRow($0, bitmap: bitmap, spec: spec) }
        let groups = groupHits(hits)
        let spans = groups
            .filter { $0.rows.count >= spec.minRows }
            .map { Span(lo: Double($0.start) / bitmap.scale, hi: Double($0.end + 1) / bitmap.scale) }
            .filter { span in !excluding.contains { $0.contains(span.mid) } }
            .sorted { $0.lo < $1.lo }

        switch spans.count {
        case 0: return .absent
        case 1: return .unique(spans[0])
        default: return .ambiguous(spans)
        }
    }

    /// Slides `template` horizontally within `searchRadius` of its baseline
    /// `originX` and picks the offset with the fewest per-channel mismatches
    /// (ties broken toward zero, then toward the negative side) — this is how
    /// we tell "the item just shifted a bit" from "the item is gone or
    /// changed", using `maxMismatch` as the line between the two.
    public static func locate(
        _ template: ItemTemplate,
        in bitmap: Bitmap,
        searchRadius: Double,
        channelTolerance: Int,
        maxMismatch: Double
    ) -> TemplateResult {
        precondition(template.bitmap.height == bitmap.height, "template must span the same rows as the strip")
        precondition(template.bitmap.scale == bitmap.scale, "template and strip must share a scale")

        // Guard against non-finite inputs before converting to Int, which
        // traps on infinity/NaN.
        guard template.originX.isFinite, searchRadius.isFinite else { return .notFound(bestMismatch: 1.0) }

        let originPx = Int((template.originX * bitmap.scale).rounded())
        let radiusPx = Int((searchRadius * bitmap.scale).rounded(.down))
        guard radiusPx >= 0 else { return .notFound(bestMismatch: 1.0) }

        let area = template.bitmap.width * template.bitmap.height
        var bestOffset: Int?
        var bestCount = Int.max

        // Clamp the candidate range to what the bitmap can actually hold
        // instead of iterating the full -radiusPx...radiusPx span: iteration
        // cost must scale with the bitmap, not with an arbitrarily large
        // searchRadius. This does not change candidate order or tie-breaks —
        // it only skips d values that `guard x0 >= 0, x0 + width <= bitmap.width`
        // would have skipped anyway.
        let minD = max(-radiusPx, -originPx)
        let maxD = min(radiusPx, bitmap.width - template.bitmap.width - originPx)
        if minD <= maxD {
            for d in minD...maxD {
                let x0 = originPx + d
                let count = mismatchCount(template: template.bitmap, in: bitmap, atX: x0, tolerance: channelTolerance, ceiling: bestCount)
                if isBetterCandidate(newCount: count, newOffset: d, currentCount: bestCount, currentOffset: bestOffset) {
                    bestCount = count
                    bestOffset = d
                }
            }
        }

        guard let offset = bestOffset else { return .notFound(bestMismatch: 1.0) }
        let mismatchFraction = area == 0 ? 0.0 : Double(bestCount) / Double(area)
        guard mismatchFraction <= maxMismatch else { return .notFound(bestMismatch: mismatchFraction) }
        return .found(offset: Double(offset) / bitmap.scale)
    }

    /// Counts pixels matching `colour` within the px columns `span` covers on
    /// every row — the columns are widened outward with floor/ceil so a
    /// fractional pt boundary still counts the px it partly touches, then
    /// clamped to the bitmap so an out-of-range span costs nothing.
    public static func count(_ colour: ColorMatch, in bitmap: Bitmap, span: Span) -> Int {
        guard span.lo < span.hi else { return 0 }
        let widthD = Double(bitmap.width)
        let loD = min(max((span.lo * bitmap.scale).rounded(.down), 0), widthD)
        let hiD = min(max((span.hi * bitmap.scale).rounded(.up), 0), widthD)
        let lowCol = Int(loD)
        let highCol = Int(hiD)
        guard lowCol < highCol else { return 0 }

        var total = 0
        for y in 0..<bitmap.height {
            for x in lowCol..<highCol where colour.matches(bitmap.pixel(x: x, y: y)) {
                total += 1
            }
        }
        return total
    }

    /// Returns the `candidates`, in the order given, that appear nowhere in
    /// `bitmaps` — colours we can safely hand out as new markers because
    /// nothing captured so far could be mistaken for them.
    public static func unusedColours(_ candidates: [RGBA], tolerance: Int, in bitmaps: [Bitmap]) -> [RGBA] {
        candidates.filter { candidate in
            let match = ColorMatch(center: candidate, tolerance: tolerance)
            return !bitmaps.contains { containsMatch(match, in: $0) }
        }
    }
}

// MARK: - findMarker internals

/// A maximal run of consecutive indices, inclusive of both ends.
private struct Run {
    let start: Int
    let end: Int

    var length: Int { end - start + 1 }
}

/// One row's occurrence of the left-run/right-run pattern, in px columns.
private struct MarkerHit {
    let row: Int
    let start: Int
    let end: Int
}

/// Groups of hits merged by transitively overlapping px ranges.
private struct MarkerGroup {
    var start: Int
    var end: Int
    var rows: Set<Int>
}

/// Maximal runs of consecutive indices in `0..<count` where `matches` holds.
private func maximalRuns(count: Int, matches: (Int) -> Bool) -> [Run] {
    var runs: [Run] = []
    var runStart: Int?
    for index in 0..<count {
        if matches(index) {
            if runStart == nil { runStart = index }
        } else if let start = runStart {
            runs.append(Run(start: start, end: index - 1))
            runStart = nil
        }
    }
    if let start = runStart {
        runs.append(Run(start: start, end: count - 1))
    }
    return runs
}

/// The marker hits on a single row of `bitmap`. A pixel matching `spec.left`
/// is never eligible to be part of a right run, even if it would also match
/// `spec.right`.
private func hitsInRow(_ y: Int, bitmap: Bitmap, spec: MarkerSpec) -> [MarkerHit] {
    var leftFlags = [Bool](repeating: false, count: bitmap.width)
    var rightFlags = [Bool](repeating: false, count: bitmap.width)
    for x in 0..<bitmap.width {
        let pixel = bitmap.pixel(x: x, y: y)
        let isLeft = spec.left.matches(pixel)
        leftFlags[x] = isLeft
        rightFlags[x] = !isLeft && spec.right.matches(pixel)
    }

    let leftRuns = maximalRuns(count: bitmap.width) { leftFlags[$0] }.filter { $0.length >= spec.minRun }
    let rightRuns = maximalRuns(count: bitmap.width) { rightFlags[$0] }.filter { $0.length >= spec.minRun }

    return leftRuns.compactMap { leftRun in
        guard let rightRun = rightRuns.first(where: { $0.start > leftRun.end }) else { return nil }
        let gap = rightRun.start - leftRun.end - 1
        guard gap <= spec.maxGap else { return nil }
        return MarkerHit(row: y, start: leftRun.start, end: rightRun.end)
    }
}

/// Merges hits whose px ranges overlap, transitively, into groups — the
/// standard sweep works here because it tracks the running max end, so a
/// chain of pairwise overlaps merges even when the first and last hit in the
/// chain do not themselves overlap.
private func groupHits(_ hits: [MarkerHit]) -> [MarkerGroup] {
    let sorted = hits.sorted { $0.start < $1.start }
    guard let first = sorted.first else { return [] }

    var groups: [MarkerGroup] = []
    var current = MarkerGroup(start: first.start, end: first.end, rows: [first.row])
    for hit in sorted.dropFirst() {
        if hit.start <= current.end {
            current.end = max(current.end, hit.end)
            current.rows.insert(hit.row)
        } else {
            groups.append(current)
            current = MarkerGroup(start: hit.start, end: hit.end, rows: [hit.row])
        }
    }
    groups.append(current)
    return groups
}

// MARK: - locate internals

/// True when a pixel's per-channel difference from its counterpart exceeds
/// `tolerance` in at least one channel. Alpha is ignored.
private func channelMismatch(_ a: RGBA, _ b: RGBA, tolerance: Int) -> Bool {
    let dr = abs(Int(a.r) - Int(b.r))
    let dg = abs(Int(a.g) - Int(b.g))
    let db = abs(Int(a.b) - Int(b.b))
    return max(dr, dg, db) > tolerance
}

/// Counts mismatching pixels between `template` and the `bitmap` region at
/// `x0`, stopping early once the count exceeds `ceiling` — the caller only
/// needs candidates that could beat the best count seen so far, and a count
/// only ever grows as more pixels are checked, so this never changes which
/// candidate wins.
private func mismatchCount(template: Bitmap, in bitmap: Bitmap, atX x0: Int, tolerance: Int, ceiling: Int) -> Int {
    var count = 0
    for y in 0..<template.height {
        for x in 0..<template.width {
            let templatePixel = template.pixel(x: x, y: y)
            let bitmapPixel = bitmap.pixel(x: x0 + x, y: y)
            guard channelMismatch(templatePixel, bitmapPixel, tolerance: tolerance) else { continue }
            count += 1
            if count > ceiling { return count }
        }
    }
    return count
}

/// True when a new candidate beats the current best: fewer mismatches first,
/// then the smaller absolute offset, then the negative offset over the
/// positive one at equal absolute value. `currentOffset == nil` means there
/// is no candidate yet, so the new one always wins.
private func isBetterCandidate(newCount: Int, newOffset: Int, currentCount: Int, currentOffset: Int?) -> Bool {
    guard let currentOffset else { return true }
    if newCount != currentCount { return newCount < currentCount }
    let newAbs = abs(newOffset)
    let currentAbs = abs(currentOffset)
    if newAbs != currentAbs { return newAbs < currentAbs }
    return newOffset < currentOffset
}

// MARK: - unusedColours internals

/// True when some pixel in `bitmap` matches `match`.
private func containsMatch(_ match: ColorMatch, in bitmap: Bitmap) -> Bool {
    for y in 0..<bitmap.height {
        for x in 0..<bitmap.width where match.matches(bitmap.pixel(x: x, y: y)) {
            return true
        }
    }
    return false
}
