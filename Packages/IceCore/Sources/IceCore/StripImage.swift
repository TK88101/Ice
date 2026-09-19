/// One pixel, 8 bits per channel.
public struct RGBA: Equatable, Hashable, Sendable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8
    public let a: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Mean of the three colour channels.
    var luma: Int { (Int(r) + Int(g) + Int(b)) / 3 }

    /// The largest per-channel difference from `other`, alpha ignored.
    func distance(to other: RGBA) -> Int {
        max(abs(Int(r) - Int(other.r)), abs(Int(g) - Int(other.g)), abs(Int(b) - Int(other.b)))
    }
}

/// A capture of the menu bar strip: RGBA8, row-major, top row first.
///
/// The adapter converts whatever the capture API returns into this, so every
/// rule in this module sees the same layout whatever produced the pixels.
public struct StripImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Pixels per point.
    public let scale: Double
    public let bytes: [UInt8]

    public init(width: Int, height: Int, scale: Double, bytes: [UInt8]) {
        precondition(width >= 0 && height >= 0, "dimensions must be non-negative")
        precondition(scale.isFinite && scale > 0, "scale must be finite and positive")
        precondition(bytes.count == width * height * 4, "bytes must hold width * height * 4 values")
        self.width = width
        self.height = height
        self.scale = scale
        self.bytes = bytes
    }

    public func pixel(x: Int, y: Int) -> RGBA {
        precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel out of range")
        let i = (y * width + x) * 4
        return RGBA(bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }
}

/// A closed interval of points along the bar's x axis.
public struct PtSpan: Equatable, Hashable, Sendable {
    public let lo: Double
    public let hi: Double

    public init(lo: Double, hi: Double) {
        precondition(lo <= hi, "lo must not exceed hi")
        self.lo = lo
        self.hi = hi
    }

    public func contains(_ x: Double) -> Bool { x >= lo && x <= hi }

    /// Whether the two share more than an edge.
    public func overlaps(_ other: PtSpan) -> Bool { lo < other.hi && other.lo < hi }
}

/// The display's menu bar, as the adapter measured it. An input, never a
/// constant: the probes that came before hard-coded this machine's notch.
public struct BarGeometry: Equatable, Sendable {
    public let widthPt: Double
    public let heightPt: Double
    public let scale: Double
    /// Nothing is drawn in the camera housing, and it captures as pure black,
    /// which reads as ink on a light bar.
    public let notch: PtSpan?

    /// The notch's pixel columns, widened outward so a fractional edge still
    /// excludes the column it touches. Computed once: every pixel scan in this
    /// module asks for it, and it cannot change for a given geometry.
    let notchColumns: Range<Int>?

    public init(widthPt: Double, heightPt: Double, scale: Double, notch: PtSpan?) {
        precondition(widthPt.isFinite && widthPt > 0 && heightPt.isFinite && heightPt > 0, "bar size must be finite and positive")
        precondition(scale.isFinite && scale > 0, "scale must be finite and positive")
        self.widthPt = widthPt
        self.heightPt = heightPt
        self.scale = scale
        self.notch = notch
        if let notch {
            let lo = Int((notch.lo * scale).rounded(.down))
            let hi = Int((notch.hi * scale).rounded(.up))
            self.notchColumns = lo < hi ? lo..<hi : nil
        } else {
            self.notchColumns = nil
        }
    }

    public var widthPx: Int { Int((widthPt * scale).rounded()) }
    public var heightPx: Int { Int((heightPt * scale).rounded()) }

    public func pt(fromPx px: Int) -> Double { Double(px) / scale }

    /// Whether a span of columns lies inside the bar and clear of the notch.
    public func allowsSpan(fromPx x: Int, widthPx w: Int) -> Bool {
        guard x >= 0, w > 0, x + w <= widthPx else { return false }
        guard let columns = notchColumns else { return true }
        return x + w <= columns.lowerBound || x >= columns.upperBound
    }

    func isNotchColumn(_ x: Int) -> Bool {
        notchColumns?.contains(x) ?? false
    }
}
