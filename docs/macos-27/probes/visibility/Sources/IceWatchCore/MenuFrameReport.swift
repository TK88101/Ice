import Foundation

/// `icewatch menu-frame`'s output (plan 2026-10-07-icebar-menu-frame-fix, F4):
/// one JSON line, keys sorted, a missing or non-finite value as `null`. The
/// display's width and the bar's height are for the helper placement check (F3).
public enum MenuFrameReport {
    public static func line(menuMaxX: Double?, notchMinX: Double?, displayWidth: Double?, barHeight: Double?, verdict: String) -> String {
        func number(_ value: Double?) -> Any {
            guard let value, value.isFinite else { return NSNull() }
            return value
        }
        let object: [String: Any] = [
            "barHeight": number(barHeight),
            "displayWidth": number(displayWidth),
            "menuMaxX": number(menuMaxX),
            "notchMinX": number(notchMinX),
            "verdict": verdict,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Only `fits` lets the run start.
    public static func exitCode(verdict: String) -> Int32 {
        verdict == "fits" ? 0 : 1
    }
}
