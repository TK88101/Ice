// The oracle's vocabulary (docs/plans/2026-09-30-icebar-c-prereg.md section 5;
// readings D1-D23 in docs/plans/2026-10-01-icebar-c-instrument.md section 3).
import IceCore

/// Section 5's numbers. Fixed by the pre-registration; never tuned.
public struct OracleParameters: Equatable, Sendable {
    /// `T_o`: a pixel differs from the local backdrop when farther than this.
    public let tO: Int
    public let partialMinOnPx: Int
    public let edgeMinOnPx: Int
    public let edgeWindowPt: Double
    public let yRangePx: Int
    /// Positive-control and ambiguity distance, in points.
    public let positionTolerancePt: Double
    /// The glyph's inset inside its 12 pt image (`Glyphs.inset.dx`).
    public let glyphInsetPt: Double

    public static let preRegistered = OracleParameters(
        tO: 24, partialMinOnPx: 16, edgeMinOnPx: 4, edgeWindowPt: 1.5, yRangePx: 4,
        positionTolerancePt: 2, glyphInsetPt: 1.5
    )
}

/// A known rendering: section 5's on-set P (alpha >= 0.5) and off-set Q
/// (alpha = 0) inside a `width` x `height` box, at one scale.
public struct OracleTemplate: Equatable, Sendable {
    public let id: String
    public let width: Int
    public let height: Int
    public let scale: Double
    /// Pixel offsets inside the box.
    let on: [Point]
    let off: [Point]
    /// Per box column, how many on- and off-pixels it holds.
    let onByColumn: [Int]
    let offByColumn: [Int]

    struct Point: Equatable, Sendable {
        let x: Int
        let y: Int
    }

    /// `alpha`: 0...255 per pixel, rows from the top.
    public init(id: String, width: Int, height: Int, alpha: [UInt8], scale: Double) {
        precondition(width > 0 && height > 0 && alpha.count == width * height, "alpha must fill the box")
        self.id = id
        self.width = width
        self.height = height
        self.scale = scale
        var on = [Point]()
        var off = [Point]()
        var onByColumn = [Int](repeating: 0, count: width)
        var offByColumn = [Int](repeating: 0, count: width)
        for y in 0..<height {
            for x in 0..<width {
                let a = alpha[y * width + x]
                if a >= 128 {
                    on.append(Point(x: x, y: y))
                    onByColumn[x] += 1
                } else if a == 0 {
                    off.append(Point(x: x, y: y))
                    offByColumn[x] += 1
                }
            }
        }
        self.on = on
        self.off = off
        self.onByColumn = onByColumn
        self.offByColumn = offByColumn
    }

    public var onCount: Int { on.count }
    public var offCount: Int { off.count }
}

/// What the oracle knows about the bar beyond its pixels, all in points.
public struct OracleContext: Equatable, Sendable {
    public let notch: PtSpan?
    /// The union of the canonical agent frames and the attempt's own on-bar
    /// AX frames (section 5, edge rule). Their columns are not visible (D6).
    public let agentFrames: [PtSpan]
    /// Where the region ends (rule 1): the leftmost reference's origin.
    public let leftmostReferenceOriginPt: Double?

    public init(notch: PtSpan?, agentFrames: [PtSpan], leftmostReferenceOriginPt: Double?) {
        self.notch = notch
        self.agentFrames = agentFrames
        self.leftmostReferenceOriginPt = leftmostReferenceOriginPt
    }
}

/// Ordered: a placement meeting a higher class is labelled with it (D11).
public enum MatchClass: Int, Comparable, Sendable, Codable {
    case edge = 0
    case partial = 1
    case full = 2

    public static func < (lhs: MatchClass, rhs: MatchClass) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum Zone: String, Sendable, Codable {
    case leftOfNotch, notchEdge, region, rightOfReferences
}

public enum HelperLabel: Equatable, Sendable {
    case none
    case drawn(MatchClass, xPt: Double, zone: Zone)
}

/// One matched placement: the box origin in pixels and its counts.
public struct Placement: Equatable, Sendable {
    public let xPx: Int
    public let yPx: Int
    public let matchClass: MatchClass
    public let hits: Int
    public let visibleOn: Int
    public let falses: Int
    public let visibleOff: Int
}

public enum InconclusiveReason: Equatable, Sendable {
    /// Two helpers' glyphs matching one placement (D14).
    case sharedPlacement(String, String)
    /// One helper matching placements more than 2 pt apart (D15).
    case spreadPlacements(String)
}

public enum ChevronSighting: String, Equatable, Sendable, Codable {
    case present, absent
    /// No chevron template at this scale (section 5: none on record at 1x).
    case notEvaluable
}

/// The oracle's labels for one capture.
public struct CaptureLabels: Equatable, Sendable {
    public let labels: [String: HelperLabel]
    public let matches: [String: [Placement]]
    public let inconclusive: [InconclusiveReason]
    public let chevron: ChevronSighting

    public init(labels: [String: HelperLabel], matches: [String: [Placement]], inconclusive: [InconclusiveReason], chevron: ChevronSighting) {
        self.labels = labels
        self.matches = matches
        self.inconclusive = inconclusive
        self.chevron = chevron
    }

    public var isInconclusive: Bool { !inconclusive.isEmpty }
}

public enum OracleError: Error, Equatable {
    case scaleMismatch(id: String)
    case emptyChevronCut
}
