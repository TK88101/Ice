/// Amendment v4 / G-b: an untemplated owner item cannot be watched by
/// pixels (there is no template to match), so it is watched through keyed
/// discovery instead -- "listed and stationary" (AX `minX` within 2 pt of
/// baseline), which is weaker evidence than the pixel criterion templated
/// items get and never claims the item was actually drawn. Used in every
/// latch read, the reset check, and teardown (section 4, section 5).
public enum UntemplatedOwnerWatch {
    public static let tolerancePt = 2.0

    public struct Reading: Equatable, Sendable {
        public let id: String
        public let minX: Double

        public init(id: String, minX: Double) {
            self.id = id
            self.minX = minX
        }
    }

    public enum Failure: Equatable, Sendable {
        case missing(String)
        case moved(String)
    }

    /// `current[id]`: the id's fresh AX reading, or `nil` when discovery's
    /// read of it was itself unusable (failed, quarantined, or otherwise
    /// unreadable) -- a lagging or ambiguous read fails exactly like a
    /// missing one. An id absent from `current` entirely is the same
    /// failure as one present with a `nil` value.
    public static func check(current: [String: Reading?], baseline: [Reading]) -> [Failure] {
        var failures = [Failure]()
        for base in baseline {
            guard let reading = current[base.id].flatMap({ $0 }) else {
                failures.append(.missing(base.id))
                continue
            }
            if abs(reading.minX - base.minX) > tolerancePt {
                failures.append(.moved(base.id))
            }
        }
        return failures
    }
}
