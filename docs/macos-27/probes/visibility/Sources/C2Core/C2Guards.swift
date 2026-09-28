// T4 (docs/plans/2026-09-28-c2-protocol.md section 2, "Guards"): the
// sequencer refuses to start unless every one of these holds. Pure.

public enum C2Guards {
    public static let geometryTolerancePt = 0.5

    /// The isolated account, never the owner's.
    public static func userAllowed(current: String, expected: String, owner: String) -> Bool {
        !current.isEmpty && current == expected && current != owner
    }

    /// Before any helper launches: only system (`com.apple.*`) items on the
    /// bar, and at least one (MenuBarAgent always owns the clock).
    public static func rosterAllowed(bundleIDs: [String]) -> Bool {
        !bundleIDs.isEmpty && bundleIDs.allSatisfy { $0.hasPrefix("com.apple.") }
    }

    public struct Geometry: Equatable, Sendable {
        public let widthPt: Double
        public let heightPt: Double
        public let notchLo: Double?
        public let notchHi: Double?

        public init(widthPt: Double, heightPt: Double, notchLo: Double?, notchHi: Double?) {
            self.widthPt = widthPt
            self.heightPt = heightPt
            self.notchLo = notchLo
            self.notchHi = notchHi
        }

        /// `"1728x32:771.5-956.5"`, or `"1440x24"` without a notch.
        public init?(spec: String) {
            let parts = spec.split(separator: ":", maxSplits: 1)
            let size = parts.first?.split(separator: "x") ?? []
            guard size.count == 2, let width = Double(size[0]), let height = Double(size[1]) else { return nil }
            var lo: Double?
            var hi: Double?
            if parts.count == 2 {
                let notch = parts[1].split(separator: "-")
                guard notch.count == 2, let l = Double(notch[0]), let h = Double(notch[1]), l < h else { return nil }
                lo = l
                hi = h
            }
            self.init(widthPt: width, heightPt: height, notchLo: lo, notchHi: hi)
        }

        /// The `--expect-geometry` form `init(spec:)` reads back.
        public var spec: String {
            let size = "\(Self.format(widthPt))x\(Self.format(heightPt))"
            guard let notchLo, let notchHi else { return size }
            return "\(size):\(Self.format(notchLo))-\(Self.format(notchHi))"
        }

        private static func format(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(value)
        }

        public func matches(_ other: Geometry) -> Bool {
            close(widthPt, other.widthPt) && close(heightPt, other.heightPt) && close(notchLo, other.notchLo) && close(notchHi, other.notchHi)
        }

        private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= C2Guards.geometryTolerancePt }
        private func close(_ a: Double?, _ b: Double?) -> Bool {
            switch (a, b) {
            case (nil, nil): true
            case let (x?, y?): close(x, y)
            default: false
            }
        }
    }
}
