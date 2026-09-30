// Synthetic strips and templates for the oracle's unit tests. Pixels are set
// directly: no AppKit, so each test controls exactly which on- and off-pixels
// differ from the backdrop.
import IceBarOracle
import IceCore

struct Canvas {
    let width: Int
    let height: Int
    let scale: Double
    var bytes: [UInt8]

    init(widthPt: Double = 1728, heightPt: Double = 32, scale: Double = 2, backdrop: (UInt8, UInt8, UInt8) = (40, 40, 40)) {
        width = Int((widthPt * scale).rounded())
        height = Int((heightPt * scale).rounded())
        self.scale = scale
        bytes = [UInt8](repeating: 255, count: width * height * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = backdrop.0
            bytes[i + 1] = backdrop.1
            bytes[i + 2] = backdrop.2
        }
    }

    mutating func set(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let i = (y * width + x) * 4
        bytes[i] = c.0
        bytes[i + 1] = c.1
        bytes[i + 2] = c.2
    }

    /// Paints every alpha >= 128 pixel of `alpha` (a `side` x `side` grid) at
    /// box origin (x0, y0) in `ink`.
    mutating func stamp(_ alpha: [UInt8], side: Int, at x0: Int, _ y0: Int, ink: (UInt8, UInt8, UInt8) = (255, 255, 255)) {
        for y in 0..<side {
            for x in 0..<side where alpha[y * side + x] >= 128 {
                set(x0 + x, y0 + y, ink)
            }
        }
    }

    mutating func fillColumns(_ columns: Range<Int>, _ c: (UInt8, UInt8, UInt8)) {
        for x in columns {
            for y in 0..<height { set(x, y, c) }
        }
    }

    var image: StripImage { StripImage(width: width, height: height, scale: scale, bytes: bytes) }
}

/// A 20 x 20 px test shape: an open bracket (top bar, left post, bottom bar,
/// 2 px strokes) plus a short accent, with empty margin. Distinct enough that
/// a shifted copy of itself never matches.
enum Shapes {
    static let side = 20

    static func bracket() -> [UInt8] {
        var a = [UInt8](repeating: 0, count: side * side)
        func on(_ x: Int, _ y: Int) { a[y * side + x] = 255 }
        for x in 2..<17 { on(x, 2); on(x, 3); on(x, 16); on(x, 17) }
        for y in 2..<18 { on(2, y); on(3, y) }
        for d in 0..<4 { on(6 + d, 12 - d); on(7 + d, 12 - d) }
        return a
    }

    /// The bracket's mirror, so two templates share nothing at the same origin.
    static func mirrored() -> [UInt8] {
        let b = bracket()
        return (0..<(side * side)).map { i in b[(i / side) * side + (side - 1 - i % side)] }
    }

    static func count(_ alpha: [UInt8], _ predicate: (UInt8) -> Bool) -> Int { alpha.filter(predicate).count }
}

extension OracleContext {
    /// The pre-registration's corpus geometry (section 6).
    static func corpus(agentFrames: [PtSpan] = [PtSpan(lo: 1380, hi: 1400)]) -> OracleContext {
        OracleContext(notch: PtSpan(lo: 771.5, hi: 956.5), agentFrames: agentFrames, leftmostReferenceOriginPt: 1317)
    }
}
