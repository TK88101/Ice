import CoreGraphics
import Foundation
import ImageIO
import IceCore

/// Everything derived once per run: geometry, scale, and the fixed
/// `com.apple.MenuBarAgent` frames from swctl's own baseline record.
struct RunContext {
    let run: RunEvidence
    let geometry: BarGeometry
    let scale: Double
    /// `MenuBarAgent` frames at swctl's own baseline (before any helper
    /// exists) — the fixed system-item set that `FoldWitness`'s one-to-one
    /// rule pairs later readings against. `minY` is not in the record, so it
    /// is set to 0; only `minY < heightPt` is ever tested on an `AgentFrame`,
    /// and 0 always satisfies that.
    let agentBaseline: [AgentFrame]

    init(run: RunEvidence, barHeightPt: Double = 32) throws {
        self.run = run
        let widthPt = try run.screenWidthPt()
        let notch = try run.notchSpan()
        // scale = capture px width / bar width pt, measured from the run's own
        // first capture rather than assumed, so a differently-scaled run would
        // be caught instead of silently mis-decoded.
        guard let anyCapture = Self.firstCaptureName(run) else {
            throw ReplayError.reconstructionFailed("\(run.runId): no capture file referenced anywhere")
        }
        let pxWidth = try Self.pixelWidth(run.captureURL(anyCapture))
        self.scale = Double(pxWidth) / widthPt
        self.geometry = BarGeometry(widthPt: widthPt, heightPt: barHeightPt, scale: scale, notch: PtSpan(lo: notch.lo, hi: notch.hi))

        let baseline = try run.swctlBaseline()
        let items = try baseline.recordArray("items", context: "baseline")
        self.agentBaseline = try items
            .filter { (try? $0.string("id", context: "baseline item")).map { $0.hasPrefix("com.apple.MenuBarAgent") } ?? false }
            .map { item in
                AgentFrame(
                    minX: try item.double("x", context: "baseline agent item"),
                    minY: 0,
                    width: try item.double("w", context: "baseline agent item")
                )
            }
    }

    var heightPx: Int { Int((geometry.heightPt * scale).rounded()) }

    func decode(_ captureName: String) throws -> StripImage {
        guard let image = PNGImage.decode(run.captureURL(captureName), geometry: geometry) else {
            throw ReplayError.decodeFailed(captureName)
        }
        return image
    }

    private static func firstCaptureName(_ run: RunEvidence) -> String? {
        for record in run.records {
            if let capture = record.capture { return capture }
        }
        return nil
    }

    private static func pixelWidth(_ url: URL) throws -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int
        else {
            throw ReplayError.decodeFailed("pixel width of \(url.lastPathComponent)")
        }
        return width
    }
}
