//  CoverPixels.swift
//  MenuBarCover

import CoreGraphics

/// Pixel comparisons of two strips of one bar.
public enum CoverPixels {
    /// A channel difference up to this is the same pixel.
    public static let sameChannel = 2
    /// The share of item-free columns that must be identical for the bar to
    /// count as transparent.
    public static let transparentShare = 0.2
    /// The share of columns that must be identical for two strips of one bar
    /// to be the same background (plan 2026-11-18-cover-stale-and-lost, D1).
    public static let equalShare = 0.98

    /// The space a strip's values are read in: its own when a bitmap can be
    /// drawn in it, so they are the values as captured.
    private static func capturedSpace(of image: CGImage) -> CGColorSpace {
        image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
    }

    /// RGBA8 pixels of an image in `space`, row-major.
    private static func rgba(_ image: CGImage, in space: CGColorSpace) -> (width: Int, height: Int, pixels: [UInt8])? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (width, height, pixels) : nil
    }

    /// Per pixel column, whether the two strips are the same there. Both are
    /// read in the first strip's colour space: two strips of one bar share
    /// it, so their values are compared as captured. A conversion to another
    /// space first widens a difference of one to three (MEASURED 2026-11-15,
    /// T5 run 7, Display P3 read as device RGB).
    public static func sameColumns(_ a: CGImage, _ b: CGImage) -> [Bool]? {
        let space = capturedSpace(of: a)
        guard let p = rgba(a, in: space), let q = rgba(b, in: space), p.width == q.width, p.height == q.height else { return nil }
        return (0..<p.width).map { x in
            for y in 0..<p.height {
                let i = (y * p.width + x) * 4
                for k in 0..<3 where abs(Int(p.pixels[i + k]) - Int(q.pixels[i + k])) > sameChannel { return false }
            }
            return true
        }
    }

    /// The blocks' columns are compared as far as this beside each block.
    public static let blockMargin = 8.0

    /// Whether two strips of one bar are the same background: `equalShare`
    /// of all columns, and of the columns under the blocks (display-local
    /// points, each widened by `blockMargin`), so a change only behind the
    /// members counts. `nil` when they cannot be compared.
    public static func isSameBackground(_ a: CGImage, _ b: CGImage, blocks: [ClosedRange<Double>], scale: Double) -> Bool? {
        guard let same = sameColumns(a, b), !same.isEmpty else { return nil }
        func share(_ columns: [Bool]) -> Double {
            columns.isEmpty ? 1 : Double(columns.filter { $0 }.count) / Double(columns.count)
        }
        let under = same.indices.filter { x in
            let point = (Double(x) + 0.5) / scale
            return blocks.contains { $0.lowerBound - blockMargin <= point && point <= $0.upperBound + blockMargin }
        }
        return share(same) >= equalShare && share(under.map { same[$0] }) >= equalShare
    }

    /// A strip's mean brightness, 0 to 1 (Rec. 709 weights on the values as captured).
    public static func luma(_ image: CGImage) -> Double? {
        guard let strip = rgba(image, in: capturedSpace(of: image)) else { return nil }
        var sum = 0.0
        for index in stride(from: 0, to: strip.pixels.count, by: 4) {
            sum += 0.2126 * Double(strip.pixels[index]) + 0.7152 * Double(strip.pixels[index + 1]) + 0.0722 * Double(strip.pixels[index + 2])
        }
        return sum / Double(strip.width * strip.height) / 255
    }

    /// Plan D2: the bar is transparent when, outside the item slots, a fair
    /// share of columns shows exactly what lies below it (menu titles and
    /// other apps' windows account for the rest). An opaque or blurred bar
    /// matches almost nowhere.
    public static func isTransparent(below: CGImage, onScreen: CGImage, slots: [ClosedRange<Double>], scale: Double) -> Bool {
        guard let same = sameColumns(below, onScreen) else { return false }
        let free = same.indices.filter { x in
            let point = (Double(x) + 0.5) / scale
            return !slots.contains { $0.contains(point) }
        }
        guard !free.isEmpty else { return false }
        return Double(free.filter { same[$0] }.count) >= transparentShare * Double(free.count)
    }
}
