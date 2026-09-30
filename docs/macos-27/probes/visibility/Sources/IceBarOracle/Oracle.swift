// The oracle (docs/plans/2026-09-30-icebar-c-prereg.md section 5): looks for
// the known rendering of each helper's glyph, and of the chevron, at every
// placement; independent of `RegionClear` and of the frozen matcher.
import IceCore

public enum Oracle {
    public static func label(
        image: StripImage,
        helpers: [OracleTemplate],
        chevron: OracleTemplate?,
        context: OracleContext,
        parameters: OracleParameters = .preRegistered
    ) throws(OracleError) -> CaptureLabels {
        if let mismatched = helpers.first(where: { $0.scale != image.scale }) {
            throw .scaleMismatch(id: mismatched.id)
        }
        let geometry = OracleGeometry(widthPx: image.width, heightPx: image.height, scale: image.scale, context: context, parameters: parameters)
        let searcher = Searcher(image: image, geometry: geometry, parameters: parameters)

        var labels = [String: HelperLabel]()
        var fullMatches = [String: [Placement]]()
        var partials = [(template: OracleTemplate, placement: Placement)]()
        var identified = [(template: OracleTemplate, placement: Placement)]()
        for template in helpers {
            let found = searcher.matches(template, prune: true)
            let full = found.filter { $0.matchClass == .full }
            fullMatches[template.id] = full
            partials += found.filter { $0.matchClass != .full }.map { (template, $0) }
            if let top = best(full, template: template, geometry: geometry) {
                identified.append((template, top))
                labels[template.id] = .drawn(.full, xPt: Double(top.xPx) / image.scale + parameters.glyphInsetPt,
                                             zone: geometry.zone(x0: top.xPx, width: template.width))
            } else {
                labels[template.id] = HelperLabel.none
            }
        }
        let ink = inkMask(identified, width: image.width, height: image.height)
        let sightings = partials.map { template, p in
            Sighting(templateID: template.id, xPx: p.xPx, yPx: p.yPx, width: template.width, matchClass: p.matchClass,
                     explained: !p.hitPixels.isEmpty && p.hitPixels.allSatisfy { ink[$0] })
        }

        let sighting: ChevronSighting
        if let chevron, chevron.scale == image.scale {
            sighting = searcher.matches(chevron, prune: true).isEmpty ? .absent : .present
        } else {
            sighting = .notEvaluable
        }
        let tolerancePx = parameters.positionTolerancePt * image.scale
        return CaptureLabels(
            labels: labels,
            matches: fullMatches,
            sightings: sightings,
            inconclusive: ambiguity(fullMatches, order: helpers.map(\.id), tolerancePx: tolerancePx),
            chevron: sighting
        )
    }

    /// The pixels where some `full`-identified helper's rendering has alpha > 0
    /// at its best placement (deviation 2 C1).
    static func inkMask(_ identified: [(template: OracleTemplate, placement: Placement)], width: Int, height: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: width * height)
        for (template, placement) in identified {
            for y in 0..<template.height {
                for x in 0..<template.width where template.alpha[y * template.width + x] > 0 {
                    let ix = placement.xPx + x
                    let iy = placement.yPx + y
                    if ix >= 0, ix < width, iy >= 0, iy < height { mask[iy * width + ix] = true }
                }
            }
        }
        return mask
    }

    /// Every placement of `template` meeting some class, `prune` off for the
    /// soundness test of the range prune.
    static func matches(image: StripImage, template: OracleTemplate, context: OracleContext, prune: Bool,
                        parameters: OracleParameters = .preRegistered) throws(OracleError) -> [Placement] {
        guard template.scale == image.scale else { throw .scaleMismatch(id: template.id) }
        let geometry = OracleGeometry(widthPx: image.width, heightPx: image.height, scale: image.scale, context: context, parameters: parameters)
        return Searcher(image: image, geometry: geometry, parameters: parameters).matches(template, prune: prune)
    }

    /// D12: highest class, higher hit fraction, lower false fraction, nearer
    /// the vertical centre, smaller x.
    static func best(_ found: [Placement], template: OracleTemplate, geometry: OracleGeometry) -> Placement? {
        let centre = geometry.centreY(height: template.height)
        return found.min { a, b in
            if a.matchClass != b.matchClass { return a.matchClass > b.matchClass }
            let hitsA = a.hits * b.visibleOn
            let hitsB = b.hits * a.visibleOn
            if hitsA != hitsB { return hitsA > hitsB }
            let falseA = a.falses * max(1, b.visibleOff)
            let falseB = b.falses * max(1, a.visibleOff)
            if falseA != falseB { return falseA < falseB }
            let dyA = abs(a.yPx - centre)
            let dyB = abs(b.yPx - centre)
            if dyA != dyB { return dyA < dyB }
            return a.xPx < b.xPx
        }
    }

    /// D14 and D15, in the helpers' own order so the result is deterministic.
    static func ambiguity(_ matches: [String: [Placement]], order: [String], tolerancePx: Double) -> [InconclusiveReason] {
        var reasons = [InconclusiveReason]()
        let xs = order.map { id in (id, (matches[id] ?? []).map(\.xPx).sorted()) }
        for (id, x) in xs {
            if let lo = x.first, let hi = x.last, Double(hi - lo) > tolerancePx {
                reasons.append(.spreadPlacements(id))
            }
        }
        for i in xs.indices {
            for j in xs.indices where j > i {
                let near = xs[i].1.contains { a in xs[j].1.contains { b in Double(abs(a - b)) <= tolerancePx } }
                if near { reasons.append(.sharedPlacement(xs[i].0, xs[j].0)) }
            }
        }
        return reasons
    }

    /// The median of the values counted in `histogram`, the lower one for an
    /// even count (D8).
    static func lowerMedian(_ histogram: [Int], count: Int) -> Int {
        let target = (count - 1) / 2
        var seen = 0
        for value in 0..<histogram.count {
            seen += histogram[value]
            if seen > target { return value }
        }
        return histogram.count - 1
    }
}
