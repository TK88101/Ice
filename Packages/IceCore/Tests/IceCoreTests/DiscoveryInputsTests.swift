import Testing
@testable import IceCore

/// These types carry nothing but what an AX read produced, unmodified. The
/// only behaviour worth pinning here is the pieces that are not plain storage:
/// `BarRect`'s computed edges, and that `Equatable` sees every stored field
/// (so two reads that differ in only their pid, or only an error string, are
/// never mistaken for the same fact).
@Suite("Discovery inputs")
struct DiscoveryInputsTests {
    @Test("BarRect computes its right and mid x from minX and width")
    func barRectComputedProperties() {
        let rect = BarRect(minX: 1008, minY: 4.5, width: 14, height: 24)
        #expect(rect.maxX == 1022)
        #expect(rect.midX == 1015)
    }

    @Test("BarRect equality and hashing follow its stored fields")
    func barRectEquatableHashable() {
        let a = BarRect(minX: 0, minY: 0, width: 10, height: 10)
        let b = BarRect(minX: 0, minY: 0, width: 10, height: 10)
        let c = BarRect(minX: 1, minY: 0, width: 10, height: 10)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a != c)
    }

    @Test("BarBounds is a plain display-local rectangle of the bar")
    func barBoundsEquality() {
        let a = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)
        let b = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)
        let c = BarBounds(minX: 1728, maxX: 3456, minY: 0, barHeight: 33)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("AttributeRead carries a value and an AXError name side by side")
    func attributeReadHoldsValueAndError() {
        let present = AttributeRead(value: "vz-a", error: "success")
        let absent = AttributeRead<String>(value: nil, error: "noValue")
        #expect(present.value == "vz-a")
        #expect(present.error == "success")
        #expect(absent.value == nil)
        #expect(absent.error == "noValue")
        #expect(present != absent)
    }

    @Test("ProcessInfoRecord distinguishes processes by every field, including pid")
    func processInfoRecordEquality() {
        let a = ProcessInfoRecord(pid: 100, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 12.0, isSelf: false)
        let sameFields = ProcessInfoRecord(pid: 100, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 12.0, isSelf: false)
        let differentPID = ProcessInfoRecord(pid: 101, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 12.0, isSelf: false)
        #expect(a == sameFields)
        #expect(a.hashValue == sameFields.hashValue)
        #expect(a != differentPID)
    }

    @Test("ExtrasRecord and RawRead compare structurally, field by field")
    func rawReadAndExtrasRecordEquality() {
        let frame = AttributeRead(value: BarRect(minX: 0, minY: 0, width: 10, height: 10), error: "success")
        let ok = AttributeRead(value: "", error: "success")
        let record = ExtrasRecord(childIndex: 0, role: ok, identifier: ok, title: ok, description: ok, help: ok, frame: frame)
        let otherRecord = ExtrasRecord(childIndex: 1, role: ok, identifier: ok, title: ok, description: ok, help: ok, frame: frame)
        let process = ProcessInfoRecord(pid: 1, bundleID: nil, localizedName: nil, executableName: nil, launchTime: nil, isSelf: true)

        let a = RawRead(process: process, extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: [record])
        let b = RawRead(process: process, extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: [record])
        let differentRecords = RawRead(process: process, extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: [otherRecord])

        #expect(a == b)
        #expect(a != differentRecords)
        #expect(record != otherRecord)
    }
}
