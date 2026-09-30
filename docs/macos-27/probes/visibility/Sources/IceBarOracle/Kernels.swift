// Deviation 2's decision functions (docs/plans/2026-10-01-icebar-c-deviation2.md):
// the texture bound (C2, wired into rule 1 in part 2), the overlap guard (C3)
// and the live `«` (b) control (C5), both wired into the runner in part 3.
// One copy each, here; the later parts call these symbols.
import IceCore

public enum TextureBound {
    public enum Outcome: Equatable, Sendable {
        case accepted(maxDeviation: Int)
        case refused(maxDeviation: Int)
    }

    /// Every pixel of `region`, outside notch and agent-frame columns, within
    /// `T_o` / 2 (max-channel) of the region's per-channel lower median M_x.
    public static func evaluate(_ image: StripImage, region: PtSpan, notch: PtSpan?, agentFrames: [PtSpan],
                                parameters: OracleParameters = .preRegistered) -> Outcome {
        let context = OracleContext(notch: notch, agentFrames: agentFrames, leftmostReferenceOriginPt: nil)
        let geometry = OracleGeometry(widthPx: image.width, heightPx: image.height, scale: image.scale, context: context, parameters: parameters)
        let span = OracleGeometry.columns(region, scale: image.scale).clamped(to: 0..<image.width)
        let columns = span.filter { geometry.visibleColumn[$0] }
        var histograms = [[Int]](repeating: [Int](repeating: 0, count: 256), count: 3)
        for y in 0..<image.height {
            for x in columns {
                let i = (y * image.width + x) * 4
                for c in 0..<3 { histograms[c][Int(image.bytes[i + c])] += 1 }
            }
        }
        let count = columns.count * image.height
        guard count > 0 else { return .accepted(maxDeviation: 0) }
        let m = (0..<3).map { Oracle.lowerMedian(histograms[$0], count: count) }
        var worst = 0
        for y in 0..<image.height {
            for x in columns {
                let i = (y * image.width + x) * 4
                worst = max(worst, abs(Int(image.bytes[i]) - m[0]), abs(Int(image.bytes[i + 1]) - m[1]), abs(Int(image.bytes[i + 2]) - m[2]))
            }
        }
        return worst * 2 <= parameters.tO ? .accepted(maxDeviation: worst) : .refused(maxDeviation: worst)
    }
}

/// A status-item window's bounds from the window server, in points.
public struct WindowBounds: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum OverlapOutcome: Equatable, Sendable {
    case clear
    case missing(String)
    case overlap(String, String)
}

public enum OverlapGuard {
    public static let toleratedOverlapPt = 0.5

    /// Every helper in `roster` must be listed; no two may overlap by more
    /// than 0.5 pt along both axes. The first problem in roster order wins.
    public static func evaluate(roster: [String], bounds: [String: WindowBounds]) -> OverlapOutcome {
        if let absent = roster.first(where: { bounds[$0] == nil }) { return .missing(absent) }
        for i in roster.indices {
            for j in roster.indices where j > i {
                if let a = bounds[roster[i]], let b = bounds[roster[j]], overlaps(a, b) { return .overlap(roster[i], roster[j]) }
            }
        }
        return .clear
    }

    static func overlaps(_ a: WindowBounds, _ b: WindowBounds) -> Bool {
        let dx = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
        let dy = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
        return dx > toleratedOverlapPt && dy > toleratedOverlapPt
    }
}

public struct BObservation: Equatable, Sendable {
    public let episode: Int
    /// `«` by (a): an on-bar agent frame of chevron width in the read.
    public let axChevron: Bool
    /// `«` by (b) in the capture.
    public let pixels: ChevronSighting

    public init(episode: Int, axChevron: Bool, pixels: ChevronSighting) {
        self.episode = episode
        self.axChevron = axChevron
        self.pixels = pixels
    }
}

public enum BOutcome: Equatable, Sendable {
    case valid(captures: Int, episodes: Int)
    case mismatch(index: Int)
    case insufficientCaptures(Int)
    case insufficientEpisodes(Int)
}

/// C5: live, in scope, (a) implies (b); at least 10 captures from 2 episodes.
public enum BControl {
    public static let minCaptures = 10
    public static let minEpisodes = 2

    public static func evaluate(_ observations: [BObservation]) -> BOutcome {
        let counted = observations.enumerated().filter { $0.element.axChevron }
        if let miss = counted.first(where: { $0.element.pixels != .present }) { return .mismatch(index: miss.offset) }
        let episodes = Set(counted.map(\.element.episode)).count
        if counted.count < minCaptures { return .insufficientCaptures(counted.count) }
        if episodes < minEpisodes { return .insufficientEpisodes(episodes) }
        return .valid(captures: counted.count, episodes: episodes)
    }
}
