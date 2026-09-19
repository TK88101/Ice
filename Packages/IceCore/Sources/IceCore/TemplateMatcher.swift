/// Searches a capture for one item's template, over the whole strip.
///
/// Never narrowed to where Accessibility currently says the item is: for an
/// overflowed item that answer depends on the path the layout took, so a search
/// window around it would look in the wrong place (FINDINGS, "Refuted").
///
/// Two passes, deliberately asymmetric:
///
/// 1. the trimap — every core pixel must be ink where the glyph has ink and not
///    ink where it clearly has none. This is what `drawn` rests on.
/// 2. the same trimap at a looser threshold — only when pass 1 found nothing
///    anywhere. Its hits carry their real mismatch, which is above the decision
///    layer's tolerance by construction, so pass 2 can only ever block an
///    absence, never assert that something is drawn.
///
/// Pass 2 asked "is this glyph's ink still here" until 2026-09-19, when the
/// first live run showed why that cannot work: the question is one-sided, so
/// any dense patch of ink on the bar satisfies a sparse glyph's ink and an item
/// that had just been hidden read as `weak` instead of gone. Requiring the
/// glyph's negative space too fixes it, and the threshold stays under the ink
/// share a vacated slot mismatches by, so "gone" is still reachable.
public enum TemplateMatcher {
    public static func match(_ template: ItemTemplate, in map: InkMap, geometry: BarGeometry, parameters: DetectorParameters) -> Match {
        precondition(parameters.isValid, "detector parameters violate their own invariants")
        precondition(template.caredCount > 0, "a template must care about some pixels")

        let cared = Double(template.caredCount)
        let allowed = Int((parameters.foundThreshold * cared).rounded(.down))
        let weakAllowed = Int((parameters.weakThreshold * cared).rounded(.down))
        let columns = offsets(template, map: map, geometry: geometry)
        var candidates = [(x: Int, score: Int)]()
        var weakHits = [(x: Int, score: Int)]()
        var best = Int.max

        // One scan, not two: the looser ceiling covers both passes, so an
        // absent item — the case this detector exists for — no longer walks
        // the whole strip a second time.
        for x0 in columns {
            let ceiling = best == Int.max ? weakAllowed : max(weakAllowed, best)
            let count = mismatchCount(template, in: map, atPx: x0, ceiling: ceiling)
            best = min(best, count)
            if count <= allowed {
                candidates.append((x0, count))
            } else if count <= weakAllowed {
                weakHits.append((x0, count))
            }
        }

        if !candidates.isEmpty {
            let kept = cluster(candidates, radius: parameters.suppressionRadiusPx, better: { $0.score < $1.score })
            if kept.count == 1 {
                return .unique(x: Double(kept[0].x) / template.scale, mismatch: Double(kept[0].score) / cared)
            }
            return .ambiguous(count: kept.count)
        }

        guard !weakHits.isEmpty else {
            let bestFraction = best == Int.max ? 1 : Double(best) / cared
            return .absent(bestMismatch: bestFraction)
        }

        let kept = cluster(weakHits, radius: parameters.suppressionRadiusPx, better: { $0.score < $1.score })
        if kept.count == 1 {
            return .unique(x: Double(kept[0].x) / template.scale, mismatch: Double(kept[0].score) / cared)
        }
        return .ambiguous(count: kept.count)
    }

    /// Every column the template could start at, inside the bar and clear of the notch.
    private static func offsets(_ template: ItemTemplate, map: InkMap, geometry: BarGeometry) -> [Int] {
        guard template.widthPx > 0, template.originYPx >= 0, template.originYPx + template.heightPx <= map.height else { return [] }
        let last = map.width - template.widthPx
        guard last >= 0 else { return [] }
        return (0...last).filter { geometry.allowsSpan(fromPx: $0, widthPx: template.widthPx) }
    }

    /// Core pixels that disagree, stopping once the count passes `ceiling`:
    /// a count only grows, so an early stop never changes which offsets win.
    static func mismatchCount(_ template: ItemTemplate, in map: InkMap, atPx x0: Int, ceiling: Int) -> Int {
        var count = 0
        for dy in 0..<template.heightPx {
            let y = template.originYPx + dy
            for dx in 0..<template.widthPx {
                let cell = template[dx, dy]
                guard cell != .edge else { continue }
                if (cell == .ink) != map[x0 + dx, y] {
                    count += 1
                    if count > ceiling { return count }
                }
            }
        }
        return count
    }

    /// Groups candidate offsets into clusters and returns one representative of
    /// each, best first by `better`.
    ///
    /// Offsets no more than `radius` apart belong to the same cluster. Chaining
    /// inside a run is deliberate: a solid patch of ink makes every offset across
    /// it a candidate, and scoring them equally would otherwise leave one
    /// representative every `radius + 1` px and read as ambiguous. Two real
    /// glyphs can never chain, because their candidate offsets differ by at
    /// least the glyph's own width, which the parameters keep above the radius.
    private static func cluster(
        _ candidates: [(x: Int, score: Int)],
        radius: Int,
        better: ((x: Int, score: Int), (x: Int, score: Int)) -> Bool
    ) -> [(x: Int, score: Int)] {
        let sorted = candidates.sorted { $0.x < $1.x }
        var representatives = [(x: Int, score: Int)]()
        var current: (x: Int, score: Int)?
        var previousX: Int?
        for candidate in sorted {
            if let last = previousX, candidate.x - last <= radius {
                if let best = current, better(candidate, best) { current = candidate }
            } else {
                if let best = current { representatives.append(best) }
                current = candidate
            }
            previousX = candidate.x
        }
        if let best = current { representatives.append(best) }
        return representatives
    }
}
