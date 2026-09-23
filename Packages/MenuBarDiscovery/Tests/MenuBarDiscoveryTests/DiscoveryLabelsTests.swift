import IceCore
import Testing
@testable import MenuBarDiscovery

/// `DiscoveryLabels.compare` is T6's comparator (plan section 4.2): frozen,
/// human-written labels against a fresh discovery. A label names an item by
/// `(owner, childIndex)` -- `owner` is the item's namespace, `childIndex` the
/// item's 0-based position among every item sharing that owner, assigned the
/// same way `mbdiscover`'s plain listing numbers its own lines, so a label
/// written from one printout still finds its item in another.
@Suite("DiscoveryLabels.compare")
struct DiscoveryLabelsTests {
    func buildSet(_ recordsByProcess: [(ProcessInfoRecord, [ExtrasRecord])]) -> DiscoveredItemSet {
        let reads = recordsByProcess.map { rawRead(process: $0.0, records: $0.1) }
        return ItemCatalog.build(reads: reads, agentPID: nil, bounds: testBounds, isTrusted: true, ownIdentifiers: testOwnIdentifiers, now: 0)
    }

    @Test("agreement: no mismatches when every label matches")
    func agreement() {
        let process = testProcess(pid: 200)
        let set = buildSet([(process, [extrasRecord(childIndex: 0, identifier: "vz-a", minX: 100)])])
        let namespace = set.items[0].key.namespace
        let labels = [DiscoveryLabel(owner: namespace, childIndex: 0, position: "onBar", basis: "declared", planIndex: nil)]
        #expect(DiscoveryLabels.compare(labels: labels, set: set, planVisible: nil).isEmpty)
    }

    @Test("a wrong position produces a mismatch")
    func wrongPosition() {
        let process = testProcess(pid: 200)
        let set = buildSet([(process, [extrasRecord(childIndex: 0, identifier: "vz-a", minX: 100)])])
        let namespace = set.items[0].key.namespace
        let labels = [DiscoveryLabel(owner: namespace, childIndex: 0, position: "parked", basis: "declared", planIndex: nil)]
        let mismatches = DiscoveryLabels.compare(labels: labels, set: set, planVisible: nil)
        #expect(!mismatches.isEmpty)
        #expect(mismatches.contains { $0.localizedCaseInsensitiveContains("position") })
    }

    @Test("a wrong basis produces a mismatch")
    func wrongBasis() {
        let process = testProcess(pid: 200)
        let set = buildSet([(process, [extrasRecord(childIndex: 0, identifier: "vz-a", minX: 100)])])
        let namespace = set.items[0].key.namespace
        let labels = [DiscoveryLabel(owner: namespace, childIndex: 0, position: "onBar", basis: "positional", planIndex: nil)]
        let mismatches = DiscoveryLabels.compare(labels: labels, set: set, planVisible: nil)
        #expect(!mismatches.isEmpty)
        #expect(mismatches.contains { $0.localizedCaseInsensitiveContains("basis") })
    }

    @Test("a label naming an item that was not discovered is reported missing")
    func missingItem() {
        let set = buildSet([])
        let labels = [DiscoveryLabel(owner: "com.example.ghost", childIndex: 0, position: "onBar", basis: "declared", planIndex: nil)]
        let mismatches = DiscoveryLabels.compare(labels: labels, set: set, planVisible: nil)
        #expect(mismatches.contains { $0.localizedCaseInsensitiveContains("missing") })
    }

    @Test("a plan order that disagrees with the labels' planIndex is reported")
    func wrongPlanOrder() throws {
        let a = testProcess(pid: 200, bundleID: "com.example.a")
        let b = testProcess(pid: 201, bundleID: "com.example.b")
        let set = buildSet([
            (a, [extrasRecord(childIndex: 0, identifier: "vz-a", minX: 100)]),
            (b, [extrasRecord(childIndex: 0, identifier: "vz-b", minX: 200)]),
        ])
        let itemA = try #require(set.items.first { $0.process.pid == 200 })
        let itemB = try #require(set.items.first { $0.process.pid == 201 })
        let labels = [
            DiscoveryLabel(owner: itemA.key.namespace, childIndex: 0, position: "onBar", basis: "declared", planIndex: 0),
            DiscoveryLabel(owner: itemB.key.namespace, childIndex: 0, position: "onBar", basis: "declared", planIndex: 1),
        ]
        // labels expect [a, b] in plan order; hand the comparator the
        // reverse to force a mismatch.
        let mismatches = DiscoveryLabels.compare(labels: labels, set: set, planVisible: [itemB, itemA])
        #expect(mismatches.contains { $0.localizedCaseInsensitiveContains("plan order") })
    }

    @Test("a plan order matching the labels' planIndex produces no mismatch")
    func planOrderAgrees() throws {
        let a = testProcess(pid: 200, bundleID: "com.example.a")
        let b = testProcess(pid: 201, bundleID: "com.example.b")
        let set = buildSet([
            (a, [extrasRecord(childIndex: 0, identifier: "vz-a", minX: 100)]),
            (b, [extrasRecord(childIndex: 0, identifier: "vz-b", minX: 200)]),
        ])
        let itemA = try #require(set.items.first { $0.process.pid == 200 })
        let itemB = try #require(set.items.first { $0.process.pid == 201 })
        let labels = [
            DiscoveryLabel(owner: itemA.key.namespace, childIndex: 0, position: "onBar", basis: "declared", planIndex: 0),
            DiscoveryLabel(owner: itemB.key.namespace, childIndex: 0, position: "onBar", basis: "declared", planIndex: 1),
        ]
        let mismatches = DiscoveryLabels.compare(labels: labels, set: set, planVisible: [itemA, itemB])
        #expect(mismatches.isEmpty)
    }

    @Test("a discovered item that no label names is reported as unexpected")
    func unexpectedItem() {
        let a = testProcess(pid: 200)
        let b = testProcess(pid: 201, bundleID: "com.example.other")
        let set = buildSet([
            (a, [extrasRecord(childIndex: 0, identifier: "vz-a", minX: 100)]),
            (b, [extrasRecord(childIndex: 0, identifier: "vz-b", minX: 200)]),
        ])
        let labels = [DiscoveryLabel(owner: set.items[0].key.namespace, childIndex: 0, position: "onBar", basis: "declared", planIndex: nil)]
        let mismatches = DiscoveryLabels.compare(labels: labels, set: set, planVisible: nil)
        #expect(mismatches.contains { $0.localizedCaseInsensitiveContains("unexpected") })
    }

    @Test("an incomplete pass is reported, so a labels check cannot pass on a partial read")
    func incompletePassIsReported() {
        let process = testProcess(pid: 200)
        let good = rawRead(process: process, records: [extrasRecord(childIndex: 0, identifier: "vz-a", minX: 100)])
        let failed = RawRead(process: testProcess(pid: 300, bundleID: "com.example.slow"), extrasError: "notAttempted", extrasElapsed: 0, childrenError: nil, childrenElapsed: nil, records: [])
        let set = ItemCatalog.build(reads: [good, failed], agentPID: nil, bounds: testBounds, isTrusted: true, ownIdentifiers: testOwnIdentifiers, now: 0)
        let labels = [DiscoveryLabel(owner: set.items[0].key.namespace, childIndex: 0, position: "onBar", basis: "declared", planIndex: nil)]
        let mismatches = DiscoveryLabels.compare(labels: labels, set: set, planVisible: nil)
        #expect(mismatches.contains { $0.localizedCaseInsensitiveContains("incomplete") })
    }
}
