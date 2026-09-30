// Rule 1's region and the columns each clause reads (claim plan R4, R5, R7).
import IceBarOracle
import IceCore

struct ClaimRegion: Sendable {
    /// Notch right edge to the leftmost reference template's origin.
    let span: PtSpan
    /// The oracle's own view of the strip with this notch and these agent
    /// frames: the same exclusions `TextureBound` applies (D6), so rule 1 (b),
    /// the texture bound and the contrast gate read one pixel set.
    let oracleContext: OracleContext
    let oracleGeometry: OracleGeometry
    /// Region columns minus notch columns: rule 1 (a) and `RegionClear`
    /// (agent frames included).
    let columns: [Int]
    /// `columns` minus the agent frames' columns: rule 1 (b), the texture
    /// bound's pixel set, the contrast gate's medians.
    let quietColumns: [Int]

    /// nil when the region is empty or no pixel is left once notch and agent
    /// columns are removed (every median would be taken over nothing).
    init?(geometry: BarGeometry, rightEdgePt: Double, agentSpans: [PtSpan]) {
        let lo = geometry.notch?.hi ?? 0
        guard rightEdgePt > lo else { return nil }
        let span = PtSpan(lo: lo, hi: rightEdgePt)
        let context = OracleContext(notch: geometry.notch, agentFrames: agentSpans, leftmostReferenceOriginPt: rightEdgePt)
        let oracle = OracleGeometry(widthPx: geometry.widthPx, heightPx: geometry.heightPx, scale: geometry.scale, context: context)
        let notchColumns = geometry.notch.map { OracleGeometry.notchColumns($0, scale: geometry.scale) } ?? 0..<0
        let columns = PixelKit.columns(span, scale: geometry.scale, width: geometry.widthPx).filter { !notchColumns.contains($0) }
        let quiet = columns.filter { oracle.isVisible(x: $0, y: 0) }
        guard !quiet.isEmpty else { return nil }
        self.span = span
        self.oracleContext = context
        self.oracleGeometry = oracle
        self.columns = columns
        self.quietColumns = quiet
    }

    var notch: PtSpan? { oracleContext.notch }
    var agentSpans: [PtSpan] { oracleContext.agentFrames }

    /// The per-channel median of one row over the quiet columns.
    func rowMedian(_ image: StripImage, _ y: Int) -> PixelColour? {
        PixelKit.median(quietColumns.map { PixelKit.colour(image, $0, y) })
    }
}

/// Everything else is derived from these (`OracleGeometry` is not Equatable).
extension ClaimRegion: Equatable {
    static func == (a: ClaimRegion, b: ClaimRegion) -> Bool {
        a.span == b.span && a.oracleContext == b.oracleContext && a.columns == b.columns
    }
}
