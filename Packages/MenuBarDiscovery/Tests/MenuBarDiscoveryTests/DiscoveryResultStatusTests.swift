import Foundation
import IceCore
import Testing
@testable import MenuBarDiscovery

/// What one pass says about one pid (hardening plan H6), derived in one place
/// instead of twice (vizprobe's `readConclusively`, `mbdiscover --watch-pid`).
/// A struct, not an enum: a process entering the quarantine is failed *and*
/// quarantined in the same pass.
@Suite("DiscoveryResult: one pid's status in a pass")
struct DiscoveryResultStatusTests {
    @Test("s1: a process entering the quarantine is both failed and quarantined")
    func failedAndQuarantined() {
        let result = pass(enumerated: [7, 8], completeness: .incomplete(failedPIDs: [7]), quarantined: [7])

        #expect(result.status(of: 7) == DiscoveryResult.PIDStatus(enumerated: true, listed: false, failed: true, quarantined: true, permissionDenied: false))
    }

    @Test("s2: read clean with no item is enumerated and nothing else")
    func readCleanNoItem() {
        let result = pass(enumerated: [7], completeness: .complete)

        #expect(result.status(of: 7) == DiscoveryResult.PIDStatus(enumerated: true, listed: false, failed: false, quarantined: false, permissionDenied: false))
    }

    @Test("s3: a process owning an item is listed")
    func listed() {
        let result = pass(enumerated: [7], items: [ownedItem(testProcess(pid: 7))], completeness: .complete)

        #expect(result.status(of: 7).listed)
        #expect(!result.status(of: 8).listed)
    }

    @Test("s4: a pass without Accessibility trust says so for every pid")
    func permissionDenied() {
        let result = pass(enumerated: [7], completeness: .permissionDenied)

        #expect(result.status(of: 7) == DiscoveryResult.PIDStatus(enumerated: true, listed: false, failed: false, quarantined: false, permissionDenied: true))
        #expect(result.status(of: 9).permissionDenied)
    }

    @Test("s5: a pid the pass never enumerated is not enumerated, and nothing else about it is claimed")
    func notEnumerated() {
        let result = pass(enumerated: [7], completeness: .complete)

        #expect(result.status(of: 9) == DiscoveryResult.PIDStatus(enumerated: false, listed: false, failed: false, quarantined: false, permissionDenied: false))
    }

    @Test("s6: skipped under the quarantine -- quarantined, not failed")
    func quarantinedOnly() {
        let result = pass(enumerated: [7], completeness: .complete, quarantined: [7])

        #expect(result.status(of: 7) == DiscoveryResult.PIDStatus(enumerated: true, listed: false, failed: false, quarantined: true, permissionDenied: false))
    }

    @Test("s7: a failed owner whose item is carried -- listed and failed, not quarantined")
    func failedAndCarried() {
        let result = pass(enumerated: [7], items: [ownedItem(testProcess(pid: 7))], completeness: .incomplete(failedPIDs: [7]))

        #expect(result.status(of: 7) == DiscoveryResult.PIDStatus(enumerated: true, listed: true, failed: true, quarantined: false, permissionDenied: false))
    }

    @Test("s8: a real pass fills enumeratedPIDs with every process it enumerated, read or not")
    func discovererFillsEnumeratedPIDs() async throws {
        let processes = [testProcess(pid: 100), testProcess(pid: 200)]
        let discoverer = MenuBarDiscoverer(
            apps: FakeRunningApps(allProcesses: processes, agent: nil),
            reader: FakeExtrasReader { process, _ in rawRead(process: process) },
            display: FakeDisplay(result: (testBounds, DiscoveryOrigin(x: 0, y: 0))),
            isTrusted: { true }, ownIdentifiers: testOwnIdentifiers, now: { 0 }
        )

        let result = try #require(await discoverer.discover(previous: nil))

        #expect(result.enumeratedPIDs == [100, 200])
        #expect(result.status(of: 100).enumerated)
        #expect(!result.status(of: 999).enumerated)
    }

    // MARK: - fixtures

    private func pass(enumerated: [Int32], items: [DiscoveredItem] = [], completeness: Completeness, quarantined: [Int32] = []) -> DiscoveryResult {
        let set = DiscoveredItemSet(items: items, visibleControlItem: nil, hiddenDivider: nil, alwaysHiddenDivider: nil, ownRead: .ok, systemElements: [], dropped: [], completeness: completeness)
        return DiscoveryResult(
            set: set, duration: 0, origin: DiscoveryOrigin(x: 0, y: 0), bounds: testBounds, nextCursor: 0,
            quarantined: quarantined.map { testProcess(pid: $0) }, enumeratedPIDs: Set(enumerated)
        )
    }
}
