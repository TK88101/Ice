// Encodes a `StripImage` back to PNG for the evidence directory -- the
// mirror of MenuBarCapture's `StripImage(cgImage:geometry:)` decode and of
// vzreplay's `PNGImage.decode`. IceCore itself must stay free of
// CoreGraphics/ImageIO (plan section 2; `Packages/IceCore/Package.swift`);
// this lives in vizprobe, an adapter like MenuBarCapture, so the restriction
// does not reach here.
import CoreGraphics
import Foundation
import ImageIO
import IceCore
import UniformTypeIdentifiers

enum StripImagePNGError: Error {
    case encodeFailed
}

extension StripImage {
    /// Writes this capture as a PNG at `url`. `bytes` is already sRGB RGBA8,
    /// premultiplied-last, row-major, top row first -- exactly what
    /// `CGContext` below expects, so this is a plain round trip of the
    /// decode in MenuBarCapture's `StripImage+CGImage.swift`.
    func writePNG(to url: URL) throws {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw StripImagePNGError.encodeFailed
        }
        var mutableBytes = bytes
        let cgImage: CGImage? = mutableBytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }
            return context.makeImage()
        }
        guard let cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw StripImagePNGError.encodeFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw StripImagePNGError.encodeFailed
        }
    }
}
