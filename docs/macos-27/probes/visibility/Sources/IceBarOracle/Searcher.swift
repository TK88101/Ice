// One capture's placement search (pre-registration section 5, "Placement
// search" and "Per placement"; readings D6-D11 of the instrument plan).
import IceCore

final class Searcher {
    private let bytes: [UInt8]
    private let geometry: OracleGeometry
    private let parameters: OracleParameters
    /// Per column, per channel, the min and max over one box's rows; shared
    /// by every template of the same height at the same y.
    private var rangeCache = [RangeKey: ColumnRanges]()
    private var histograms = [[Int]](repeating: [Int](repeating: 0, count: 256), count: 3)

    private struct RangeKey: Hashable {
        let y0: Int
        let height: Int
    }

    private struct ColumnRanges {
        let lo: [UInt8]
        let hi: [UInt8]
    }

    init(image: StripImage, geometry: OracleGeometry, parameters: OracleParameters) {
        bytes = image.bytes
        self.geometry = geometry
        self.parameters = parameters
    }

    /// Every x across the whole strip, box cut or not; y within the range of
    /// the vertical centre (D7).
    func matches(_ template: OracleTemplate, prune: Bool) -> [Placement] {
        let centre = geometry.centreY(height: template.height)
        var found = [Placement]()
        for y0 in (centre - parameters.yRangePx)...(centre + parameters.yRangePx) {
            guard y0 + template.height > 0, y0 < geometry.heightPx else { continue }
            let ranges = prune ? columnRanges(y0: y0, height: template.height) : nil
            for x0 in (1 - template.width)..<geometry.widthPx {
                if let placement = evaluate(template, x0: x0, y0: y0, ranges: ranges) {
                    found.append(placement)
                }
            }
        }
        return found
    }

    private func evaluate(_ t: OracleTemplate, x0: Int, y0: Int, ranges: ColumnRanges?) -> Placement? {
        let (visibleOn, visibleOff) = visibleCounts(t, x0: x0, y0: y0)
        let full = visibleOn == t.onCount && visibleOn > 0
        let partial = !full && visibleOn >= parameters.partialMinOnPx
        let edge = visibleOn >= parameters.edgeMinOnPx && geometry.isEdgeEligible(x0: x0, width: t.width)
        guard full || partial || edge, visibleOff > 0 else { return nil }
        // Sound: with every channel's range over the visible box <= T_o, the
        // median b lies inside that range, so no on-pixel can be a hit.
        if let ranges, rangeWithinTolerance(ranges, x0: x0, width: t.width) { return nil }

        let backdrop = median(of: t.off, x0: x0, y0: y0, count: visibleOff)
        let loose = full || partial
        let allowedMisses = loose ? visibleOn - (9 * visibleOn + 9) / 10 : 0
        guard let hits = count(t.on, x0: x0, y0: y0, from: backdrop, far: true, limit: allowedMisses) else { return nil }
        let allowedFalses = loose ? visibleOff / 10 : 0
        guard let falses = count(t.off, x0: x0, y0: y0, from: backdrop, far: false, limit: allowedFalses) else { return nil }

        let meetsLoose = hits * 10 >= 9 * visibleOn && falses * 10 <= visibleOff
        let matchClass: MatchClass
        if full && meetsLoose {
            matchClass = .full
        } else if partial && meetsLoose {
            matchClass = .partial
        } else if edge && hits == visibleOn && falses == 0 {
            matchClass = .edge
        } else {
            return nil
        }
        var placement = Placement(xPx: x0, yPx: y0, matchClass: matchClass, hits: hits, visibleOn: visibleOn, falses: falses, visibleOff: visibleOff)
        if matchClass != .full { placement.hitPixels = hitPixels(t.on, x0: x0, y0: y0, from: backdrop) }
        return placement
    }

    private func hitPixels(_ points: [OracleTemplate.Point], x0: Int, y0: Int, from b: (Int, Int, Int)) -> [Int] {
        let width = geometry.widthPx
        return points.compactMap { p in
            guard geometry.isVisible(x: x0 + p.x, y: y0 + p.y) else { return nil }
            let index = (y0 + p.y) * width + x0 + p.x
            let i = index * 4
            let d = max(abs(Int(bytes[i]) - b.0), abs(Int(bytes[i + 1]) - b.1), abs(Int(bytes[i + 2]) - b.2))
            return d > parameters.tO ? index : nil
        }
    }

