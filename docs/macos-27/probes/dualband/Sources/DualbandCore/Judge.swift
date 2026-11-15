//  Judge.swift
//  dualband

/// A bar strip as luminance, one byte per pixel, row-major.
public struct GrayStrip: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width >= 0 && height >= 0 && pixels.count == width * height, "pixels must fill the strip")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }
}

/// What one capture of one bar says (plan T0, the `hides` predicate).
public struct BarReading: Equatable, Sendable {
    /// Pixels left of the members' standard-length spot that changed against
    /// the standard-length strip: a member drawn elsewhere, or a `«`.
    public let newForeground: Int
    /// Glyph-like pixels inside the spot: a member still, or again, drawn there.
    public let spotForeground: Int

    public var hides: Bool {
        newForeground <= Judge.maxNewForeground && spotForeground <= Judge.maxSpotForeground
    }
}

public enum JudgeRefusal: Error, Equatable, Sendable {
    case sizeMismatch
    case emptySpot
    case spotOutOfStrip
}

public enum Judge {
    /// A luminance change counted as something drawn (of 255).
    public static let changeThreshold = 48
    /// A pixel this far from its row's median inside the spot is glyph-like.
    public static let contrastThreshold = 64
    /// Columns kept clear between the compared region and the spot.
    public static let spotPad = 4
    /// Antialiasing and noise allowance, in pixels.
    public static let maxNewForeground = 12
    public static let maxSpotForeground = 12

    /// - Parameters:
    ///   - sample: the bar at the length under test.
    ///   - standard: the same bar at standard length, same condition.
    ///   - spot: the members' pixel columns at standard length on this bar.
    ///   - excluded: columns never compared (the notch, a third-party window over the bar).
    public static func read(
        sample: GrayStrip, standard: GrayStrip, spot: Range<Int>, excluded: [Range<Int>] = []
    ) throws(JudgeRefusal) -> BarReading {
        guard sample.width == standard.width, sample.height == standard.height else { throw .sizeMismatch }
        guard !spot.isEmpty else { throw .emptySpot }
        guard spot.lowerBound >= 0, spot.upperBound <= sample.width else { throw .spotOutOfStrip }
        return BarReading(
            newForeground: changedLeft(of: spot.lowerBound - spotPad, sample: sample, standard: standard, excluded: excluded),
            spotForeground: glyphPixels(in: spot, of: sample, excluded: excluded)
        )
    }

    /// Columns where nearly the whole height is near black (a notch app's
    /// drawn blob over a coloured bar), widened by `pad` on each side.
    public static func darkBlobs(in strip: GrayStrip, darkBelow: UInt8 = 24, share: Double = 0.7, pad: Int = 8) -> [Range<Int>] {
        guard strip.height > 0 else { return [] }
        var spans: [Range<Int>] = []
        var start: Int?
        for x in 0...strip.width {
            let dark = x < strip.width && Double((0..<strip.height).filter { strip[x, $0] < darkBelow }.count) >= share * Double(strip.height)
            if dark, start == nil { start = x }
            if !dark, let s = start {
                spans.append(max(0, s - pad)..<min(strip.width, x + pad))
                start = nil
            }
        }
        return spans
    }

    public static func changedLeft(of limit: Int, sample: GrayStrip, standard: GrayStrip, excluded: [Range<Int>]) -> Int {
        guard limit > 0 else { return 0 }
        let columns = (0..<limit).filter { x in !excluded.contains { $0.contains(x) } }
        var count = 0
        for y in 0..<sample.height {
            for x in columns where abs(Int(sample[x, y]) - Int(standard[x, y])) > changeThreshold {
                count += 1
            }
        }
        return count
    }

    static func glyphPixels(in spot: Range<Int>, of strip: GrayStrip, excluded: [Range<Int>]) -> Int {
        let columns = spot.filter { x in !excluded.contains { $0.contains(x) } }
        guard !columns.isEmpty else { return 0 }
        var count = 0
        for y in 0..<strip.height {
            let row = columns.map { Int(strip[$0, y]) }
            let median = row.sorted()[row.count / 2]
            count += row.filter { abs($0 - median) > contrastThreshold }.count
        }
        return count
    }
}
