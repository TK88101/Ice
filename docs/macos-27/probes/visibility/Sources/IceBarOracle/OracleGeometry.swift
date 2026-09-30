// Which pixels the oracle may read and where a placement sits (readings D5,
// D6, D10, D13 of docs/plans/2026-10-01-icebar-c-instrument.md).
import IceCore

public struct OracleGeometry: Sendable {
    public let widthPx: Int
    public let heightPx: Int
    public let scale: Double
    let notchColumns: Range<Int>?
    /// false for notch columns and agent-frame columns (D6).
    let visibleColumn: [Bool]
    /// Pixel windows around every edge (D10): both notch edges, both strip
    /// ends, both edges of every agent frame, each widened by the window.
    let edgeWindows: [(lo: Double, hi: Double)]
    let referenceOriginPt: Double?

    public init(widthPx: Int, heightPx: Int, scale: Double, context: OracleContext, parameters: OracleParameters = .preRegistered) {
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.scale = scale
        notchColumns = context.notch.flatMap { Self.notchColumns($0, scale: scale) }
        var visible = [Bool](repeating: true, count: widthPx)
        var blocked = context.agentFrames.map { Self.columns($0, scale: scale) }
        if let notchColumns { blocked.append(notchColumns) }
        for columns in blocked {
            for x in columns.clamped(to: 0..<max(0, widthPx)) { visible[x] = false }
        }
        visibleColumn = visible

        var edgesPt = [0, Double(widthPx) / scale]
        if let notch = context.notch { edgesPt += [notch.lo, notch.hi] }
        for frame in context.agentFrames { edgesPt += [frame.lo, frame.hi] }
        edgeWindows = edgesPt.map { (($0 - parameters.edgeWindowPt) * scale, ($0 + parameters.edgeWindowPt) * scale) }
        referenceOriginPt = context.leftmostReferenceOriginPt
    }

    /// IceCore's own widening (`BarGeometry.notchColumns`, internal there):
    /// round the low edge down and the high edge up.
    public static func notchColumns(_ notch: PtSpan, scale: Double) -> Range<Int> {
        let lo = Int((notch.lo * scale).rounded(.down))
        let hi = Int((notch.hi * scale).rounded(.up))
        return lo..<max(lo, hi)
    }

    /// A frame's columns, not widened (D6).
    static func columns(_ span: PtSpan, scale: Double) -> Range<Int> {
        let lo = Int((span.lo * scale).rounded(.down))
        let hi = Int((span.hi * scale).rounded(.up))
        return lo..<max(lo, hi)
    }

    func isVisible(x: Int, y: Int) -> Bool {
        x >= 0 && x < widthPx && y >= 0 && y < heightPx && visibleColumn[x]
    }

    /// The box's pixel span [x0, x0 + width) reaches into some edge window.
    func isEdgeEligible(x0: Int, width: Int) -> Bool {
        let lo = Double(x0)
        let hi = Double(x0 + width)
        return edgeWindows.contains { lo < $0.hi && hi > $0.lo }
    }

    func zone(x0: Int, width: Int) -> Zone {
        if let notchColumns, x0 < notchColumns.upperBound, x0 + width > notchColumns.lowerBound {
            return .notchEdge
        }
        if let notchColumns, x0 + width <= notchColumns.lowerBound {
            return .leftOfNotch
        }
        if let referenceOriginPt, Double(x0) / scale >= referenceOriginPt {
            return .rightOfReferences
        }
        return .region
    }

    /// How many of `template`'s on-pixels are visible with the box at (x0, y0):
    /// the count S2, S5 and S13 are generated against.
    public func visibleOnCount(_ template: OracleTemplate, x0: Int, y0: Int) -> Int {
        template.on.reduce(0) { $0 + (isVisible(x: x0 + $1.x, y: y0 + $1.y) ? 1 : 0) }
    }

    /// Top row of a `height` px box centred on the strip, rounding down (D7).
    public func centreY(height: Int) -> Int {
        Int((Double(heightPx - height) / 2).rounded(.down))
    }
}
