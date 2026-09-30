import Testing
@testable import C1Core

/// Amendment v4 / G-b: untemplated owner items are watched through keyed
/// discovery, not residual ink -- "listed and stationary" (AX `minX`
/// within 2 pt of baseline), never "drawn". A lagging or ambiguous read
/// fails closed exactly like a missing one.
@Suite("UntemplatedOwnerWatch")
struct UntemplatedOwnerWatchTests {
    func reading(_ id: String, _ x: Double) -> UntemplatedOwnerWatch.Reading {
        .init(id: id, minX: x)
    }

    @Test("every baseline id present, within 2 pt -> no failures")
    func allPresent() {
        let baseline = [reading("owner-1", 500), reading("owner-2", 600)]
        let current: [String: UntemplatedOwnerWatch.Reading?] = ["owner-1": reading("owner-1", 501), "owner-2": reading("owner-2", 600)]
        #expect(UntemplatedOwnerWatch.check(current: current, baseline: baseline) == [])
    }

    @Test("exactly at the 2 pt tolerance boundary still passes")
    func atToleranceBoundary() {
        let baseline = [reading("owner-1", 500)]
        let current: [String: UntemplatedOwnerWatch.Reading?] = ["owner-1": reading("owner-1", 502)]
        #expect(UntemplatedOwnerWatch.check(current: current, baseline: baseline) == [])
    }

    @Test("just past the 2 pt tolerance -> moved")
    func pastTolerance() {
        let baseline = [reading("owner-1", 500)]
        let current: [String: UntemplatedOwnerWatch.Reading?] = ["owner-1": reading("owner-1", 502.1)]
        #expect(UntemplatedOwnerWatch.check(current: current, baseline: baseline) == [.moved("owner-1")])
    }

    @Test("an id absent from the current dictionary entirely -> missing")
    func absentEntirely() {
        let baseline = [reading("owner-1", 500)]
        let current: [String: UntemplatedOwnerWatch.Reading?] = [:]
        #expect(UntemplatedOwnerWatch.check(current: current, baseline: baseline) == [.missing("owner-1")])
    }

    @Test("an id present but nil (a lagging or ambiguous read) -> missing, fails closed")
    func presentButNilFailsClosed() {
        let baseline = [reading("owner-1", 500)]
        let current: [String: UntemplatedOwnerWatch.Reading?] = ["owner-1": nil]
        #expect(UntemplatedOwnerWatch.check(current: current, baseline: baseline) == [.missing("owner-1")])
    }

    @Test("multiple failures are all reported, in baseline order")
    func multipleFailures() {
        let baseline = [reading("owner-1", 500), reading("owner-2", 600), reading("owner-3", 700)]
        let current: [String: UntemplatedOwnerWatch.Reading?] = ["owner-1": nil, "owner-2": reading("owner-2", 650), "owner-3": reading("owner-3", 700)]
        #expect(UntemplatedOwnerWatch.check(current: current, baseline: baseline) == [.missing("owner-1"), .moved("owner-2")])
    }

    @Test("no baseline items -> nothing to check, no failures")
    func noBaseline() {
        #expect(UntemplatedOwnerWatch.check(current: [:], baseline: []) == [])
    }
}
