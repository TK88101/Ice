// The oracle's glyph renderings (docs/plans/2026-09-30-icebar-c-prereg.md
// section 5, "Rendering"): each glyph's coverage alpha, drawn offline by the
// helpers' own drawing code (`Glyphs.image`) at scale 1 or 2. Derived from
// what `GlyphCheck.coverage` did at its fixed scale 2, which it now calls.
import AppKit

/// One glyph drawn into a `sidePx` x `sidePx` bitmap, rows from the top.
public struct GlyphCoverage: Equatable, Sendable {
    public let glyph: Glyph
    public let scale: Int
    public let sidePx: Int
    /// Alpha per pixel, 0...255.
    public let alpha: [UInt8]
    /// The coloured variant's unpremultiplied RGB, 3 bytes per pixel; nil for
    /// the ordinary (template) variant, whose colour the bar decides.
    public let rgb: [UInt8]?

    /// Section 5's on-set P: alpha >= 0.5. Pixel indices, row-major.
    public var onSet: [Int] { alpha.indices.filter { alpha[$0] >= 128 } }
    /// Section 5's off-set Q: alpha = 0 inside the glyph's box.
    public var offSet: [Int] { alpha.indices.filter { alpha[$0] == 0 } }
}

public enum GlyphRenderer {
    public static let sidePt = 12
    public static let supportedScales = 1...2

    public enum Failure: Error, Equatable {
        case unsupportedScale(Int)
        case bitmapUnavailable
    }

    public static func coverage(_ glyph: Glyph, scale: Int, coloured: Bool = false) throws(Failure) -> GlyphCoverage {
        guard supportedScales.contains(scale) else { throw .unsupportedScale(scale) }
        let sidePx = sidePt * scale
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sidePx, pixelsHigh: sidePx, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: sidePx * 4, bitsPerPixel: 32)
        else { throw .bitmapUnavailable }
        // The point size first: a context made before it draws 1 pt as 1 px.
        rep.size = NSSize(width: sidePt, height: sidePt)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw .bitmapUnavailable }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        Glyphs.image(glyph, side: CGFloat(sidePt), coloured: coloured).draw(in: NSRect(x: 0, y: 0, width: sidePt, height: sidePt))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { throw .bitmapUnavailable }

        let count = sidePx * sidePx
        let alpha = (0..<count).map { data[$0 * 4 + 3] }
        let rgb: [UInt8]? = coloured ? (0..<count).flatMap { i in
            (0..<3).map { c in unpremultiply(data[i * 4 + c], alpha: alpha[i]) }
        } : nil
        return GlyphCoverage(glyph: glyph, scale: scale, sidePx: sidePx, alpha: alpha, rgb: rgb)
    }

    private static func unpremultiply(_ value: UInt8, alpha: UInt8) -> UInt8 {
        guard alpha > 0 else { return 0 }
        return UInt8(min(255, (Double(value) * 255 / Double(alpha)).rounded()))
    }
}
