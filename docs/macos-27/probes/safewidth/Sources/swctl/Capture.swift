// Strip capture: the screencapture CLI with a hard deadline, decoded with ImageIO
// into a plain RGBA buffer that SafeWidthCore can read.
//
// CGWindowListCreateImage and CGDisplayCreateImage are obsoleted in this SDK, and
// the CLI runs under the terminal's Screen Recording grant, which is already in
// place on this machine. Each capture is a separate process, so a stuck capture is
// killed rather than waited on.
import Foundation
import ImageIO
import CoreGraphics
import SafeWidthCore

struct StripCapture {
    /// The menu bar's height on this display (safeAreaInsets.top). Anything below
    /// it belongs to whatever window sits under the bar and changes with it, so
    /// every decoded strip is cut to this height — B0's 33 pt captures included.
    static let barHeightPt = 32

    /// Width and height of the captured strip, points.
    let widthPt: Int
    let heightPt: Int
    /// A capture that has not finished within this many seconds is killed.
    let deadline: TimeInterval
    /// Where the most recent capture is written. Overwritten every time; the
    /// evidence writer copies the ones worth keeping.
    let scratchFile: URL

    struct Frame {
        let bitmap: Bitmap
        let started: TimeInterval
        let finished: TimeInterval
        let file: URL
    }

    func capture(clock: () -> TimeInterval) -> Frame? {
        let started = clock()
        try? FileManager.default.removeItem(at: scratchFile)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "png", "-R", "0,0,\(widthPt),\(heightPt)", scratchFile.path]
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        if done.wait(timeout: .now() + deadline) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0, let bitmap = Self.decode(scratchFile, widthPt: widthPt) else {
            return nil
        }
        return Frame(bitmap: bitmap, started: started, finished: clock(), file: scratchFile)
    }

    /// Decodes a PNG into sRGB RGBA8. Every capture goes through the same
    /// conversion, so colours are comparable across captures even though they are
    /// not the display's native values.
    static func decode(_ url: URL, widthPt: Int) -> Bitmap? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return nil
        }
        let scale = Double(width) / Double(widthPt)
        let full = Bitmap(width: width, height: height, scale: scale, bytes: bytes)
        let barRows = min(height, Int((Double(barHeightPt) * scale).rounded()))
        return full.crop(x: 0, y: 0, width: width, height: barRows)
    }
}
