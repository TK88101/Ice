// Rule 1's region and the columns each clause reads (claim plan R4, R5, R7).
import IceBarOracle
import IceCore

struct ClaimRegion: Equatable, Sendable {
    /// Notch right edge to the leftmost reference template's origin.
    let span: PtSpan
    /// Region columns minus notch columns: rule 1 (a) and `RegionClear`
    /// (agent frames included).
    let columns: [Int]
    /// `columns` minus the canonical agent frames' columns: rule 1 (b), the
    /// texture bound's pixel set, the contrast gate's medians.
    let quietColumns: [Int]

    /// nil when the region is empty or no pixel is left once notch and agent
    /// columns are removed (every median would be taken over nothing).
    init?(geometry: BarGeometry, widthPx: Int, rightEdgePt: Double, agentSpans: [PtSpan]) {
        let lo = geometry.notch?.hi ?? 0
        guard rightEdgePt > lo else { return nil }
        let span = PtSpan(lo: lo, hi: rightEdgePt)
        let notchColumns = geometry.notch.map { OracleGeometry.notchColumns($0, scale: geometry.scale) } ?? 0..<0
        let columns = PixelKit.columns(span, scale: geometry.scale, width: widthPx).filter { !notchColumns.contains($0) }
        let agentColumns = agentSpans.map { PixelKit.columns($0, scale: geometry.scale, width: widthPx) }
        let quiet = columns.filter { x in !agentColumns.contains { $0.contains(x) } }
        guard !quiet.isEmpty else { return nil }
        self.span = span
        self.columns = columns
        self.quietColumns = quiet
    }

    /// The per-channel median of one row over the quiet columns.
    func rowMedian(_ image: StripImage, _ y: Int) -> PixelColour? {
        PixelKit.median(quietColumns.map { PixelKit.colour(image, $0, y) })
    }
}
