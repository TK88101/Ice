// One corpus item as a recipe (pre-registration section 6): what is drawn
// where, and the label the oracle must give. Codable: `freeze.json` records
// every spec, so the frozen corpus can be regenerated and checked byte for byte.
import IceBarOracle
import IceCore
import VZGlyphs

public struct RGB: Codable, Hashable, Sendable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static func grey(_ v: UInt8) -> RGB { RGB(v, v, v) }
}

/// The ordinary variant is drawn in a solid ink (the bar's tint); the
/// coloured variant brings its own (255, 0, 0) from the renderer.
public enum InkSpec: Codable, Hashable, Sendable {
    case solid(RGB)
    case coloured
}

/// Reading D22 of the instrument plan.
public enum Backdrop: Codable, Hashable, Sendable {
    case uniform(RGB)
    /// +-6 seeded per-pixel noise on a grey.
    case noise6(RGB)
    /// A horizontal grey gradient.
    case gradientX(from: Int, to: Int)
    /// Seeded value noise on (90, 90, 90): lattice 8 pt, values in [-A, +A].
    case valueNoise(amplitude: Int)
    /// (40, 40, 40) -> (110, 110, 110) along x + y.
    case diagonal
    /// (40, 80, 200) -> (220, 120, 40) along x.
    case blueOrange
}

public enum PlacementRole: String, Codable, Sendable {
    /// The glyph the row is about.
    case test
    /// A visible helper in its fixed reference slot (D2).
    case reference
}

public struct GlyphPlacement: Codable, Equatable, Sendable {
    public let glyph: Glyph
    public let role: PlacementRole
    /// The 12 pt image box's origin, in pixels at the item's scale.
    public let xPx: Int
    public let yPx: Int
    public let ink: InkSpec
    public let alphaFactor: Double
}

public struct ChevronPlacement: Codable, Equatable, Sendable {
    public let xPx: Int
    public let yPx: Int
}

public enum ExpectedLabel: Codable, Equatable, Sendable {
    case none
    /// Deviation 2 C1: identity is `full` only; kept as a list for the
    /// freeze-1 record format.
    case drawn([MatchClass], xPt: Double, zone: Zone)

    public var isFull: Bool {
        if case let .drawn(classes, _, _) = self { return classes == [.full] }
        return false
    }
}

public enum Tri: String, Codable, Sendable {
    case yes, no, either
}

/// How an item is judged (instrument plan section 7a, T12).
public enum ExpectationMode: String, Codable, Sendable {
    /// Inside the texture bound: identity, sightings, verdict, `«` exact.
    case exact
    /// Outside it (deviation 2 C4): never clean when a member is visibly drawn.
    case failClosed
    /// K2 (C5): the texture bound refuses its region.
    case textureRefused
}

public struct Expectation: Codable, Equatable, Sendable {
    /// Identity per helper (`full` or `none`); nil where not asserted.
    public let helpers: [String: ExpectedLabel]?
    /// Per placed glyph with 4 <= n < all of P: its visible columns, where at
    /// least one unexplained sighting must overlap.
    public let requiredSightings: [String: [Int]]
    /// Deviation 3 D3.2: the same glyph identified `full` within 2 pt also
    /// meets its requirement; keyed like `requiredSightings`.
    public let cutIdentity: [String: ExpectedLabel]
    /// Visible columns of every placed glyph: in exact mode every unexplained
    /// sighting must overlap one of them.
    public let placedColumns: [[Int]]
    public let seesMember: Tri?
    public let inconclusive: Bool?
    /// Exact `«`; nil where not asserted.
    public let chevron: ChevronSighting?
    /// C4: some member is placed with >= 4 visible on-px.
    public let memberVisiblyDrawn: Bool
}

/// A visible helper in its slot, with the AX `minX` its positive control uses.
public struct VisibleControl: Codable, Equatable, Sendable {
    public let id: String
    public let axMinX: Double

    public init(id: String, axMinX: Double) {
        self.id = id
        self.axMinX = axMinX
    }
}

/// S13's five cuts.
public enum S13Cut: String, CaseIterable, Codable, Sendable {
    case notchEdge, capsuleEdge, capsuleShifted, stripStart, stripEnd
}

public struct ItemSpec: Codable, Equatable, Sendable {
    public let id: String
    public let row: String
    public let scale: Int
    public let backdrop: Backdrop
    public let glyphs: [GlyphPlacement]
    public let chevrons: [ChevronPlacement]
    /// Where the capsule is drawn (its canonical x, or S13's shifted one).
    public let capsuleXPt: Double
    /// The agent frames the oracle is given: canonical, plus the attempt's own.
    public let agentFramesPt: [[Double]]
    /// A K item's file name under `KCaptures.directory`.
    public let recorded: String?
    /// Prefixed to the id to seed the item's noise (`corpus-2`, `dev`).
    public let seedSalt: String
    /// Window-server bounds of all 19 helpers (C3's guard input).
    public let windows: [String: WindowBounds]
    public let visibleControls: [VisibleControl]
    public let mode: ExpectationMode
    public let expected: Expectation

    public var context: OracleContext {
        if recorded != nil {
            return OracleContext(notch: KCaptures.notch, agentFrames: [], leftmostReferenceOriginPt: nil)
        }
        return OracleContext(
            notch: CorpusGeometry.notch,
            agentFrames: agentFramesPt.map { PtSpan(lo: $0[0], hi: $0[1]) },
            leftmostReferenceOriginPt: CorpusGeometry.leftmostReferencePt
        )
    }
}
