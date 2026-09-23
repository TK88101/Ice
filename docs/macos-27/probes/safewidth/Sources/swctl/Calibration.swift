// Calibration from the B0 baseline: which user items are on the bar, what each
// looks like, which of them change by themselves, how much of the icon colour
// each one shows, and which marker colours never occur in the strip.
//
// Written once per session to <b0 run>/calibration.json and read by every later
// stage. Templates are not stored: they are re-cropped from the reference capture
// named in the file, so the JSON stays small and the pixels stay authoritative.
import Foundation
import SafeWidthCore

struct CalibratedItem: Codable {
    let id: String
    let bundle: String
    let x: Double
    let w: Double
    let kind: String            // "static" | "dynamic"
    let worstMismatchAtZero: Double
    let presenceMinimum: Int
}

struct Calibration: Codable {
    let b0RunId: String
    let referenceCapture: String
    let scale: Double
    let items: [CalibratedItem]
    /// Candidate marker colours (RRGGBB) never seen in any B0 capture.
    let unusedColours: [String]
    let negativeControlMatches: Int
    let notchLeft: Double
    let notchRight: Double
}

enum Calibrate {
    static let templateTolerance = 24
    static let staticMismatch = 0.02
    /// Ink on a light bar; `ink(_:)` picks this or its white counterpart per run.
    static let dark = ColorMatch(center: RGBA(0, 0, 0), tolerance: 100)
    static let light = ColorMatch(center: RGBA(255, 255, 255), tolerance: 70)
    static let colourTolerance = 48

    /// Saturated candidates; B0 decides which of them are usable.
    static let candidates: [RGBA] = [
        RGBA(0, 0, 255), RGBA(255, 0, 255), RGBA(0, 255, 255), RGBA(255, 0, 0),
        RGBA(0, 255, 0), RGBA(128, 0, 255), RGBA(255, 0, 128), RGBA(0, 128, 255),
        RGBA(0, 255, 128), RGBA(128, 255, 0), RGBA(255, 128, 0), RGBA(0, 0, 128),
        RGBA(128, 0, 128), RGBA(0, 128, 128), RGBA(128, 0, 0), RGBA(0, 128, 0),
    ]

    static func run(b0Directory: URL) throws -> Calibration {
        let records = try loadRecords(b0Directory.appendingPathComponent("samples.jsonl"))
        let captureNames = records.filter { $0["kind"] as? String == "b0.sample" }.compactMap { $0["capture"] as? String }
        let snapshots = records.filter { $0["kind"] as? String == "b0.ax" }.compactMap { $0["value"] }
        guard let referenceName = captureNames.first, let referenceAX = snapshots.first else {
            throw CalibrationError.empty
        }
        let captures = captureNames.compactMap { name in
            StripCapture.decode(b0Directory.appendingPathComponent("captures").appendingPathComponent(name), widthPt: 1728)
        }
        guard let reference = captures.first else {
            throw CalibrationError.undecodable(referenceName)
        }
        let axItems = try decodeItems(referenceAX)
        guard let derived = baselines(items: axItems, captures: captures) else {
            throw CalibrationError.undecodable(referenceName)
        }
        let items = derived.items
        let unused = Pixels.unusedColours(candidates, tolerance: colourTolerance, in: captures)
        let manifest = try manifestNotch(b0Directory)
        return Calibration(
            b0RunId: b0Directory.lastPathComponent,
            referenceCapture: referenceName,
            scale: reference.scale,
            items: items,
            unusedColours: unused.map(hex),
            negativeControlMatches: negativeControl(unused: unused, captures: captures),
            notchLeft: manifest.left,
            notchRight: manifest.right
        )
    }

    /// User items on the bar at the reference instant, with ids that stay stable
    /// when one app owns several items: bundle plus ordinal among that bundle's items.
    static func identify(_ items: [AXItem]) -> [(id: String, item: AXItem)] {
        var seen: [String: Int] = [:]
        return items.filter { $0.y < 40 && $0.w > 0 }.sorted { $0.x < $1.x }.map { item in
            let ordinal = seen[item.bundle, default: 0]
            seen[item.bundle] = ordinal + 1
            return (id: "\(item.bundle)#\(ordinal)", item: item)
        }
    }

