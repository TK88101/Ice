import IceCore
import MenuBarCapture

/// A minimal synthetic bar strip for `HidingVerification`'s tests: enough
/// real drawing to give IceCore's rules an actual glyph to accept and match,
/// without going through `CGImage` at all (that conversion has its own tests
/// in MenuBarCapture). Shaped after, but generalised beyond,
/// `Packages/MenuBarCapture/Tests/MenuBarCaptureTests/TestBar.swift` (a
/// frozen package's test target, not importable from here): that file draws
/// exactly one target and one reference; this one draws an arbitrary set of
/// named, independently movable/toggleable glyphs, which T7's multi-item
/// cases (two adjacent targets, a moved target, a moved indicator) need.
enum TestBar {
    static let widthPt = 300
    static let heightPt = 12
    static let scale = 2
    static let backdrop = RGBA(40, 40, 40)
    static let ink = RGBA(255, 255, 255)

    static var geometry: BarGeometry {
        BarGeometry(widthPt: Double(widthPt), heightPt: Double(heightPt), scale: Double(scale), notch: nil)
    }

    /// The (trimmed, detector-facing) frame a glyph drawn at `atPt` would be
    /// read at -- one point narrower than its own ink on each side, matching
    /// `CheckFrames.trim`'s convention.
    static func frame(id: String, atPt xPt: Double, width: Double = 7) -> ItemFrame {
        ItemFrame(id: id, minX: xPt - 1, minY: 0, width: width, height: Double(heightPt))
    }

    /// Asymmetric, so it matches itself in exactly one place.
    static let shapeA: [String] = [
        "##########",
        "##........",
        "##........",
        "##........",
        "##########",
        "##########",
        "........##",
        "........##",
        "........##",
        "##########",
    ]

    /// A hollow box -- a different shape, so a whole-strip search never
    /// confuses one glyph with another.
    static let shapeB: [String] = [
        "##########",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##########",
    ]

    /// A cross -- a third distinct shape.
    static let shapeC: [String] = [
        "...##.....",
        "...##.....",
        "...##.....",
        "##########",
        "##########",
        "##########",
        "##########",
        "...##.....",
        "...##.....",
        "...##.....",
    ]

    /// Builds a strip with each `(shape, atPt)` pair drawn at its point.
    /// Leaving a glyph out of the list is how a test "hides" it.
    static func image(_ glyphs: [(shape: [String], atPt: Double)]) -> StripImage {
        let widthPx = widthPt * scale
        let heightPx = heightPt * scale
        var bytes = [UInt8](repeating: 0, count: widthPx * heightPx * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = backdrop.r
            bytes[i + 1] = backdrop.g
            bytes[i + 2] = backdrop.b
            bytes[i + 3] = 255
        }

        for (shape, xPt) in glyphs {
            let x0 = Int((xPt * Double(scale)).rounded())
            let y0 = (heightPx - shape.count) / 2
            for (dy, row) in shape.enumerated() {
                for (dx, char) in row.enumerated() where char == "#" {
                    let x = x0 + dx
                    let y = y0 + dy
                    guard x >= 0, x < widthPx, y >= 0, y < heightPx else { continue }
                    let i = (y * widthPx + x) * 4
                    bytes[i] = ink.r
                    bytes[i + 1] = ink.g
                    bytes[i + 2] = ink.b
                    bytes[i + 3] = 255
                }
            }
        }
        return StripImage(width: widthPx, height: heightPx, scale: Double(scale), bytes: bytes)
    }
}
