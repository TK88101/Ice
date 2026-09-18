// Shared fixtures for the Guard*Tests split: baseline/reading builders, the
// single-item guard factory, canned captures, and the always-true/false
// presence probes.
import Testing
@testable import SafeWidthCore

// MARK: - Fixtures

private let sampleBitmap = Bitmap(width: 1, height: 1, scale: 2, bytes: [0, 0, 0, 255])

/// A baseline user item at `originX` with the given `width`, in points.
func item(_ id: String, at originX: Double, width: Double, kind: ItemKind) -> UserItemBaseline {
    UserItemBaseline(
        template: ItemTemplate(id: id, originX: originX, bitmap: sampleBitmap),
        kind: kind,
        width: width
    )
}

func reading(_ id: String, _ result: TemplateResult) -> ItemReading {
    ItemReading(id: id, template: result)
}

/// mid = 15
let protectedExpected = Span(lo: 10, hi: 20)
/// Marker exactly where expected: offset 0.
let protectedOkAtZero = MarkerResult.unique(Span(lo: 10, hi: 20))

func singleItemGuard(kind: ItemKind = .static, persistence: Int = 2) -> SafetyGuard {
    SafetyGuard(
        baselines: [item("A", at: 0, width: 10, kind: kind)],
        protectedExpected: protectedExpected,
        protectedTolerance: 2,
        anchorTolerance: 1,
        persistence: persistence
    )
}

func harmOnlyReading(time: Double) -> CaptureReading {
    // Item A found at rest: contributes nothing. Protected absent: harm only.
    CaptureReading(time: time, items: [reading("A", .found(offset: 0))], protected: .absent, pill: nil)
}

func unknownOnlyReading(time: Double) -> CaptureReading {
    // No reading at all for A: unverifiable (unknown) only, protected ok.
    CaptureReading(time: time, items: [], protected: protectedOkAtZero, pill: nil)
}

func cleanReading(time: Double) -> CaptureReading {
    CaptureReading(time: time, items: [reading("A", .found(offset: 0))], protected: protectedOkAtZero, pill: nil)
}

let alwaysTrue: @Sendable (String, Span) -> Bool = { _, _ in true }
let alwaysFalse: @Sendable (String, Span) -> Bool = { _, _ in false }
