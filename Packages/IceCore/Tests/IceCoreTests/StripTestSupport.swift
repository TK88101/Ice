@testable import IceCore

/// Colours for synthetic menu bar strips. The bar is translucent in real life, so
/// the tests paint several backdrops under the same glyphs.
enum Paint {
    static let darkBar = RGBA(40, 40, 40)
    static let redBar = RGBA(200, 60, 60)
    static let lightBar = RGBA(225, 225, 225)
    static let midGrey = RGBA(128, 128, 128)
    static let white = RGBA(255, 255, 255)
    static let black = RGBA(0, 0, 0)
}

/// A glyph drawn at pixel resolution: `#` is ink, anything else is left alone.
struct Glyph {
    let rows: [String]

    var widthPx: Int { rows.map(\.count).max() ?? 0 }
    var heightPx: Int { rows.count }

    /// Asymmetric, so it matches itself in exactly one place.
    static let flag = Glyph(rows: [
        "##########",
        "##########",
        "##......##",
        "##......##",
        "##########",
        "##########",
        "##........",
        "##........",
        "##........",
        "##........",
    ])

    /// A different shape of the same size, for "another item".
    static let box = Glyph(rows: [
        "##########",
        "##########",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##########",
        "##########",
    ])

    /// Two thin strokes: little ink, a lot of background.
    static let thin = Glyph(rows: [
        "#.........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "..........",
        "........#.",
    ])
}

/// A mutable synthetic strip, top row first, RGBA8.
struct Canvas {
    let widthPt: Int
    let heightPt: Int
    let scale: Int
    private(set) var bytes: [UInt8]

    init(widthPt: Int = 200, heightPt: Int = 12, scale: Int = 2, backdrop: RGBA = Paint.darkBar) {
        self.widthPt = widthPt
        self.heightPt = heightPt
        self.scale = scale
        let count = widthPt * scale * heightPt * scale
        var bytes = [UInt8]()
        bytes.reserveCapacity(count * 4)
        for _ in 0..<count {
            bytes.append(contentsOf: [backdrop.r, backdrop.g, backdrop.b, backdrop.a])
        }
        self.bytes = bytes
    }

    var widthPx: Int { widthPt * scale }
    var heightPx: Int { heightPt * scale }

    mutating func set(x: Int, y: Int, _ colour: RGBA) {
        guard x >= 0, x < widthPx, y >= 0, y < heightPx else { return }
        let i = (y * widthPx + x) * 4
        bytes[i] = colour.r
        bytes[i + 1] = colour.g
        bytes[i + 2] = colour.b
        bytes[i + 3] = colour.a
    }

    mutating func fill(xPx: Range<Int>, yPx: Range<Int>, _ colour: RGBA) {
        for y in yPx {
            for x in xPx {
                set(x: x, y: y, colour)
            }
        }
    }

    /// Draws the glyph with its left edge at `xPt`, vertically centred.
    mutating func draw(_ glyph: Glyph, atPt xPt: Double, colour: RGBA = Paint.white) {
        let x0 = Int((xPt * Double(scale)).rounded())
        let y0 = (heightPx - glyph.heightPx) / 2
        for (dy, row) in glyph.rows.enumerated() {
            for (dx, char) in row.enumerated() where char == "#" {
                set(x: x0 + dx, y: y0 + dy, colour)
            }
        }
    }

    var image: StripImage {
        StripImage(width: widthPx, height: heightPx, scale: Double(scale), bytes: bytes)
    }

    func geometry(notch: PtSpan? = nil) -> BarGeometry {
        BarGeometry(widthPt: Double(widthPt), heightPt: Double(heightPt), scale: Double(scale), notch: notch)
    }
}

extension Glyph {
    /// The glyph's width in points at the given scale.
    func widthPt(scale: Int) -> Double { Double(widthPx) / Double(scale) }
}
