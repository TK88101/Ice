/// Section 4: one serial capture path, watching an owner-only roster
/// (Target and the spacer excluded by the caller before an observation ever
/// reaches here) plus Protected as a separate one-miss condition. A trip is
/// what tells the stage to rest the spacer and quit the helpers at once
/// (I3's `LatchingCapturer` acts on it); this type only decides whether one
/// has happened.
public enum LatchTrip: Equatable, Sendable {
    case ownerItemMissing(String)
    case protectedMissing
    case residualInkChanged
    case foldAppeared
    /// A capture that failed, or an AX read that came back late -- itself
    /// an immediate abort (section 4), checked ahead of everything else in
    /// the same observation.
    case captureFailed
}

public struct Latch: Sendable {
    public private(set) var isTripped = false
    public private(set) var lastTrip: LatchTrip?

    public init() {}

    /// One capture's owner-only reading. The caller has already excluded
    /// Target and the spacer from `missingOwnerItems` -- their own changes
    /// are never credible disappearances (section 4), so the latch has no
    /// way to see them at all.
    public struct Observation: Equatable, Sendable {
        public let missingOwnerItems: [String]
        public let protectedMissing: Bool
        public let residualInkChanged: Bool
        public let foldAppearedWithoutExpansion: Bool
        public let captureFailed: Bool

        public init(
            missingOwnerItems: [String] = [],
            protectedMissing: Bool = false,
            residualInkChanged: Bool = false,
            foldAppearedWithoutExpansion: Bool = false,
            captureFailed: Bool = false
        ) {
            self.missingOwnerItems = missingOwnerItems
            self.protectedMissing = protectedMissing
            self.residualInkChanged = residualInkChanged
            self.foldAppearedWithoutExpansion = foldAppearedWithoutExpansion
            self.captureFailed = captureFailed
        }
    }

    /// Feeds one capture's observation in. Returns the trip reason the
    /// first time this observation trips the latch; once tripped, later
    /// observations return `nil` until `resetAfterPassingCheck()` -- there
    /// is nothing more for the stage to act on, and section 4 already says
    /// the miss state only resets on a passing reset check.
    @discardableResult
    public mutating func observe(_ observation: Observation) -> LatchTrip? {
        guard !isTripped else { return nil }

        let trip: LatchTrip?
        if observation.captureFailed {
            trip = .captureFailed
        } else if let missing = observation.missingOwnerItems.first {
            trip = .ownerItemMissing(missing)
        } else if observation.protectedMissing {
            trip = .protectedMissing
        } else if observation.residualInkChanged {
            trip = .residualInkChanged
        } else if observation.foldAppearedWithoutExpansion {
            trip = .foldAppeared
        } else {
            trip = nil
        }

        if let trip {
            isTripped = true
            lastTrip = trip
        }
        return trip
    }

    /// Section 4: "its miss state resets only after a passing reset check."
    public mutating func resetAfterPassingCheck() {
        isTripped = false
        lastTrip = nil
    }
}
