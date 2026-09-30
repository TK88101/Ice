// Rule 1's contrast gate (pre-registration section 3; claim plan R11-R13),
// measured on the visible helpers at the oracle's own placement.
import IceBarOracle
import IceCore

public struct ContrastMeasurement: Equatable, Sendable {
    /// The smallest distance between a core pixel and M_r.
    public let cR: Int
    /// Median colour of the visible helpers' off-pixels Q.
    public let mR: PixelColour
    /// The region's median (quiet columns).
    public let mX: PixelColour
    public let mxToMr: Int
    /// The largest distance of a region row median from M_x.
    public let maxRowMedianToMx: Int

    func passes(_ parameters: ClaimParameters) -> Bool {
        cR >= parameters.contrastMin && mxToMr <= parameters.tBg && maxRowMedianToMx <= parameters.tBg
    }
}

enum ContrastGate {
    /// Core: coverage alpha >= 0.9, i.e. >= 230 of 255.
    static let coreAlpha: UInt8 = 230

    /// nil when the gate cannot be measured: a malformed roster, an oracle
    /// error, a visible helper not identified `full`, an inconclusive capture,
    /// or no core / off-pixel to measure.
    static func measure(stored: StripImage, visible: [OracleTemplate], references: [String], region: ClaimRegion,
                        notch: PtSpan?, agentSpans: [PtSpan]) -> ContrastMeasurement? {
        let ids = visible.map(\.id)
        guard !visible.isEmpty, Set(ids).count == ids.count, Set(references).isSubset(of: ids),
              visible.allSatisfy({ $0.scale == stored.scale })
        else { return nil }
        let context = OracleContext(notch: notch, agentFrames: agentSpans, leftmostReferenceOriginPt: region.span.hi)
        guard let labels = try? Oracle.label(image: stored, helpers: visible, chevron: nil, context: context),
              !labels.isInconclusive
        else { return nil }
        let geometry = OracleGeometry(widthPx: stored.width, heightPx: stored.height, scale: stored.scale, context: context)

        var core = [PixelColour]()
        var off = [PixelColour]()
        for template in visible {
            guard case let .drawn(.full, x, _)? = labels.labels[template.id],
                  let placement = best(labels.matches[template.id] ?? [], template: template, geometry: geometry),
                  Double(placement.xPx) / stored.scale + OracleParameters.preRegistered.glyphInsetPt == x
            else { return nil }
            for ty in 0..<template.height {
                for tx in 0..<template.width {
                    let ix = placement.xPx + tx
                    let iy = placement.yPx + ty
                    guard geometry.isVisible(x: ix, y: iy) else { continue }
                    let a = template.alpha[ty * template.width + tx]
                    if a >= coreAlpha { core.append(PixelKit.colour(stored, ix, iy)) }
                    if a == 0 { off.append(PixelKit.colour(stored, ix, iy)) }
                }
            }
        }
        let quiet = (0..<stored.height).flatMap { y in region.quietColumns.map { PixelKit.colour(stored, $0, y) } }
        guard let mR = PixelKit.median(off), let mX = PixelKit.median(quiet),
              let cR = core.map({ PixelKit.distance($0, mR) }).min()
        else { return nil }
        let rowSpread = (0..<stored.height).compactMap { region.rowMedian(stored, $0) }.map { PixelKit.distance($0, mX) }.max() ?? 0
        return ContrastMeasurement(cR: cR, mR: mR, mX: mX, mxToMr: PixelKit.distance(mX, mR), maxRowMedianToMx: rowSpread)
    }

    /// D12, as `Oracle.best` (internal to part 1, which is not changed for a
    /// non-bug): highest class, higher hit fraction, lower false fraction,
    /// nearer the vertical centre, smaller x. Pinned against it by a test.
    static func best(_ found: [IceBarOracle.Placement], template: OracleTemplate, geometry: OracleGeometry) -> IceBarOracle.Placement? {
        let centre = geometry.centreY(height: template.height)
        return found.min { a, b in
            if a.matchClass != b.matchClass { return a.matchClass > b.matchClass }
            let hitsA = a.hits * b.visibleOn
            let hitsB = b.hits * a.visibleOn
            if hitsA != hitsB { return hitsA > hitsB }
            let falseA = a.falses * max(1, b.visibleOff)
            let falseB = b.falses * max(1, a.visibleOff)
            if falseA != falseB { return falseA < falseB }
            let dyA = abs(a.yPx - centre)
            let dyB = abs(b.yPx - centre)
            if dyA != dyB { return dyA < dyB }
            return a.xPx < b.xPx
        }
    }
}
