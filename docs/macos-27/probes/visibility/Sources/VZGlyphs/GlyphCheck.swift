// T8a's "glyphs pairwise distinct", checked with IceCore's own baseline
// rules rather than by eye: every glyph is rendered the way the bar
// renders a template image (light ink on a dark bar), side by side in one
// synthetic strip, and `StripAssessor.baseline` must accept all of them -- in
// particular none may be `notUniqueAtBaseline`, which is what two glyphs
// matching each other would produce. Nothing is drawn on screen.
import AppKit
import IceCore

public enum GlyphCheck {
    static let sidePt = 12
    static let scale = 2
    static let heightPt = 24
    static let pitchPt = 30
    /// Room for every glyph at `pitchPt`, then the agent frame.
    static let widthPt = 20 + pitchPt * Glyph.allCases.count + 30
    typealias Placement = (id: String, glyph: Glyph, xPt: Int)
    /// Every glyph: C2's three hidden-section glyphs (T2) and route C's
    /// thirteen (2026-10-01 instrument plan, T2).
    static let distinctLayout: [Placement] = Glyph.allCases.enumerated().map { index, glyph in
        (glyph.rawValue, glyph, 20 + pitchPt * index)
    }
    /// The negative control: the same glyph twice must be refused as not
    /// unique, or the check above proves nothing.
    static let twinLayout: [Placement] = [("target", .target, 20), ("twin", .target, 50), ("reference", .reference, 80)]
    static let backdrop: (r: Double, g: Double, b: Double) = (40, 40, 40)
    static let ink: (r: Double, g: Double, b: Double) = (255, 255, 255)

    /// Passes when every glyph is accepted and the twin control's
    /// two identical glyphs are both refused as not unique.
    public static func run(parameters: DetectorParameters = .preRegistered) -> (passed: Bool, lines: [String]) {
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
        let agent = [AgentFrame(minX: Double(widthPt - 20), minY: 0, width: 12)]
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
        guard let rendered = try? GlyphRenderer.coverage(glyph, scale: scale) else { return nil }
        return rendered.alpha.map { Double($0) / 255 }
    }
}
