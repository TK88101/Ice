// Synthetic bars for the claim's tests (docs/plans/2026-10-02-icebar-c-claim.md).
// Pixels are set directly, and the frozen baseline is IceCore's own
// `StripAssessor.baseline` run on them, so every refusal a test provokes is
// provoked against the real frozen detector, not a stand-in.
@testable import IceBarClaim
import IceBarOracle
import IceCore

typealias RGB3 = (UInt8, UInt8, UInt8)

struct Strip {
    let width: Int
    let height: Int
    let scale: Double
    var bytes: [UInt8]

    init(widthPt: Double = Bar.widthPt, heightPt: Double = Bar.heightPt, scale: Double = 2, backdrop: RGB3 = Bar.dark) {
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

    mutating func set(_ x: Int, _ y: Int, _ c: RGB3) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let i = (y * width + x) * 4
        bytes[i] = c.0
        bytes[i + 1] = c.1
        bytes[i + 2] = c.2
    }

    /// Fills columns `xs` over rows `ys` (every row by default).
    mutating func fill(_ xs: Range<Int>, rows ys: Range<Int>? = nil, _ c: RGB3) {
        for x in xs {
            for y in ys ?? 0..<height { set(x, y, c) }
        }
    }

    /// Paints every alpha >= 128 pixel of a `side` x `side` grid at (x0, y0).
    mutating func stamp(_ alpha: [UInt8], side: Int = Shapes.side, at x0: Int, _ y0: Int = Bar.glyphY, ink: RGB3 = Bar.white) {
        for y in 0..<side {
            for x in 0..<side where alpha[y * side + x] >= 128 {
                set(x0 + x, y0 + y, ink)
            }
        }
    }

    /// Paints `count` pixels, 4 per row, from (x0, y0): one 8-connected cluster.
    mutating func block(_ count: Int, at x0: Int, _ y0: Int, _ c: RGB3) {
        for i in 0..<count { set(x0 + i % 4, y0 + i / 4, c) }
    }

    var image: StripImage { StripImage(width: width, height: height, scale: scale, bytes: bytes) }
}

/// 20 x 20 px shapes, 2 px strokes, pairwise distinct under the oracle's full
/// rule and never matching a shifted copy of themselves.
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

    static func mirrored() -> [UInt8] {
        let b = bracket()
        return (0..<(side * side)).map { i in b[(i / side) * side + (side - 1 - i % side)] }
    }

    /// A T with a foot on the right: no left post, no top-right corner.
    static func tee() -> [UInt8] {
        var a = [UInt8](repeating: 0, count: side * side)
        func on(_ x: Int, _ y: Int) { a[y * side + x] = 255 }
        for x in 3..<17 { on(x, 3); on(x, 4) }
        for y in 3..<17 { on(9, y); on(10, y) }
        for x in 11..<15 { on(x, 15); on(x, 16) }
        return a
    }
}

/// A 400 x 24 pt bar at scale 2: notch 100-160 pt, the references `reference`
/// (300 pt) and `alt` (330 pt), a visible `target` (350 pt), and two
/// `MenuBarAgent` items right of them. Rule 1's region is 160 ..< 300 pt,
/// columns 320 ..< 600.
enum Bar {
    static let widthPt = 400.0
    static let heightPt = 24.0
    static let scale = 2.0
    static let notch = PtSpan(lo: 100, hi: 160)
    static let geometry = BarGeometry(widthPt: widthPt, heightPt: heightPt, scale: scale, notch: notch)
    static let dark: RGB3 = (40, 40, 40)
    static let white: RGB3 = (255, 255, 255)
    static let glyphY = 14
    static let notchColumns = 200..<320
    static let regionColumns = 320..<600
    static let agentFrames = [AgentFrame(minX: 370, minY: 0, width: 12), AgentFrame(minX: 386, minY: 0, width: 8)]
    static let references = ["reference", "alt"]

    static let slots: [(id: String, xPt: Double, alpha: [UInt8])] = [
        ("reference", 300, Shapes.bracket()), ("alt", 330, Shapes.mirrored()), ("target", 350, Shapes.tee()),
    ]

    static var visible: [OracleTemplate] {
        slots.map { OracleTemplate(id: $0.id, width: Shapes.side, height: Shapes.side, alpha: $0.alpha, scale: scale) }
    }

    static var itemFrames: [String: ItemFrame] {
        Dictionary(uniqueKeysWithValues: slots.prefix(2).map {
            ($0.id, ItemFrame(id: $0.id, minX: $0.xPt, minY: 0, width: 10, height: heightPt))
        })
    }

    /// The hidden-state bar: dark backdrop, black notch, the three visible
    /// helpers drawn; `targetInk` sets the target's ink (the contrast gate).
    static func strip(backdrop: RGB3 = dark, targetInk: RGB3 = white) -> Strip {
        var strip = Strip(backdrop: backdrop)
        strip.fill(notchColumns, (0, 0, 0))
        for slot in slots {
            strip.stamp(slot.alpha, at: Int(slot.xPt * scale), ink: slot.id == "target" ? targetInk : white)
        }
        return strip
    }

    /// Five samples 1 s apart, the same image in both captures unless `images`
    /// gives one per capture (10), and `reads` one agent read per sample.
    static func samples(_ image: StripImage, images: [StripImage]? = nil, reads: [[AgentFrame]]? = nil) -> [ObservationSample] {
        (0..<5).map { i in
            ObservationSample(
                time: Double(i),
                before: images?[2 * i] ?? image,
                after: images?[2 * i + 1] ?? image,
                agentFrames: reads?[i] ?? agentFrames,
                itemFrames: itemFrames
            )
        }
    }

    /// A grey of level `v` on every channel.
    static func level(_ v: Int) -> RGB3 { (UInt8(v), UInt8(v), UInt8(v)) }

    /// The dark backdrop raised by `d` on every channel.
    static func grey(_ d: Int) -> RGB3 { level(40 + d) }

    /// One attempt: six equal captures.
    static func six(_ image: StripImage) -> [StripImage] { Array(repeating: image, count: 6) }

    /// Ten capture images, all `base` except capture `index` (0...9).
    static func captures(_ base: StripImage, replacing index: Int, with other: StripImage) -> [StripImage] {
        (0..<10).map { $0 == index ? other : base }
    }

    static func frozen(_ samples: [ObservationSample]) -> BaselineResult {
        StripAssessor.baseline(samples: samples, geometry: geometry, parameters: .preRegistered)
    }

    /// Rule 1 on samples 2-5, against the frozen baseline of `frozenFrom`
    /// (the same samples by default).
    static func verdict(_ samples: [ObservationSample], frozenFrom: [ObservationSample]? = nil,
                        references: [String] = references, visible: [OracleTemplate]? = nil) -> BaselineVerdict {
        HiddenBaseline.evaluate(kept: Array(samples.dropFirst()), frozen: frozen(frozenFrom ?? samples),
                                references: references, visible: visible ?? Self.visible)
    }

    static func isAccepted(_ verdict: BaselineVerdict) -> Bool {
        if case .accepted = verdict.outcome { return true }
        return false
    }

    static func accepted(_ strip: Strip = strip(), reads: [[AgentFrame]]? = nil) -> HiddenBaseline? {
        if case let .accepted(baseline) = verdict(samples(strip.image, reads: reads)).outcome { return baseline }
        return nil
    }
}
