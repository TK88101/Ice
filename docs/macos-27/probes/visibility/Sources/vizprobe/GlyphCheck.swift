// T8a's "glyphs pairwise distinct", checked with IceCore's own baseline
// rules rather than by eye: the three glyphs are rendered the way the bar
// renders a template image (light ink on a dark bar), side by side in one
// synthetic strip, and `StripAssessor.baseline` must accept all three -- in
// particular none may be `notUniqueAtBaseline`, which is what two glyphs
// matching each other would produce. Nothing is drawn on screen.
import AppKit
import IceCore
import VZGlyphs

enum GlyphCheck {
    static let sidePt = 12
    static let scale = 2
    static let heightPt = 24
    static let widthPt = 120
    typealias Placement = (id: String, glyph: Glyph, xPt: Int)
    static let distinctLayout: [Placement] = [("target", .target, 20), ("reference", .reference, 50), ("alt", .alt, 80)]
    /// The negative control: the same glyph twice must be refused as not
    /// unique, or the check above proves nothing.
    static let twinLayout: [Placement] = [("target", .target, 20), ("twin", .target, 50), ("reference", .reference, 80)]
    static let backdrop: (r: Double, g: Double, b: Double) = (40, 40, 40)
    static let ink: (r: Double, g: Double, b: Double) = (255, 255, 255)

    /// Passes when the three glyphs are all accepted and the twin control's
    /// two identical glyphs are both refused as not unique.
    static func run(parameters: DetectorParameters = .preRegistered) -> (passed: Bool, lines: [String]) {
        guard let distinct = baseline(distinctLayout, parameters: parameters),
              let twins = baseline(twinLayout, parameters: parameters)
        else { return (false, ["glyph check: could not render the glyphs"]) }

        var lines = ["glyph check: accepted \(distinct.acceptedIDs.sorted())"]
        for (id, rejection) in distinct.rejections.sorted(by: { $0.key < $1.key }) {
            lines.append("glyph check: rejected \(id) -- \(rejection)")
        }
        let distinctOK = Set(distinct.acceptedIDs) == Set(distinctLayout.map(\.id)) && distinct.rejections.isEmpty
        let controlOK = twins.rejections["target"] == .notUniqueAtBaseline && twins.rejections["twin"] == .notUniqueAtBaseline
        lines.append("glyph check (negative control, the target glyph twice): target=\(twins.rejections["target"].map { "\($0)" } ?? "accepted") twin=\(twins.rejections["twin"].map { "\($0)" } ?? "accepted")")
        let passed = distinctOK && controlOK
        lines.append("glyph check: \(passed ? "pairwise distinct under StripAssessor's rules, and the twin control is refused" : "FAILED")")
        return (passed, lines)
    }

    private static func baseline(_ layout: [Placement], parameters: DetectorParameters) -> BaselineResult? {
        let geometry = BarGeometry(widthPt: Double(widthPt), heightPt: Double(heightPt), scale: Double(scale), notch: nil)
        guard let strip = strip(layout) else { return nil }

        var frames = [String: ItemFrame]()
        for placement in layout {
            frames[placement.id] = ItemFrame(id: placement.id, minX: Double(placement.xPt), minY: 0, width: Double(sidePt), height: Double(heightPt))
        }
        // One MenuBarAgent frame right of the glyphs, as on the real bar (the
        // clock): the fold witness reads the fold against the agent's items,
        // and with none at all every baseline reads the fold as not absent.
        let agent = [AgentFrame(minX: 104, minY: 0, width: 12)]
        let samples = (0..<5).map { ObservationSample(time: Double($0), before: strip, after: strip, agentFrames: agent, itemFrames: frames) }
        return StripAssessor.baseline(samples: samples, geometry: geometry, parameters: parameters)
    }

    private static func strip(_ layout: [Placement]) -> StripImage? {
        let widthPx = widthPt * scale
        let heightPx = heightPt * scale
        var bytes = [UInt8](repeating: 255, count: widthPx * heightPx * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = UInt8(backdrop.r)
            bytes[i + 1] = UInt8(backdrop.g)
            bytes[i + 2] = UInt8(backdrop.b)
        }
        let sidePx = sidePt * scale
        let top = (heightPx - sidePx) / 2
        for placement in layout {
            guard let coverage = coverage(placement.glyph) else { return nil }
            let left = placement.xPt * scale
            for y in 0..<sidePx {
                for x in 0..<sidePx {
                    let alpha = coverage[y * sidePx + x]
                    let i = ((top + y) * widthPx + (left + x)) * 4
                    bytes[i] = UInt8((backdrop.r + (ink.r - backdrop.r) * alpha).rounded())
                    bytes[i + 1] = UInt8((backdrop.g + (ink.g - backdrop.g) * alpha).rounded())
                    bytes[i + 2] = UInt8((backdrop.b + (ink.b - backdrop.b) * alpha).rounded())
                }
            }
        }
        return StripImage(width: widthPx, height: heightPx, scale: Double(scale), bytes: bytes)
    }

    /// The glyph's alpha, row by row from the top, at `scale`.
    private static func coverage(_ glyph: Glyph) -> [Double]? {
        let sidePx = sidePt * scale
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sidePx, pixelsHigh: sidePx, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: sidePx * 4, bitsPerPixel: 32)
        else { return nil }
        // The point size first: a context made before it draws 1 pt as 1 px,
        // i.e. the glyph at half the bar's scale.
        rep.size = NSSize(width: sidePt, height: sidePt)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        Glyphs.image(glyph, side: CGFloat(sidePt)).draw(in: NSRect(x: 0, y: 0, width: sidePt, height: sidePt))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return nil }
        return (0..<(sidePx * sidePx)).map { Double(data[$0 * 4 + 3]) / 255 }
    }
}
