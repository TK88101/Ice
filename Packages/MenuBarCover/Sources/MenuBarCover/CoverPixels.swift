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

    /// RGBA8 pixels of an image, row-major.
    private static func rgba(_ image: CGImage) -> (width: Int, height: Int, pixels: [UInt8])? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (width, height, pixels) : nil
    }

    /// Per pixel column, whether the two strips are the same there.
    public static func sameColumns(_ a: CGImage, _ b: CGImage) -> [Bool]? {
        guard let p = rgba(a), let q = rgba(b), p.width == q.width, p.height == q.height else { return nil }
        return (0..<p.width).map { x in
            for y in 0..<p.height {
                let i = (y * p.width + x) * 4
                for k in 0..<3 where abs(Int(p.pixels[i + k]) - Int(q.pixels[i + k])) > sameChannel { return false }
            }
            return true
        }
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
