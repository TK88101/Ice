/// What one observation's matcher read of each reference, so that a refused
/// capture says which reference refused it and by how far (plan
/// 2026-10-09-lab-first-run-followup, S3 design D3). Read from what
/// `StripAssessor.observe` already hands out; nothing here decides anything.

public struct ReferenceReading: Equatable, Sendable {
    public let key: ItemKey
    /// `unique`, `ambiguous`, `absent`, or `unobserved` (no sighting at all).
    public let match: String
    public let mismatch: Double?
    /// Where a unique match lies against its template's origin, in points.
    public let offset: Double?

    public init(key: ItemKey, match: String, mismatch: Double?, offset: Double?) {
        self.key = key
        self.match = match
        self.mismatch = mismatch
        self.offset = offset
    }
}

public struct ObservationDiagnostics: Equatable, Sendable {
    public let references: [ReferenceReading]
    public let captureStable: Bool
    /// `absent`, `present` or `unreadable`.
    public let fold: String

    public init(references: [ReferenceReading], captureStable: Bool, fold: String) {
        self.references = references
        self.captureStable = captureStable
        self.fold = fold
    }

    /// `references`: each reference with its template's origin, in the order
    /// they are to be reported.
    public static func make(reading: StripReading, references: [(key: ItemKey, originX: Double?)]) -> ObservationDiagnostics {
        let matches = Dictionary(reading.sightings.map { ($0.id, $0.match) }, uniquingKeysWith: { first, _ in first })
        let readings = references.map { reference -> ReferenceReading in
            switch matches[reference.key.encoded] {
            case .unique(let x, let mismatch):
                ReferenceReading(key: reference.key, match: "unique", mismatch: mismatch, offset: reference.originX.map { x - $0 })
            case .ambiguous:
                ReferenceReading(key: reference.key, match: "ambiguous", mismatch: nil, offset: nil)
            case .absent(let bestMismatch):
                ReferenceReading(key: reference.key, match: "absent", mismatch: bestMismatch, offset: nil)
            case nil:
                ReferenceReading(key: reference.key, match: "unobserved", mismatch: nil, offset: nil)
            }
        }
        return ObservationDiagnostics(references: readings, captureStable: reading.captureStable, fold: name(of: reading.fold))
    }

    /// Whether the bar lies as one piece away from where its baseline was
    /// cut: at least two references, each found well (`unique`, within
    /// `maxMismatch`), each farther than `tolerance` from its origin, all the
    /// same distance. A system item that changes its width does that (run
    /// 20261111-233109, k8: the clock at midnight, both references 8 pt off),
    /// and a new baseline reads the bar again. Anything less is not evidence
    /// of it: references the frontmost app's menus cover are `absent`, one
    /// reference alone may have moved by itself.
    public func baselineDisplaced(tolerance: Double, maxMismatch: Double) -> Bool {
        let offsets = references.compactMap { reference -> Double? in
            guard reference.match == "unique", let mismatch = reference.mismatch, mismatch <= maxMismatch,
                  let offset = reference.offset, offset.isFinite, abs(offset) > tolerance
            else { return nil }
            return offset
        }
        guard offsets.count >= 2, offsets.count == references.count,
              let nearest = offsets.min(), let farthest = offsets.max()
        else { return false }
        return farthest - nearest <= tolerance
    }

    private static func name(of fold: Fold) -> String {
        switch fold {
        case .absent: "absent"
        case .present: "present"
        case .unreadable: "unreadable"
        }
    }
}