    private func visibleCounts(_ t: OracleTemplate, x0: Int, y0: Int) -> (on: Int, off: Int) {
        if y0 >= 0 && y0 + t.height <= geometry.heightPx {
            var on = 0
            var off = 0
            for c in 0..<t.width {
                let x = x0 + c
                if x >= 0 && x < geometry.widthPx && geometry.visibleColumn[x] {
                    on += t.onByColumn[c]
                    off += t.offByColumn[c]
                }
            }
            return (on, off)
        }
        let on = t.on.reduce(0) { $0 + (geometry.isVisible(x: x0 + $1.x, y: y0 + $1.y) ? 1 : 0) }
        let off = t.off.reduce(0) { $0 + (geometry.isVisible(x: x0 + $1.x, y: y0 + $1.y) ? 1 : 0) }
        return (on, off)
    }

    private func rangeWithinTolerance(_ ranges: ColumnRanges, x0: Int, width: Int) -> Bool {
        var lo: (Int, Int, Int) = (255, 255, 255)
        var hi: (Int, Int, Int) = (0, 0, 0)
        for x in max(0, x0)..<min(geometry.widthPx, x0 + width) where geometry.visibleColumn[x] {
            lo = (min(lo.0, Int(ranges.lo[x * 3])), min(lo.1, Int(ranges.lo[x * 3 + 1])), min(lo.2, Int(ranges.lo[x * 3 + 2])))
            hi = (max(hi.0, Int(ranges.hi[x * 3])), max(hi.1, Int(ranges.hi[x * 3 + 1])), max(hi.2, Int(ranges.hi[x * 3 + 2])))
        }
        let tolerance = parameters.tO
        return hi.0 - lo.0 <= tolerance && hi.1 - lo.1 <= tolerance && hi.2 - lo.2 <= tolerance
    }

    private func columnRanges(y0: Int, height: Int) -> ColumnRanges {
        let key = RangeKey(y0: y0, height: height)
        if let cached = rangeCache[key] { return cached }
        let width = geometry.widthPx
        var lo = [UInt8](repeating: 255, count: width * 3)
        var hi = [UInt8](repeating: 0, count: width * 3)
        for y in max(0, y0)..<min(geometry.heightPx, y0 + height) {
            for x in 0..<width {
                let i = (y * width + x) * 4
                for c in 0..<3 {
                    lo[x * 3 + c] = min(lo[x * 3 + c], bytes[i + c])
                    hi[x * 3 + c] = max(hi[x * 3 + c], bytes[i + c])
                }
            }
        }
        let ranges = ColumnRanges(lo: lo, hi: hi)
        rangeCache[key] = ranges
        return ranges
    }

    /// b: the per-channel lower median of the visible off-pixels (D8).
    private func median(of points: [OracleTemplate.Point], x0: Int, y0: Int, count: Int) -> (Int, Int, Int) {
        let width = geometry.widthPx
        for p in points where geometry.isVisible(x: x0 + p.x, y: y0 + p.y) {
            let i = ((y0 + p.y) * width + x0 + p.x) * 4
            for c in 0..<3 { histograms[c][Int(bytes[i + c])] += 1 }
        }
        let b = (Oracle.lowerMedian(histograms[0], count: count),
                 Oracle.lowerMedian(histograms[1], count: count),
                 Oracle.lowerMedian(histograms[2], count: count))
        for p in points where geometry.isVisible(x: x0 + p.x, y: y0 + p.y) {
            let i = ((y0 + p.y) * width + x0 + p.x) * 4
            for c in 0..<3 { histograms[c][Int(bytes[i + c])] -= 1 }
        }
        return b
    }

    /// With `far`, counts visible points farther than `T_o` from `b` (hits),
    /// giving up once more than `limit` are not; without it, counts the far
    /// ones (falses), giving up once more than `limit` are. nil = gave up.
    private func count(_ points: [OracleTemplate.Point], x0: Int, y0: Int, from b: (Int, Int, Int), far: Bool, limit: Int) -> Int? {
        let width = geometry.widthPx
        var farCount = 0
        var nearCount = 0
        for p in points where geometry.isVisible(x: x0 + p.x, y: y0 + p.y) {
            let i = ((y0 + p.y) * width + x0 + p.x) * 4
            let d = max(abs(Int(bytes[i]) - b.0), abs(Int(bytes[i + 1]) - b.1), abs(Int(bytes[i + 2]) - b.2))
            if d > parameters.tO {
                farCount += 1
                if !far && farCount > limit { return nil }
            } else {
                nearCount += 1
                if far && nearCount > limit { return nil }
            }
        }
        return farCount
    }
}
