import CoreGraphics
import IceCore

extension StripImage {
    /// Decodes `cgImage` into sRGB RGBA8, premultiplied-last, and cuts the
    /// result to `geometry.heightPx`: the row below the bar belongs to
    /// whatever window sits under it, not to the bar itself
    /// (docs/plans/2026-09-19-visibility-adapter.md section 4;
    /// probes/safewidth Deviation 3, the same crop this mirrors).
    ///
    /// `nil` when the image cannot be decoded into a bitmap context, or
    /// decodes to no usable rows.
    public init?(cgImage: CGImage, geometry: BarGeometry) {
        let width = cgImage.width
        let sourceHeight = cgImage.height
        guard width > 0, sourceHeight > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: width * sourceHeight * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: sourceHeight,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: sourceHeight))
            return true
        }
        guard drawn else { return nil }

        let heightPx = min(sourceHeight, geometry.heightPx)
        guard heightPx > 0 else { return nil }
        let bytesPerRow = width * 4
        let cropped = heightPx == sourceHeight ? bytes : Array(bytes[0..<(heightPx * bytesPerRow)])
        self.init(width: width, height: heightPx, scale: geometry.scale, bytes: cropped)
    }
}
