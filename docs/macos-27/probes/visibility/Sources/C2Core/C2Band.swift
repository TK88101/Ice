// T1 (docs/plans/2026-09-28-c2-protocol.md section 4): a configuration's band
// from its readings, the deterministic range expansion, the 4 pt edge
// refinement, and -- across configurations -- the intersection, the length L
// and its collar. Pure; lengths are spacer points.

/// One scanned length's own outcome, already past 6.2's inconclusive retries.
public enum C2Reading: Equatable, Sendable {
    /// Every hidden item `hidden(folded: false)` -- the only band member.
    case hiddenNoFold
    case hiddenFolded
    case stillDrawn
    /// Anything else: refused, unverifiable, or inconclusive three times.
    case notShown
}

public struct C2Point: Equatable, Sendable {
    public let length: Double
    public let reading: C2Reading

    public init(length: Double, reading: C2Reading) {
        self.length = length
        self.reading = reading
    }
}

public struct C2Span: Equatable, Sendable {
    public let lo: Double
    public let hi: Double

    public init(lo: Double, hi: Double) {
        self.lo = lo
        self.hi = hi
    }

    public var width: Double { hi - lo }
}

public enum C2Band {
    public static let coarseStepPt = 16.0
    public static let refineStepPt = 4.0
    public static let expansionChunkPt = 160.0
    public static let minimumLengthPt = 0.0
    /// The helper refuses any spacer length above this (vzhelper's own 0-1000).
    public static let maximumLengthPt = 1000.0
    public static let minimumIntersectionPt = 32.0
    public static let collarHalfWidthPt = 16.0

    /// The widest contiguous run of `hiddenNoFold` in length order (any other
    /// reading splits it); on a tie, the lower run. `nil` when none.
    public static func band(_ points: [C2Point]) -> C2Span? {
        var best: C2Span?
        var current: C2Span?
        for point in points.sorted(by: { $0.length < $1.length }) {
            guard point.reading == .hiddenNoFold else {
                current = nil
                continue
            }
            let run = C2Span(lo: current?.lo ?? point.length, hi: point.length)
            current = run
            if best == nil || run.width > best!.width { best = run }
        }
        return best
    }

    /// The next 160 pt chunk to scan (16 pt steps), or `nil` when the band is
    /// closed on both sides or the scan already reaches 0 / 1000 where it is
    /// open. Without a band, downward first, then upward.
    public static func nextExpansion(_ points: [C2Point]) -> [Double]? {
        guard let lowest = points.map(\.length).min(), let highest = points.map(\.length).max() else { return nil }
        let found = band(points)
        let openBelow = lowest > minimumLengthPt && (found == nil || found!.lo == lowest)
        let openAbove = highest < maximumLengthPt && (found == nil || found!.hi == highest)
        if openBelow { return chunkBelow(lowest) }
        if openAbove { return chunkAbove(highest) }
        return nil
    }

    /// The 4 pt points strictly inside the gap below the band's lowest point
    /// and above its highest -- empty once a gap is already 4 pt.
    public static func refinementPoints(_ points: [C2Point]) -> [Double] {
        guard let found = band(points) else { return [] }
        let lengths = points.map(\.length)
        var result = [Double]()
        if let below = lengths.filter({ $0 < found.lo }).max() {
            result += Array(stride(from: below + refineStepPt, to: found.lo, by: refineStepPt))
        }
        if let above = lengths.filter({ $0 > found.hi }).min() {
            result += Array(stride(from: found.hi + refineStepPt, to: above, by: refineStepPt))
        }
        return result
    }

    public static func intersection(_ spans: [C2Span]) -> C2Span? {
        guard let lo = spans.map(\.lo).max(), let hi = spans.map(\.hi).min(), lo <= hi else { return nil }
        return C2Span(lo: lo, hi: hi)
    }

    /// The intersection's midpoint rounded to 1 pt, only when it is at least
    /// `minimumIntersectionPt` wide (16 pt of margin on both sides).
    public static func length(_ intersection: C2Span) -> Double? {
        guard intersection.width >= minimumIntersectionPt else { return nil }
        return ((intersection.lo + intersection.hi) / 2).rounded()
    }

    public static func collar(_ length: Double) -> [Double] {
        Array(stride(from: length - collarHalfWidthPt, through: length + collarHalfWidthPt, by: refineStepPt))
    }

    private static func chunkBelow(_ lowest: Double) -> [Double] {
        let steps = Int(expansionChunkPt / coarseStepPt)
        var chunk = (1...steps).map { lowest - Double($0) * coarseStepPt }.filter { $0 > minimumLengthPt }
        if lowest - expansionChunkPt <= minimumLengthPt { chunk.append(minimumLengthPt) }
        return chunk.sorted()
    }

    private static func chunkAbove(_ highest: Double) -> [Double] {
        let steps = Int(expansionChunkPt / coarseStepPt)
        var chunk = (1...steps).map { highest + Double($0) * coarseStepPt }.filter { $0 < maximumLengthPt }
        if highest + expansionChunkPt >= maximumLengthPt { chunk.append(maximumLengthPt) }
        return chunk
    }
}