    /// The colour an icon is drawn in on this bar right now. The bar is translucent
    /// over a wallpaper that changes during the day, and the icons flip between
    /// white on a dark bar and black on a light one, so this is decided per run
    /// from the bar's median brightness right of the notch.
    static func ink(_ bitmap: Bitmap) -> ColorMatch {
        var lumas: [Int] = []
        let start = Int(960 * bitmap.scale)
        for y in stride(from: 0, to: bitmap.height, by: 4) {
            for x in stride(from: start, to: bitmap.width, by: 4) {
                let p = bitmap.pixel(x: x, y: y)
                lumas.append((Int(p.r) + Int(p.g) + Int(p.b)) / 3)
            }
        }
        let median = lumas.sorted()[lumas.count / 2]
        return median < 128 ? light : dark
    }

    /// User items and their guard baselines from captures taken with nothing of
    /// ours in the bar. An item is static only if its crop from the first capture
    /// matches every later capture at offset 0.
    static func baselines(ax: AXSnapshot, captures: [Bitmap]) -> (items: [CalibratedItem], baselines: [UserItemBaseline], ink: ColorMatch)? {
        baselines(items: ax.items, captures: captures)
    }

    static func baselines(items axItems: [AXItem], captures: [Bitmap]) -> (items: [CalibratedItem], baselines: [UserItemBaseline], ink: ColorMatch)? {
        guard let reference = captures.first else {
            return nil
        }
        let ink = ink(reference)
        let entries = identify(axItems)
        let items = entries.map { classify($0, reference: reference, captures: captures, ink: ink) }
        let baselines = zip(entries, items).map { entry, item in
            UserItemBaseline(
                template: template(id: entry.id, x: entry.item.x, w: entry.item.w, from: reference),
                kind: item.kind == "static" ? .static : .dynamic,
                width: entry.item.w
            )
        }
        return (items, baselines, ink)
    }

    static func template(id: String, x: Double, w: Double, from bitmap: Bitmap) -> ItemTemplate {
        let lo = max(0, Int((x * bitmap.scale).rounded()))
        let hi = min(bitmap.width, Int(((x + w) * bitmap.scale).rounded()))
        return ItemTemplate(id: id, originX: Double(lo) / bitmap.scale, bitmap: bitmap.crop(x: lo, y: 0, width: max(0, hi - lo), height: bitmap.height))
    }

    private static func classify(_ entry: (id: String, item: AXItem), reference: Bitmap, captures: [Bitmap], ink: ColorMatch) -> CalibratedItem {
        let template = template(id: entry.id, x: entry.item.x, w: entry.item.w, from: reference)
        var worst = 0.0
        var isStatic = true
        for capture in captures {
            switch Pixels.locate(template, in: capture, searchRadius: 0, channelTolerance: templateTolerance, maxMismatch: staticMismatch) {
            case .found:
                continue
            case .notFound(let mismatch):
                worst = max(worst, mismatch)
                isStatic = false
            }
        }
        let span = Span(lo: template.originX, hi: template.originX + entry.item.w)
        let inkCounts = captures.map { Pixels.count(ink, in: $0, span: span) }
        return CalibratedItem(
            id: entry.id,
            bundle: entry.item.bundle,
            x: template.originX,
            w: entry.item.w,
            kind: isStatic ? "static" : "dynamic",
            worstMismatchAtZero: worst,
            presenceMinimum: max(1, (inkCounts.min() ?? 0) / 2)
        )
    }

    /// Every ordered pair of unused colours searched as a marker in every B0
    /// capture must find nothing: the markers cannot be confused with the bar.
    private static func negativeControl(unused: [RGBA], captures: [Bitmap]) -> Int {
        var matches = 0
        for left in unused {
            for right in unused where right != left {
                let spec = Palette.spec((left, right), narrow: true, tolerance: colourTolerance)
                for capture in captures {
                    if case .absent = Pixels.findMarker(spec, in: capture) {
                        continue
                    }
                    matches += 1
                }
            }
        }
        return matches
    }

    static func hex(_ colour: RGBA) -> String {
        String(format: "%02X%02X%02X", colour.r, colour.g, colour.b)
    }

    static func rgba(_ hex: String) -> RGBA? {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            return nil
        }
        return RGBA(UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF))
    }

    private static func loadRecords(_ url: URL) throws -> [[String: Any]] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
    }

    private static func decodeItems(_ snapshot: Any) throws -> [AXItem] {
        let data = try JSONSerialization.data(withJSONObject: snapshot)
        return try JSONDecoder().decode(AXSnapshot.self, from: data).items
    }

    private static func manifestNotch(_ directory: URL) throws -> (left: Double, right: Double) {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["notchLeft"] as? Double ?? -1, object?["notchRight"] as? Double ?? -1)
    }
}

enum CalibrationError: Error {
    case empty
    case undecodable(String)
}
