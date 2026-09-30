// The fake bar's pixel renderer and AX-frame convention, moved out of
// `FakeBarWorld.swift` (C2 T3) to keep that file under the 800-line cap.
import IceCore

extension FakeBarWorld {
    static func render(_ glyphs: [(shape: [String], atPt: Double)]) -> StripImage {
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

    /// The trimmed (detector-facing) AX frame a glyph at `atPt` reads at --
    /// one point narrower than its own ink on each side, the same
    /// convention `TestBar.frame` uses.
    static func frame(atPt xPt: Double, width: Double = 7) -> BarRect {
        BarRect(minX: xPt - 1, minY: 0, width: width, height: Double(heightPt))
    }
}
