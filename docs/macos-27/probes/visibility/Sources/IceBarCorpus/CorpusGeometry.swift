// The corpus geometry (pre-registration section 6) and the recorded K inputs.
import Foundation
import IceBarOracle
import IceCore
import VZGlyphs

public enum CorpusGeometry {
    public static let widthPt = 1728
    public static let heightPt = 32
    public static let notch = PtSpan(lo: 771.5, hi: 956.5)
    /// D2: fixed slots, left to right.
    public static let referenceSlots: [(glyph: Glyph, xPt: Double)] = [(.reference, 1317), (.alt, 1350)]
    public static let leftmostReferencePt = 1317.0
    public static let capsuleXPt = 1380.0
    public static let capsuleWidthPt = 20.0
    public static let capsuleHeightPt = 18.0
    public static let capsuleColour = RGB(130, 90, 250)
    public static let glyphSidePt = 12
    public static let insetPt = 1.5
    /// D1: the three visible helpers' glyphs; the other 16 are members.
    public static let visibleGlyphs: [Glyph] = [.reference, .alt, .target]
    public static let scales = [1, 2]

    public static func widthPx(scale: Int) -> Int { widthPt * scale }
    public static func heightPx(scale: Int) -> Int { heightPt * scale }
    public static func px(_ pt: Double, scale: Int) -> Int { Int((pt * Double(scale)).rounded(.down)) }
    public static func glyphTop(scale: Int) -> Int { (heightPx(scale: scale) - glyphSidePt * scale) / 2 }
    public static func notchColumns(scale: Int) -> Range<Int> { OracleGeometry.notchColumns(notch, scale: Double(scale)) }
    public static func capsuleFrame(xPt: Double) -> [Double] { [xPt, xPt + capsuleWidthPt] }

    /// D13, written out independently of the oracle's own zone function.
    static func zone(x0: Int, width: Int, scale: Int) -> Zone {
        let columns = notchColumns(scale: scale)
        if x0 < columns.upperBound && x0 + width > columns.lowerBound { return .notchEdge }
        if x0 + width <= columns.lowerBound { return .leftOfNotch }
        return Double(x0) / Double(scale) >= leftmostReferencePt ? .rightOfReferences : .region
    }

    static func labelX(_ x0: Int, scale: Int) -> Double { Double(x0) / Double(scale) + insetPt }
}

public struct KInput: Sendable {
    public let id: String
    public let file: String
    public let sha256: String
    public let chevron: ChevronSighting
}

/// Section 6's recorded captures (owner's account, read-only).
public enum KCaptures {
    public static let run = "20260918-204150-m-mid"
    public static let inputs = [
        KInput(id: "K1", file: "00011-probe-mid-20.png", sha256: "a3bcce60c95dc037ca2085cb6acc6f51539d749d69d2c3871d707639a36739e6", chevron: .present),
        KInput(id: "K2", file: "00015-probe-mid-648.png", sha256: "763ecc099fd04c89db630b9571abaea0e1433c0c246259749806efd8675021e2", chevron: .present),
        KInput(id: "K3", file: "00017-probe-mid-652.png", sha256: "763ecc099fd04c89db630b9571abaea0e1433c0c246259749806efd8675021e2", chevron: .present),
        KInput(id: "K4", file: "00041-probe-mid-4.png", sha256: "e720dbe781d20c9fc4bbe67d61056c6494e043de29d5eaebb7c548a7ef70279e", chevron: .absent),
    ]
    /// K3 has K2's bytes: "kept as one item".
    public static let items = inputs.filter { $0.id != "K3" }
    /// K1's chevron AX frame (labels.json "oracleValue" x=976.5 w=17.5).
    public static let chevronFramePt = PtSpan(lo: 976.5, hi: 994)
    /// The run's manifest.json notchLeft/notchRight.
    public static let notch = PtSpan(lo: 771.5, hi: 956.5)
    /// Rule 1's region for that run (instrument plan 7a, T12): notch right edge
    /// to its target helper at x 1008 (MEASURED samples.jsonl ownAX).
    public static let textureRegion = PtSpan(lo: 956.5, hi: 1008)
    /// K2's chevron AX frame (labels.json "oracleValue" x=1012.5 w=17.5).
    public static let k2ChevronFramePt = PtSpan(lo: 1012.5, hi: 1030)

    public static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["ICEBAR_K_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("IceReverse-evidence/\(run)/captures")
    }
}
