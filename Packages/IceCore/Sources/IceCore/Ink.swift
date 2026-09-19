/// Matches a pixel whose colour channels each lie within `tolerance` of `center`.
public struct ColorMatch: Equatable, Hashable, Sendable {
    public let center: RGBA
    public let tolerance: Int

    public init(center: RGBA, tolerance: Int) {
        precondition(tolerance >= 0, "tolerance must be non-negative")
        self.center = center
        self.tolerance = tolerance
    }

    public func matches(_ pixel: RGBA) -> Bool { pixel.distance(to: center) <= tolerance }

    /// Farther than twice the tolerance: not ink, and not an anti-aliased edge of it.
    func isFar(from pixel: RGBA) -> Bool { pixel.distance(to: center) > 2 * tolerance }
}

/// The colours glyphs are drawn in on the bar right now.
///
/// Decided once per baseline and used for every capture of that observation,
/// so a bar that changes appearance mid-observation fails loudly instead of
/// being re-read in its new colour.
public struct Ink: Equatable, Sendable {
    public let colours: [ColorMatch]

    public init(colours: [ColorMatch]) {
        self.colours = colours
    }

    public func isInk(_ pixel: RGBA) -> Bool {
        colours.contains { $0.matches(pixel) }
    }

    /// Neither ink nor an edge of it: the pixels a glyph's surroundings are made of.
    public func isClearlyBackground(_ pixel: RGBA) -> Bool {
        colours.allSatisfy { $0.isFar(from: pixel) }
    }

    public func adding(_ colour: ColorMatch) -> Ink {
        Ink(colours: colours + [colour])
    }

    public func map(_ image: StripImage) -> InkMap {
        var bits = [Bool](repeating: false, count: image.width * image.height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                bits[y * image.width + x] = isInk(image.pixel(x: x, y: y))
            }
        }
        return InkMap(width: image.width, height: image.height, bits: bits)
    }

    /// The bar's ink, from one capture.
    ///
    /// White on a dark bar, black on a light one, by the median luma of the bar
    /// outside the notch. Within `parameters.inkDecisionBand` the median is a coin
    /// toss (a red bar with white glyphs measured 125 against a threshold of 128 —
    /// plan deviation 1), so there the glyphs decide: whichever colour matches more
    /// pixels inside `glyphFrames`. A mid-tone backdrop matches neither colour, so
    /// only glyphs are counted there. A tie, or no glyph at all, yields `nil`.
    public static func calibrated(from image: StripImage, geometry: BarGeometry, glyphFrames: [PtSpan], parameters: DetectorParameters) -> Ink? {
        let white = parameters.whiteInk
        let black = parameters.blackInk
        guard let median = medianLuma(image, geometry: geometry) else {
            return nil
        }
        if median < parameters.inkDecisionBand.lowerBound {
            return Ink(colours: [white])
        }
        if median > parameters.inkDecisionBand.upperBound {
            return Ink(colours: [black])
        }
        let (whiteCount, blackCount) = counts(white, black, in: image, frames: glyphFrames, geometry: geometry)
        guard whiteCount != blackCount else {
            return nil
        }
        return Ink(colours: [whiteCount > blackCount ? white : black])
    }

    private static func medianLuma(_ image: StripImage, geometry: BarGeometry) -> Int? {
        var lumas = [Int]()
        for y in stride(from: 0, to: image.height, by: 2) {
            for x in stride(from: 0, to: image.width, by: 2) where !geometry.isNotchColumn(x) {
                lumas.append(image.pixel(x: x, y: y).luma)
            }
        }
        guard !lumas.isEmpty else {
            return nil
        }
        return lumas.sorted()[lumas.count / 2]
    }

    /// Both candidate colours in one pass over the frames' pixels.
    private static func counts(_ first: ColorMatch, _ second: ColorMatch, in image: StripImage, frames: [PtSpan], geometry: BarGeometry) -> (Int, Int) {
        var firstTotal = 0
        var secondTotal = 0
        for frame in frames {
            let lo = max(0, Int((frame.lo * image.scale).rounded(.down)))
            let hi = min(image.width, Int((frame.hi * image.scale).rounded(.up)))
            guard lo < hi else { continue }
            for y in 0..<image.height {
                for x in lo..<hi where !geometry.isNotchColumn(x) {
                    let pixel = image.pixel(x: x, y: y)
                    if first.matches(pixel) { firstTotal += 1 }
                    if second.matches(pixel) { secondTotal += 1 }
                }
            }
        }
        return (firstTotal, secondTotal)
    }
}

/// Which pixels of one capture are ink. Computed once per capture, then shared
/// by every template searched in it.
public struct InkMap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    let bits: [Bool]

    init(width: Int, height: Int, bits: [Bool]) {
        precondition(bits.count == width * height, "one bit per pixel")
        self.width = width
        self.height = height
        self.bits = bits
    }

    public subscript(x: Int, y: Int) -> Bool {
        bits[y * width + x]
    }
}
