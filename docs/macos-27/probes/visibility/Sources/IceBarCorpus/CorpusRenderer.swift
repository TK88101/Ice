// Draws a spec: backdrop, glyphs by their coverage, chevrons, the capsule over
// them, the notch black (readings D4, D20-D23). K items are read, not drawn.
import Foundation
import IceBarOracle
import IceCore
import VZGlyphs

public struct CorpusItem: Sendable {
    public let spec: ItemSpec
    public let image: StripImage
    public var context: OracleContext { spec.context }
}

public enum CorpusRenderer {
    /// Freeze 1 seeded by id alone; later corpora prefix a salt (deviation 2 C6).
    static func seed(salt: String, id: String) -> String { salt.isEmpty ? id : "\(salt)|\(id)" }

    public static func render(_ spec: ItemSpec, templates: CorpusTemplates, kDirectory: URL = KCaptures.directory) throws -> CorpusItem {
        if let file = spec.recorded {
            let data = try Data(contentsOf: kDirectory.appendingPathComponent(file))
            return CorpusItem(spec: spec, image: try PNGIO.decode(data, scale: Double(spec.scale)))
        }
        var canvas = Canvas(scale: spec.scale)
        canvas.fill(spec.backdrop, seed: seed(salt: spec.seedSalt, id: spec.id))
        for placed in spec.glyphs {
            let coloured = placed.ink == .coloured
            let coverage = try templates.coverage(placed.glyph, scale: spec.scale, coloured: coloured)
            canvas.composite(alpha: coverage.alpha, side: coverage.sidePx, at: placed.xPx, placed.yPx, factor: placed.alphaFactor) { i in
                switch placed.ink {
                case let .solid(rgb): return rgb
                case .coloured:
                    let rgb = coverage.rgb ?? []
                    return RGB(rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2])
                }
            }
        }
        let chevron = templates.chevron
        for placed in spec.chevrons {
            canvas.composite(alpha: chevron.alpha, width: chevron.width, height: chevron.height, at: placed.xPx, placed.yPx, factor: 1) { _ in .grey(255) }
        }
        canvas.capsule(xPt: spec.capsuleXPt)
        canvas.notch()
        return CorpusItem(spec: spec, image: StripImage(width: canvas.width, height: canvas.height, scale: Double(spec.scale), bytes: canvas.bytes))
    }
}

struct Canvas {
    let scale: Int
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(scale: Int) {
        self.scale = scale
        width = CorpusGeometry.widthPx(scale: scale)
        height = CorpusGeometry.heightPx(scale: scale)
        bytes = [UInt8](repeating: 255, count: width * height * 4)
    }

    mutating func set(_ x: Int, _ y: Int, _ c: RGB) {
        let i = (y * width + x) * 4
        bytes[i] = c.r
        bytes[i + 1] = c.g
        bytes[i + 2] = c.b
    }

    func get(_ x: Int, _ y: Int) -> RGB {
        let i = (y * width + x) * 4
        return RGB(bytes[i], bytes[i + 1], bytes[i + 2])
    }

    mutating func fill(_ backdrop: Backdrop, seed: String) {
        var rng = SeededRandom(id: seed)
        let lattice = valueLattice(backdrop, rng: &rng)
        for y in 0..<height {
            for x in 0..<width {
                set(x, y, colour(backdrop, x: x, y: y, rng: &rng, lattice: lattice))
            }
        }
    }

    private func colour(_ backdrop: Backdrop, x: Int, y: Int, rng: inout SeededRandom, lattice: ValueLattice?) -> RGB {
        switch backdrop {
        case let .uniform(c):
            return c
        case let .noise6(c):
            return .grey(clamp(Double(c.r) + Double(rng.int(in: -6...6))))
        case let .gradientX(from, to):
            return .grey(clamp(Double(from) + Double(to - from) * Double(x) / Double(width - 1)))
        case .valueNoise:
            return .grey(clamp(90 + (lattice?.value(x: x, y: y) ?? 0)))
        case .diagonal:
            return .grey(clamp(40 + 70 * Double(x + y) / Double(width - 1 + height - 1)))
        case .blueOrange:
            let t = Double(x) / Double(width - 1)
            return RGB(clamp(40 + 180 * t), clamp(80 + 40 * t), clamp(200 - 160 * t))
        }
    }

