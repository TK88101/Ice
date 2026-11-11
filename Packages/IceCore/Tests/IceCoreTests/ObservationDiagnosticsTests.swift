import Testing
@testable import IceCore

/// What one observation's matcher read of each reference (plan
/// 2026-10-09-lab-first-run-followup, S3 design D3): enough to say which
/// reference a refused capture was refused for, and by how far.
@Suite("ObservationDiagnostics")
struct ObservationDiagnosticsTests {
    let first = ItemKey(namespace: "com.icespike4.protected", identifier: "ref1", pid: 11, childIndex: nil)
    let second = ItemKey(namespace: "com.icespike4.protected", identifier: "ref2", pid: 12, childIndex: nil)

    func sighting(_ key: ItemKey, _ match: Match) -> ItemSighting {
        ItemSighting(id: key.encoded, appearance: .asBaselined, match: match, placement: .unavailable)
    }

    func reading(_ sightings: [ItemSighting], stable: Bool = false, fold: Fold = .absent) -> StripReading {
        StripReading(sightings: sightings, fold: fold, foldAtBaseline: .absent, captureStable: stable)
    }

    @Test("a reference found away from its template's origin says how far")
    func movedReference() {
        let diagnostics = ObservationDiagnostics.make(
            reading: reading([sighting(first, .unique(x: 1184, mismatch: 0.01))]),
            references: [(first, 1232)]
        )
        #expect(diagnostics.references == [ReferenceReading(key: first, match: "unique", mismatch: 0.01, offset: -48)])
        #expect(!diagnostics.captureStable)
        #expect(diagnostics.fold == "absent")
    }

    @Test("ambiguous, absent and unobserved references are named, in the order given")
    func otherMatches() {
        let third = ItemKey(namespace: "n", identifier: "ref3", pid: 13, childIndex: nil)
        let diagnostics = ObservationDiagnostics.make(
            reading: reading([sighting(second, .absent(bestMismatch: 0.4)), sighting(first, .ambiguous(count: 2))], stable: true, fold: .unreadable),
            references: [(first, 1232), (second, 1204), (third, nil)]
        )
        #expect(diagnostics.references == [
            ReferenceReading(key: first, match: "ambiguous", mismatch: nil, offset: nil),
            ReferenceReading(key: second, match: "absent", mismatch: 0.4, offset: nil),
            ReferenceReading(key: third, match: "unobserved", mismatch: nil, offset: nil),
        ])
        #expect(diagnostics.captureStable)
        #expect(diagnostics.fold == "unreadable")
    }

    // MARK: - A bar displaced as one piece under its baseline

    func diagnostics(_ readings: [(match: String, mismatch: Double?, offset: Double?)]) -> ObservationDiagnostics {
        let keys = [first, second, ItemKey(namespace: "n", identifier: "ref3", pid: 13, childIndex: nil)]
        return ObservationDiagnostics(
            references: zip(keys, readings).map { ReferenceReading(key: $0, match: $1.match, mismatch: $1.mismatch, offset: $1.offset) },
            captureStable: false,
            fold: "unreadable"
        )
    }

    func displaced(_ readings: [(match: String, mismatch: Double?, offset: Double?)]) -> Bool {
        diagnostics(readings).baselineDisplaced(tolerance: 1, maxMismatch: 0.05)
    }

    @Test("two references found well, the same distance from their origins: the bar moved as one piece (run 20261111-233109, k8)")
    func rigidShift() {
        #expect(displaced([("unique", 0, 8), ("unique", 0, 8)]))
        #expect(displaced([("unique", 0.05, -8), ("unique", 0.01, -8.5)]))
    }

    @Test("references the frontmost app's menus cover are not a displaced bar (run 20261111-233109, front-long)")
    func coveredReferences() {
        #expect(!displaced([("absent", 0.12, nil), ("absent", 0.12, nil)]))
    }

    @Test("anything short of two good references the same distance away is not a displaced bar", arguments: [
        [],
        [("unique", 0.0, 8.0)],
        [("unique", 0.0, 8.0), ("absent", 0.4, nil)],
        [("unique", 0.0, 8.0), ("ambiguous", nil, nil)],
        [("unique", 0.0, 8.0), ("unobserved", nil, nil)],
        [("unique", 0.0, 8.0), ("unique", 0.0, nil)],
        [("unique", 0.0, 8.0), ("unique", 0.06, 8.0)],
        [("unique", 0.0, 8.0), ("unique", nil, 8.0)],
        [("unique", 0.0, 8.0), ("unique", 0.0, 6.0)],
        [("unique", 0.0, 8.0), ("unique", 0.0, -8.0)],
        [("unique", 0.0, 1.0), ("unique", 0.0, 1.0)],
        [("unique", 0.0, 0.0), ("unique", 0.0, 0.0)],
        [("unique", 0.0, 8.0), ("unique", 0.0, 8.0), ("unique", 0.0, 0.0)],
    ] as [[(String, Double?, Double?)]])
    func notDisplaced(readings: [(String, Double?, Double?)]) {
        #expect(!displaced(readings.map { (match: $0.0, mismatch: $0.1, offset: $0.2) }))
    }

    @Test("a unique match without a template origin has no distance")
    func noOrigin() {
        let diagnostics = ObservationDiagnostics.make(
            reading: reading([sighting(first, .unique(x: 10, mismatch: 0))], fold: .present),
            references: [(first, nil)]
        )
        #expect(diagnostics.references == [ReferenceReading(key: first, match: "unique", mismatch: 0, offset: nil)])
        #expect(diagnostics.fold == "present")
    }
}
