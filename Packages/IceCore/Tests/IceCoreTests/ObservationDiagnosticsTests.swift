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
