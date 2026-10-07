import Foundation

/// `icewatch references`'s output (plan 2026-10-07-icebar-menu-frame-fix,
/// section 11): one JSON line, keys sorted. The run's own helpers are listed
/// by identifier; every other item is only counted.
public enum ReferencesReport {
    public struct Helper: Equatable, Sendable {
        public let id: String
        public let x: Double?
        public let side: String

        public init(id: String, x: Double?, side: String) {
            self.id = id
            self.x = x
            self.side = side
        }
    }

    /// An item that is not the run's own: what it is (the evidence directory
    /// may hold app identifiers; the repository and the Terminal may not).
    public struct Other: Equatable, Sendable {
        public let namespace: String
        public let basis: String
        public let position: String
        public let x: Double?
        public let side: String

        public init(namespace: String, basis: String, position: String, x: Double?, side: String) {
            self.namespace = namespace
            self.basis = basis
            self.position = position
            self.x = x
            self.side = side
        }
    }

    /// `hidden` left of the hidden divider, `visible` between it and Ice's
    /// icon (or right of the divider when the icon was not read), else
    /// `rightOfIce`; `unknown` without a position or a divider.
    public static func side(midX: Double?, dividerMinX: Double?, iceIconMidX: Double?) -> String {
        guard let midX, let dividerMinX else { return "unknown" }
        if midX <= dividerMinX { return "hidden" }
        if let iceIconMidX, midX >= iceIconMidX { return "rightOfIce" }
        return "visible"
    }

    public static func line(
        complete: Bool, items: Int, dividerMinX: Double?, iceIconMidX: Double?, references: Int,
        helpers: [Helper], others: [Other]
    ) -> String {
        func number(_ value: Double?) -> Any {
            guard let value, value.isFinite else { return NSNull() }
            return value
        }
        let object: [String: Any] = [
            "complete": complete,
            "items": items,
            "dividerMinX": number(dividerMinX),
            "iceIconMidX": number(iceIconMidX),
            "references": references,
            "helpers": helpers.map { ["id": $0.id, "x": number($0.x), "side": $0.side] as [String: Any] },
            "otherHidden": others.count { $0.side == "hidden" },
            "otherVisible": others.count { $0.side == "visible" },
            "others": others.map { ["namespace": $0.namespace, "basis": $0.basis, "position": $0.position, "x": number($0.x), "side": $0.side] as [String: Any] },
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
