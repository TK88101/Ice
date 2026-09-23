@testable import MenuBarCapture
import IceCore

/// A minimal synthetic bar strip for `Sampler`/`VisibilityObserver` tests:
/// just enough real drawing to give IceCore's rules an actual glyph to accept
/// and match, without going through `CGImage` at all -- that conversion has
/// its own tests in `StripImageConversionTests`.
///
/// The layout (target at 60pt, reference at 150pt, frames a point narrower
/// than their own ink) mirrors the working configuration in
/// `Packages/IceCore/Tests/IceCoreTests/StripAssessorTests.swift`, read for
/// exactly this purpose.
enum TestBar {
    static let widthPt = 200
    static let heightPt = 12
    static let scale = 2
    static let backdrop = RGBA(40, 40, 40)
    static let ink = RGBA(255, 255, 255)
    static let targetPt = 60.0
    static let referencePt = 150.0

    /// Asymmetric, so it matches itself in exactly one place.
    private static let flag: [String] = [
        "##########",
        "##........",
        "##........",
        "##........",
        "##########",
        "##########",
        "........##",
        "........##",
        "........##",
        "##########",
    ]

    /// A different shape, so a whole-strip search never confuses target with
    /// reference.
    private static let box: [String] = [
        "##########",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##......##",
        "##########",
    ]

    static var geometry: BarGeometry {
        BarGeometry(widthPt: Double(widthPt), heightPt: Double(heightPt), scale: Double(scale), notch: nil)
    }

    static var targetFrame: ItemFrame {
        ItemFrame(id: "target", minX: targetPt - 1, minY: 0, width: 7, height: 12)
    }

    static var referenceFrame: ItemFrame {
        ItemFrame(id: "reference", minX: referencePt - 1, minY: 0, width: 7, height: 12)
    }

    /// One system item, well clear of both glyphs and of the chevron width.
    static var agentFrames: [AgentFrame] {
        [AgentFrame(minX: 170, minY: 0, width: 26)]
    }

    /// A strip with the target's `flag` glyph at `targetPt` (optional) and
    /// the reference's `box` glyph at `referencePt` (optional).
    static func image(target: Bool, reference: Bool = true) -> StripImage {
        let widthPx = widthPt * scale
        let heightPx = heightPt * scale
        var bytes = [UInt8](repeating: 0, count: widthPx * heightPx * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = backdrop.r
            bytes[i + 1] = backdrop.g
            bytes[i + 2] = backdrop.b
            bytes[i + 3] = 255
        }

        func draw(_ rows: [String], atPt xPt: Double) {
            let x0 = Int((xPt * Double(scale)).rounded())
            let y0 = (heightPx - rows.count) / 2
            for (dy, row) in rows.enumerated() {
                for (dx, char) in row.enumerated() where char == "#" {
                    let x = x0 + dx
                    let y = y0 + dy
                    guard x >= 0, x < widthPx, y >= 0, y < heightPx else { continue }
                    let i = (y * widthPx + x) * 4
                    bytes[i] = ink.r
                    bytes[i + 1] = ink.g
                    bytes[i + 2] = ink.b
                    bytes[i + 3] = 255
                }
            }
        }

        if target { draw(flag, atPt: targetPt) }
        if reference { draw(box, atPt: referencePt) }
        return StripImage(width: widthPx, height: heightPx, scale: Double(scale), bytes: bytes)
    }

    static func snapshot(includeTarget: Bool = true, includeReference: Bool = true) -> MenuBarAXSnapshot {
        var frames = [String: ItemFrame]()
        if includeTarget { frames["target"] = targetFrame }
        if includeReference { frames["reference"] = referenceFrame }
        return MenuBarAXSnapshot(itemFrames: frames, agentFrames: agentFrames)
    }
}
