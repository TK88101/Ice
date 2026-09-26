import Testing
@testable import C1Core

/// Amendment v9, "Sort-key values": `classify` is the pure decision behind
/// the pre-launch owner-domain scan's refusal reasons -- unreadable,
/// non-numeric, missing and attribution-unclear are each their own case
/// (crosscheck-rework8.json #0/#4, Codex round 9b H1).
@Suite("PlacementValueScan")
struct PlacementValueScanTests {
    @Test("a nil bundle id is attribution-unclear")
    func nilBundleIDIsUnclear() {
        let result = PlacementValueScan.classify(.init(minX: 100, bundleID: nil, rawValues: ["5703"]))
        #expect(result == .init(minX: 100, issue: .attributionUnclear, numericValues: []))
    }

    @Test("an empty bundle id is attribution-unclear")
    func emptyBundleIDIsUnclear() {
        let result = PlacementValueScan.classify(.init(minX: 100, bundleID: "", rawValues: ["5703"]))
        #expect(result.issue == .attributionUnclear)
    }

    @Test("a pid: fallback identity is attribution-unclear")
    func pidFallbackIsUnclear() {
        let result = PlacementValueScan.classify(.init(minX: 100, bundleID: "pid:501", rawValues: ["5703"]))
        #expect(result.issue == .attributionUnclear)
    }

    @Test("nil rawValues (the domain itself could not be read) is unreadable")
    func nilRawValuesIsUnreadable() {
        let result = PlacementValueScan.classify(.init(minX: 100, bundleID: "com.example.app", rawValues: nil))
        #expect(result == .init(minX: 100, issue: .unreadable, numericValues: []))
    }

    @Test("an empty rawValues array (read fine, no matching key) is missing")
    func emptyRawValuesIsMissing() {
        let result = PlacementValueScan.classify(.init(minX: 100, bundleID: "com.example.app", rawValues: []))
        #expect(result == .init(minX: 100, issue: .missing, numericValues: []))
    }

    @Test("a non-numeric matching value is nonNumeric, even with a numeric one alongside it")
    func nonNumericValueRefuses() {
        let result = PlacementValueScan.classify(.init(minX: 100, bundleID: "com.example.app", rawValues: ["215", "not-a-number"]))
        #expect(result == .init(minX: 100, issue: .nonNumeric, numericValues: []))
    }

    @Test("every matching value numeric -- classified with no issue and the parsed numbers")
    func numericValuesClassifyClean() {
        let result = PlacementValueScan.classify(.init(minX: 100, bundleID: "com.example.app", rawValues: ["215", "5703"]))
        #expect(result == .init(minX: 100, issue: nil, numericValues: [215, 5703]))
    }
}