    private func valueLattice(_ backdrop: Backdrop, rng: inout SeededRandom) -> ValueLattice? {
        guard case let .valueNoise(amplitude) = backdrop else { return nil }
        let step = 8 * scale
        let columns = width / step + 2
        let rows = height / step + 2
        let values = (0..<(columns * rows)).map { _ in Double(rng.int(in: -amplitude...amplitude)) }
        return ValueLattice(step: step, columns: columns, values: values)
    }

    /// Source-over: out = backdrop * (1 - a) + ink * a, a = alpha / 255 x factor.
    mutating func composite(alpha: [UInt8], side: Int, at x0: Int, _ y0: Int, factor: Double, ink: (Int) -> RGB) {
        composite(alpha: alpha, width: side, height: side, at: x0, y0, factor: factor, ink: ink)
    }

    mutating func composite(alpha: [UInt8], width w: Int, height h: Int, at x0: Int, _ y0: Int, factor: Double, ink: (Int) -> RGB) {
        for gy in 0..<h {
            for gx in 0..<w {
                let x = x0 + gx
                let y = y0 + gy
                let i = gy * w + gx
                guard x >= 0, x < width, y >= 0, y < height, alpha[i] > 0 else { continue }
                let a = Double(alpha[i]) / 255 * factor
                let under = get(x, y)
                let over = ink(i)
                set(x, y, RGB(blend(under.r, over.r, a), blend(under.g, over.g, a), blend(under.b, over.b, a)))
            }
        }
    }

    /// D23: a 20 x 18 pt stadium, vertically centred, pixel centres inside.
    mutating func capsule(xPt: Double) {
        let s = Double(scale)
        let radius = CorpusGeometry.capsuleHeightPt / 2
        let centreY = Double(CorpusGeometry.heightPt) / 2
        let left = xPt + radius
        let right = xPt + CorpusGeometry.capsuleWidthPt - radius
        for y in 0..<height {
            for x in 0..<width {
                let px = (Double(x) + 0.5) / s
                let py = (Double(y) + 0.5) / s
                let nearestX = min(max(px, left), right)
                let dx = px - nearestX
                let dy = py - centreY
                if dx * dx + dy * dy <= radius * radius { set(x, y, CorpusGeometry.capsuleColour) }
            }
        }
    }

    /// D4: the camera housing captures as pure black.
    mutating func notch() {
        for x in CorpusGeometry.notchColumns(scale: scale) {
            for y in 0..<height { set(x, y, .grey(0)) }
        }
    }
}

struct ValueLattice {
    let step: Int
    let columns: Int
    let values: [Double]

    /// Bilinear between lattice nodes with smoothstep weights.
    func value(x: Int, y: Int) -> Double {
        let fx = Double(x) / Double(step)
        let fy = Double(y) / Double(step)
        let ix = Int(fx)
        let iy = Int(fy)
        let tx = smooth(fx - Double(ix))
        let ty = smooth(fy - Double(iy))
        func node(_ cx: Int, _ cy: Int) -> Double { values[cy * columns + cx] }
        let top = node(ix, iy) * (1 - tx) + node(ix + 1, iy) * tx
        let bottom = node(ix, iy + 1) * (1 - tx) + node(ix + 1, iy + 1) * tx
        return top * (1 - ty) + bottom * ty
    }

    private func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}

private func clamp(_ v: Double) -> UInt8 { UInt8(min(255, max(0, v.rounded()))) }

private func blend(_ under: UInt8, _ over: UInt8, _ a: Double) -> UInt8 {
    clamp(Double(under) * (1 - a) + Double(over) * a)
}
