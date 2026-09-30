// PNG in and out, sha256, and the seeded generator for the corpus.
import CoreGraphics
import CryptoKit
import Foundation
import IceCore
import ImageIO
import UniformTypeIdentifiers

public enum CorpusError: Error, Equatable {
    case unreadableImage(String)
    case unwritableImage
    case missingRendering(String)
    case hashMismatch(String)
}

public enum Digest {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(_ bytes: [UInt8]) -> String { sha256(Data(bytes)) }
}

/// RGBA8, top row first, the layout `StripImage` uses. Encoded without
/// premultiplication in sRGB so a round trip keeps every byte (alpha is 255).
public enum PNGIO {
    public static func encode(_ image: StripImage) throws -> Data {
        guard let provider = CGDataProvider(data: Data(image.bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: image.width * 4, space: space,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw CorpusError.unwritableImage }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CorpusError.unwritableImage
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw CorpusError.unwritableImage }
        return data as Data
    }

    /// Draws the PNG into its own colour space (no conversion) at `scale`.
    public static func decode(_ data: Data, scale: Double = 1) throws -> StripImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CorpusError.unreadableImage("not an image") }
        let width = cgImage.width
        let height = cgImage.height
        let space = cgImage.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw CorpusError.unreadableImage("no bitmap context") }
        return StripImage(width: width, height: height, scale: scale, bytes: bytes)
    }
}

/// SplitMix64, seeded from the item id (FNV-1a), so every item's noise is
/// fixed by its id alone.
struct SeededRandom {
    private var state: UInt64

    init(id: String) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `range` (both ends included).
    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
}
