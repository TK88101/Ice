/// Amendment v9, "Sort-key values": classifies one on-bar owner item's own
/// read of its preference domain -- the bounded, read-only scan
/// `step1bPlacementPlan` performs before any launch (never writes; the live
/// implementation is `C1StageEnvironment.ownerPreferenceScanner`,
/// `Sources/vizprobe/StageC1Live.swift`) -- into either a set of numeric
/// stored values or the one uncertain-scan reason that makes the whole plan
/// refuse (`PlacementPlan.RefusalReason.ownerScanUncertain`). The recorded
/// evidence (crosscheck-rework8.json #0/#4) shows the owner's own stored
/// "NSStatusItem Preferred Position" values do not fit a
/// right-edge-distance reading and instead follow the items' own
/// left-to-right order, so this plan must be able to read them rather than
/// guess -- and must refuse, not guess, when it cannot.
public enum PlacementValueScan {
    /// Why one on-bar owner item's own scan could not be trusted.
    public enum Issue: Equatable, Sendable {
        /// The item's own owning bundle id could not be determined -- no
        /// bundle id at all, an empty one, or a fallback identity string
        /// (`ItemNamespace.resolve`'s own `"pid:<n>"`, IceCore) that names
        /// no real preference domain.
        case attributionUnclear
        /// The bundle id's own domain could not be read at all.
        case unreadable
        /// The domain was read, and had at least one "NSStatusItem
        /// Preferred Position " key, but not every one of them could be
        /// parsed as a number.
        case nonNumeric
        /// The domain was read, but had no "NSStatusItem Preferred
        /// Position " key at all.
        case missing
    }

    /// One on-bar owner item's own raw scan, before classification.
    public struct Reading: Equatable, Sendable {
        public let minX: Double
        /// `nil` or empty (per `classify`'s own attribution rule) makes
        /// this item's scan `.attributionUnclear` regardless of
        /// `rawValues`.
        public let bundleID: String?
        /// Every matching key's own stored value, read as a string
        /// (`C1OwnerPreferenceScanning`'s own contract) -- `nil` when the
        /// domain itself could not be read at all, distinct from an empty
        /// array (the domain read fine but had no matching key).
        public let rawValues: [String]?

        public init(minX: Double, bundleID: String?, rawValues: [String]?) {
            self.minX = minX
            self.bundleID = bundleID
            self.rawValues = rawValues
        }
    }

    /// One on-bar owner item's scan, classified.
    public struct Classified: Equatable, Sendable {
        public let minX: Double
        /// `nil` when every matching key parsed as a number (`numericValues`
        /// is then non-empty); the refusal reason otherwise
        /// (`numericValues` is then always empty).
        public let issue: Issue?
        public let numericValues: [Double]

        public init(minX: Double, issue: Issue?, numericValues: [Double]) {
            self.minX = minX
            self.issue = issue
            self.numericValues = numericValues
        }
    }

    /// A bundle id counts as attributable only when it is non-empty and is
    /// not `ItemNamespace.resolve`'s own non-bundle fallback shape
    /// (IceCore's `"pid:<n>"`) -- this package restates that one string
    /// check rather than importing IceCore for it.
    public static func classify(_ reading: Reading) -> Classified {
        guard let bundleID = reading.bundleID, !bundleID.isEmpty, !bundleID.hasPrefix("pid:") else {
            return Classified(minX: reading.minX, issue: .attributionUnclear, numericValues: [])
        }
        guard let rawValues = reading.rawValues else {
            return Classified(minX: reading.minX, issue: .unreadable, numericValues: [])
        }
        guard !rawValues.isEmpty else {
            return Classified(minX: reading.minX, issue: .missing, numericValues: [])
        }
        var numbers = [Double]()
        for raw in rawValues {
            guard let value = Double(raw) else {
                return Classified(minX: reading.minX, issue: .nonNumeric, numericValues: [])
            }
            numbers.append(value)
        }
        return Classified(minX: reading.minX, issue: nil, numericValues: numbers)
    }
}
