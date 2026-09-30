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

    @Test("an empty rawValues array (no stored value) is clean, with no numbers")
    func emptyRawValuesIsClean() {
        let result = PlacementValueScan.classify(.init(minX: 100, bundleID: "com.example.app", rawValues: []))
        #expect(result == .init(minX: 100, issue: nil, numericValues: []))
    }

    @Test("more matching values than the cap is tooManyKeys, even when every one is numeric")
    func overCapIsTooManyKeys() {
        let raw = (0...PlacementValueScan.maxMatchingKeys).map { "\($0)" }
        let result = PlacementValueScan.classify(.init(minX: 100, bundleID: "com.example.app", rawValues: raw))
        #expect(result == .init(minX: 100, issue: .tooManyKeys, numericValues: []))
    }

    @Test("exactly the cap of matching values is still classified")
    func atCapIsClean() {
        let raw = (1...PlacementValueScan.maxMatchingKeys).map { "\($0)" }
        let result = PlacementValueScan.classify(.init(minX: 100, bundleID: "com.example.app", rawValues: raw))
        #expect(result.issue == nil)
        #expect(result.numericValues.count == PlacementValueScan.maxMatchingKeys)
    }

    @Test("keysToRead keeps only prefixed keys, sorted, and at most one past the cap")
    func keysToReadFiltersSortsAndBounds() {
        let prefix = PreferredPositionKey.scanPrefix
        #expect(PlacementValueScan.keysToRead(["other", prefix + "b", prefix + "a", "NSStatusItem Visible x"]) == [prefix + "a", prefix + "b"])
        let many = (10..<50).map { prefix + "\($0)" }
        let read = PlacementValueScan.keysToRead(many.reversed())
        #expect(read.count == PlacementValueScan.maxMatchingKeys + 1)
        #expect(read == Array(many.prefix(PlacementValueScan.maxMatchingKeys + 1)))
    }

    @Test("keysToRead of an empty key list is empty")
    func keysToReadEmpty() {
        #expect(PlacementValueScan.keysToRead([]).isEmpty)
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
