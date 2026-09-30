// Pixel arithmetic shared by rules 1-3 (claim plan R5, R6, R9, R16): one
// distance, one column convention, one median, one clustering.
import IceCore

/// A colour as three 0...255 channels; also a per-channel median.
public struct PixelColour: Equatable, Sendable {
    public let r: Int
    public let g: Int
    public let b: Int

    public init(r: Int, g: Int, b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }
}

enum PixelKit {
    static func colour(_ image: StripImage, _ x: Int, _ y: Int) -> PixelColour {
        let i = (y * image.width + x) * 4
        return PixelColour(r: Int(image.bytes[i]), g: Int(image.bytes[i + 1]), b: Int(image.bytes[i + 2]))
    }

    /// The frozen `RGBA.distance` (internal to IceCore): the largest
    /// per-channel difference, alpha ignored.
    static func distance(_ a: PixelColour, _ b: PixelColour) -> Int {
        max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
    }

    /// The same distance between two images at one position, without
    /// building colours (rules 1 (a) and 3 visit every region pixel).
    static func distance(_ a: StripImage, _ b: StripImage, _ x: Int, _ y: Int) -> Int {
        let i = (y * a.width + x) * 4
        return max(abs(Int(a.bytes[i]) - Int(b.bytes[i])), abs(Int(a.bytes[i + 1]) - Int(b.bytes[i + 1])),
                   abs(Int(a.bytes[i + 2]) - Int(b.bytes[i + 2])))
    }

    /// `floor(lo s) ..< ceil(hi s)`, clamped to the strip: the convention of
    /// `FoldWitness.columnRange` and `OracleGeometry.columns`.
    static func columns(_ span: PtSpan, scale: Double, width: Int) -> Range<Int> {
        let lo = max(0, Int((span.lo * scale).rounded(.down)))
        let hi = min(width, Int((span.hi * scale).rounded(.up)))
        return lo < hi ? lo..<hi : 0..<0
    }

    /// Per-channel median, the lower one for an even count (D8); nil when
    /// there is nothing to take it over.
    static func median(_ colours: [PixelColour]) -> PixelColour? {
        guard !colours.isEmpty else { return nil }
        var histograms = [[Int]](repeating: [Int](repeating: 0, count: 256), count: 3)
        for c in colours {
            histograms[0][c.r] += 1
            histograms[1][c.g] += 1
            histograms[2][c.b] += 1
        }
        let target = (colours.count - 1) / 2
        let m = histograms.map { histogram -> Int in
            var seen = 0
            for value in 0..<256 {
                seen += histogram[value]
                if seen > target { return value }
            }
            return 255
        }
        return PixelColour(r: m[0], g: m[1], b: m[2])
    }

    /// Sizes of the 8-connected clusters of `true` in a `width` x `height`
    /// mask (the cluster rule of `FoldWitness.unexplainedClusters`).
    static func clusterSizes(_ mask: [Bool], width: Int, height: Int) -> [Int] {
        var visited = [Bool](repeating: false, count: mask.count)
        var sizes = [Int]()
        for start in mask.indices where mask[start] && !visited[start] {
            visited[start] = true
            var stack = [start]
            var size = 0
            while let index = stack.popLast() {
                size += 1
                let cx = index % width
                let cy = index / width
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = cx + dx
                        let ny = cy + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let next = ny * width + nx
                        guard mask[next], !visited[next] else { continue }
                        visited[next] = true
                        stack.append(next)
                    }
                }
            }
            sizes.append(size)
        }
        return sizes
    }
}
