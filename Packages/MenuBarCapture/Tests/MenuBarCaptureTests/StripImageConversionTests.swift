import CoreGraphics
import Foundation
import Testing
@testable import MenuBarCapture
import IceCore

@Suite("StripImage(cgImage:geometry:)")
struct StripImageConversionTests {
    /// Builds a CGImage directly from RGBA8 bytes, in the *same* sRGB space
    /// (not `CGColorSpaceCreateDeviceRGB`) the conversion decodes into, so no
    /// colour-matching transform runs during the test and every byte
    /// round-trips exactly.
    static func makeImage(width: Int, height: Int, bytes: [UInt8]) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    @Test("keeps every pixel, top row first, at scale 1")
    func colourRoundTripScale1() {
        // Two rows, two columns, four distinct colours: a row or column swap
        // would fail this test.
        let bytes: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255, // row 0 (top): red, green
            0, 0, 255, 255, 255, 255, 0, 255, // row 1: blue, yellow
        ]
        let image = Self.makeImage(width: 2, height: 2, bytes: bytes)
        let geometry = BarGeometry(widthPt: 2, heightPt: 2, scale: 1, notch: nil)

        let strip = StripImage(cgImage: image, geometry: geometry)

        #expect(strip?.width == 2)
        #expect(strip?.height == 2)
        #expect(strip?.scale == 1)
        #expect(strip?.pixel(x: 0, y: 0) == RGBA(255, 0, 0))
        #expect(strip?.pixel(x: 1, y: 0) == RGBA(0, 255, 0))
        #expect(strip?.pixel(x: 0, y: 1) == RGBA(0, 0, 255))
        #expect(strip?.pixel(x: 1, y: 1) == RGBA(255, 255, 0))
    }

    @Test("cuts 33 captured rows to a 32pt bar at scale 1")
    func cutsToBarHeightScale1() {
        var bytes = [UInt8]()
        for row in 0..<33 {
            // Row `row`'s red channel encodes its own index, so a wrong crop is visible.
            bytes.append(contentsOf: [UInt8(row), 0, 0, 255])
        }
        let image = Self.makeImage(width: 1, height: 33, bytes: bytes)
        let geometry = BarGeometry(widthPt: 1, heightPt: 32, scale: 1, notch: nil)

        let strip = StripImage(cgImage: image, geometry: geometry)

        #expect(strip?.height == 32)
        #expect(strip?.pixel(x: 0, y: 0).r == 0)
        #expect(strip?.pixel(x: 0, y: 31).r == 31)
        // Row 32 -- the one below the bar -- must not survive the crop.
        #expect(!(strip?.bytes.contains(32) ?? true))
    }

    @Test("cuts to the bar height at scale 2 too")
    func cutsToBarHeightScale2() {
        var bytes = [UInt8]()
        for row in 0..<34 {
            bytes.append(contentsOf: [UInt8(row), 0, 0, 255])
        }
        let image = Self.makeImage(width: 1, height: 34, bytes: bytes)
        let geometry = BarGeometry(widthPt: 1, heightPt: 16, scale: 2, notch: nil) // 16pt * 2 = 32px

        let strip = StripImage(cgImage: image, geometry: geometry)

        #expect(strip?.height == 32)
        #expect(strip?.scale == 2)
        #expect(strip?.pixel(x: 0, y: 0).r == 0)
        #expect(strip?.pixel(x: 0, y: 31).r == 31)
        #expect(!(strip?.bytes.contains(32) ?? true))
    }
}
