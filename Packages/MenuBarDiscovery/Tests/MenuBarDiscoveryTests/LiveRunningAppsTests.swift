import Darwin
import Foundation
import IceCore
import Testing
@testable import MenuBarDiscovery

/// The live process enumeration's start time (2026-09-25 responsiveness-quarantine
/// plan, E0/T5). An integration test: it reads the real kernel, but only about
/// this test process, and touches no one's menu bar. Without this wiring the
/// quarantine would silently never apply -- every record would lack an identity.
@Suite("LiveRunningApps: the kernel start time")
struct LiveRunningAppsTests {
    @Test("this process has a start time, in the past, and it does not move between two reads")
    func ownStartTimeIsStable() throws {
        let first = try #require(LiveRunningApps.kernelStartTime(of: getpid()))
        let second = try #require(LiveRunningApps.kernelStartTime(of: getpid()))

        #expect(first == second)
        #expect(first > 0)
        #expect(first <= Date().timeIntervalSince1970)
    }

    @Test("a pid that does not exist has none")
    func missingProcessHasNone() {
        #expect(LiveRunningApps.kernelStartTime(of: Int32.max) == nil)
    }

    @Test("the enumeration fills it in: at least one running application carries a start time")
    func enumerationFillsIt() {
        #expect(LiveRunningApps().processes().contains { $0.startTime != nil })
    }
}
