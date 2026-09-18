// Shared value types for SafeWidthCore. Every module in this target is written
// against this file only; none may depend on another module's implementation.
//
// Units: "pt" is a screen point along the menu bar's x axis, "px" is a bitmap
// pixel. A strip captured on this machine is 1728 pt wide at scale 2, so
// px = pt * scale. Times are seconds on a monotonic clock supplied by the caller.

// MARK: - Pixels

/// One pixel, 8 bits per channel.
public struct RGBA: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

/// An RGBA8 bitmap, row-major, top row first, 4 bytes per pixel.
public struct Bitmap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Pixels per point.
    public let scale: Double
    public let bytes: [UInt8]

    public init(width: Int, height: Int, scale: Double, bytes: [UInt8]) {
        precondition(width >= 0 && height >= 0 && scale > 0)
        precondition(bytes.count == width * height * 4, "bytes must hold width * height * 4 values")
        self.width = width
        self.height = height
        self.scale = scale
        self.bytes = bytes
    }

    public func pixel(x: Int, y: Int) -> RGBA {
        precondition(x >= 0 && x < width && y >= 0 && y < height)
        let i = (y * width + x) * 4
        return RGBA(bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    /// The sub-bitmap at the given pixel rectangle, which must lie inside this one.
    public func crop(x: Int, y: Int, width w: Int, height h: Int) -> Bitmap {
        precondition(x >= 0 && y >= 0 && w >= 0 && h >= 0 && x + w <= width && y + h <= height)
        var out = [UInt8]()
        out.reserveCapacity(w * h * 4)
        for row in y..<(y + h) {
            let start = (row * width + x) * 4
            out.append(contentsOf: bytes[start..<(start + w * 4)])
        }
        return Bitmap(width: w, height: h, scale: scale, bytes: out)
    }
}

/// A closed interval of points along the menu bar's x axis.
public struct Span: Equatable, Hashable, Sendable {
    public var lo: Double
    public var hi: Double

    public init(lo: Double, hi: Double) {
        precondition(lo <= hi)
        self.lo = lo
        self.hi = hi
    }

    public var mid: Double { (lo + hi) / 2 }
    public var width: Double { hi - lo }

    public func contains(_ x: Double) -> Bool { x >= lo && x <= hi }
}

/// Matches a pixel whose r, g and b each lie within `tolerance` of `center`.
/// Alpha is ignored.
public struct ColorMatch: Equatable, Sendable {
    public var center: RGBA
    public var tolerance: Int

    public init(center: RGBA, tolerance: Int) {
        self.center = center
        self.tolerance = tolerance
    }

    public func matches(_ p: RGBA) -> Bool {
        abs(Int(p.r) - Int(center.r)) <= tolerance
            && abs(Int(p.g) - Int(center.g)) <= tolerance
            && abs(Int(p.b) - Int(center.b)) <= tolerance
    }
}

/// A two-colour marker drawn by our own helpers: on a row, a run of `left`
/// followed, after at most `maxGap` px, by a run of `right`. Both runs must be at
/// least `minRun` px long, and the pattern must recur on at least `minRows` rows
/// whose px ranges overlap.
public struct MarkerSpec: Equatable, Sendable {
    public var left: ColorMatch
    public var right: ColorMatch
    public var minRun: Int
    public var maxGap: Int
    public var minRows: Int

    public init(left: ColorMatch, right: ColorMatch, minRun: Int, maxGap: Int, minRows: Int) {
        self.left = left
        self.right = right
        self.minRun = minRun
        self.maxGap = maxGap
        self.minRows = minRows
    }
}

/// The one place that fixes how big a marker is drawn and how much of it the
/// search must see. The helpers draw it and the controller looks for it from
/// different targets, so the numbers live here rather than in either of them.
public enum MarkerGeometry {
    /// Side of a helper's square marker, points.
    public static let helperSidePt = 8.0
    /// Width and height of the spacer's edge markers, points.
    public static let spacerWidthPt = 4.0
    public static let spacerHeightPt = 8.0
    /// Shortest run of one colour the search accepts, pixels.
    public static func minRun(narrow: Bool, scale: Double) -> Int {
        let halfPt = (narrow ? spacerWidthPt : helperSidePt) / 2
        return max(2, Int((halfPt * scale * 0.75).rounded(.down)))
    }
    public static func minRows(scale: Double) -> Int {
        max(4, Int((helperSidePt * scale * 0.5).rounded(.down)))
    }
}

public enum MarkerResult: Equatable, Sendable {
    case absent
    case unique(Span)
    /// More than one match, sorted by `lo`.
    case ambiguous([Span])
}

// MARK: - User items

/// A user item as it looked at the session baseline.
public struct ItemTemplate: Equatable, Sendable {
    public let id: String
    /// Left edge at baseline, pt.
    public let originX: Double
    /// Crop of the full strip height at the item's baseline rect.
    public let bitmap: Bitmap

    public init(id: String, originX: Double, bitmap: Bitmap) {
        self.id = id
        self.originX = originX
        self.bitmap = bitmap
    }
}

public enum TemplateResult: Equatable, Sendable {
    /// Best match, pt relative to `originX`. 0 means unchanged.
    case found(offset: Double)
    /// No offset within the search radius matched. `bestMismatch` is the
    /// smallest fraction of differing pixels seen, for the evidence log.
    case notFound(bestMismatch: Double)
}

public enum ItemKind: Equatable, Sendable {
    /// Looks the same from capture to capture; checked by its template.
    case `static`
    /// Changes by itself (clock, battery, the microphone pill, animated icons);
    /// checked by presence and by its static anchors.
    case dynamic
}

public struct UserItemBaseline: Equatable, Sendable {
    public let template: ItemTemplate
    public var kind: ItemKind
    /// Width at baseline, pt.
    public let width: Double

    public init(template: ItemTemplate, kind: ItemKind, width: Double) {
        self.template = template
        self.kind = kind
        self.width = width
    }

    public var id: String { template.id }
    public var span: Span { Span(lo: template.originX, hi: template.originX + width) }
}

// MARK: - Guard input and output

/// What one capture showed for one user item.
public struct ItemReading: Equatable, Sendable {
    public let id: String
    public let template: TemplateResult

    public init(id: String, template: TemplateResult) {
        self.id = id
        self.template = template
    }
}

/// The microphone pill as seen by AX and by pixels in one capture.
public struct PillReading: Equatable, Sendable {
    public let axPresent: Bool
    public let pixelPresent: Bool

    public init(axPresent: Bool, pixelPresent: Bool) {
        self.axPresent = axPresent
        self.pixelPresent = pixelPresent
    }
}

public struct CaptureReading: Equatable, Sendable {
    public let time: Double
    /// One reading per baseline user item, in baseline left-to-right order.
    public let items: [ItemReading]
    /// Our protected helper `P`.
    public let protected: MarkerResult
    /// nil when the pill was absent at baseline and in AX now.
    public let pill: PillReading?

    public init(time: Double, items: [ItemReading], protected: MarkerResult, pill: PillReading?) {
        self.time = time
        self.items = items
        self.protected = protected
        self.pill = pill
    }
}

public enum GuardFinding: Equatable, Sendable {
    /// `P`'s marker not found uniquely, or found away from where it should be.
    case protectedLost
    /// A user item is no longer visible.
    case itemLost(id: String)
    /// A dynamic item whose position cannot be confirmed by its anchors.
    case itemUnverifiable(id: String)
    /// The pill is present in AX but absent in pixels: something pushed it out.
    case pillHidden
    /// Informational. A static item whose look changed in place; it is
    /// reclassified as dynamic.
    case appearanceChanged(id: String)
    /// Informational. A visible item found away from its baseline position.
    case shifted(id: String, offset: Double)
}

public enum GuardDecision: Equatable, Sendable {
    /// Nothing wrong. `info` holds only informational findings.
    case clean(info: [GuardFinding])
    /// A harm or unverifiable finding seen once; not acted on until it persists.
    case suspect(reasons: [GuardFinding])
    /// Harm persisted: put the spacer back to rest now.
    case restore(reasons: [GuardFinding])
    /// Unverifiable persisted: put the spacer back to rest and stop the campaign.
    case stop(reasons: [GuardFinding])
}

// MARK: - Legs and verdicts

public enum TargetState: Equatable, Sendable {
    /// `T`'s marker found uniquely; x is the marker's midpoint, pt.
    case visible(x: Double)
    /// Marker absent, `«` present, and the overflow attributed to `T`.
    case overflowed
    /// Marker absent, overflow not confirmed. Never counts towards `W_hide`.
    case invisibleUnconfirmed
    case ambiguous
}

/// One settled sample of one leg.
public struct LegSample: Equatable, Sendable {
    public var length: Double
    public var target: TargetState
    /// `S`'s left edge, pt; nil when neither pixels nor AX gave it.
    public var spacerLeft: Double?
    /// true when `spacerLeft` came from AX because the marker was not visible.
    public var spacerLeftFromAX: Bool
    /// `S`'s AppKit window width, pt.
    public var spacerAppKitWidth: Double?
    /// false when neither `S` marker is drawn where it would be visible; nil when
    /// that cannot be told (both markers would fall under the notch or off-screen).
    public var spacerDrawn: Bool?
    public var harm: Bool
    public var unsettled: Bool

    public init(
        length: Double,
        target: TargetState,
        spacerLeft: Double? = nil,
        spacerLeftFromAX: Bool = false,
        spacerAppKitWidth: Double? = nil,
        spacerDrawn: Bool? = nil,
        harm: Bool = false,
        unsettled: Bool = false
    ) {
        self.length = length
        self.target = target
        self.spacerLeft = spacerLeft
        self.spacerLeftFromAX = spacerLeftFromAX
        self.spacerAppKitWidth = spacerAppKitWidth
        self.spacerDrawn = spacerDrawn
        self.harm = harm
        self.unsettled = unsettled
    }
}

/// Where a transition lies on the grid actually tested.
public enum Bracket: Equatable, Sendable {
    /// The transition lies in (lo, hi]: the old state was seen at `lo`, the new
    /// one first at `hi`. `lo` is nil when `hi` is the smallest length tested.
    case at(lo: Double?, hi: Double)
    /// Never seen on the tested grid, whose largest length was `maxTested`.
    case notObserved(maxTested: Double)
}

public enum Bound: String, CaseIterable, Sendable {
    case edge
    case sat
    case selfov
    case top
    case harm
}

public struct LegBrackets: Equatable, Sendable {
    public var hide: Bracket
    public var edge: Bracket
    public var sat: Bracket
    public var selfov: Bracket
    public var top: Bracket
    public var harm: Bracket

    public init(hide: Bracket, edge: Bracket, sat: Bracket, selfov: Bracket, top: Bracket, harm: Bracket) {
        self.hide = hide
        self.edge = edge
        self.sat = sat
        self.selfov = selfov
        self.top = top
        self.harm = harm
    }

    public func bracket(for bound: Bound) -> Bracket {
        switch bound {
        case .edge: edge
        case .sat: sat
        case .selfov: selfov
        case .top: top
        case .harm: harm
        }
    }
}

public enum Verdict: Equatable, Sendable {
    /// `W_hide < W_bound` on every repeat. `margin` is pt between the largest
    /// `W_hide` upper end and the smallest bound lower end. `gridScoped` is true
    /// when the bound was never observed, so the claim covers the tested grid only.
    case holds(margin: Double, gridScoped: Bool)
    case fails(reason: String)
    case insufficient(reason: String)
}
