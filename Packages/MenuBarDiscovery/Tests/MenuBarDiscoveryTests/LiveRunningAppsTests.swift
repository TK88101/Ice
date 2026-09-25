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

/// Which running application is the menu bar agent (hardening plan H3): the
/// bundle id alone would let any process that claims `com.apple.MenuBarAgent`,
/// and comes first in the list, take over the agent's routing and its
/// quarantine exemption. The bundle must also live under `/System`, judged on
/// the standardized path's first component.
@Suite("LiveRunningApps: which process is the menu bar agent")
struct MenuBarAgentIdentityTests {
    private let agentID = LiveExtrasReader.menuBarAgentBundleID

    @Test("a1: the agent's bundle id under /System/Library is the agent")
    func systemBundleIsTheAgent() {
        #expect(LiveRunningApps.isMenuBarAgent(bundleID: agentID, bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/MenuBarAgent.app")))
    }

    @Test("a2: the same bundle id anywhere else is not", arguments: [
        "/Applications/MenuBarAgent.app", "/Users/someone/MenuBarAgent.app", "/private/tmp/System/MenuBarAgent.app",
    ])
    func sameIDElsewhereIsNot(path: String) {
        #expect(!LiveRunningApps.isMenuBarAgent(bundleID: agentID, bundleURL: URL(fileURLWithPath: path)))
    }

    @Test("a3: /SystemX is not /System")
    func prefixIsNotAComponent() {
        #expect(!LiveRunningApps.isMenuBarAgent(bundleID: agentID, bundleURL: URL(fileURLWithPath: "/SystemX/Library/CoreServices/MenuBarAgent.app")))
    }

    @Test("a4: no bundle URL is not the agent")
    func nilURLIsNot() {
        #expect(!LiveRunningApps.isMenuBarAgent(bundleID: agentID, bundleURL: nil))
    }

    @Test("a5: a path that starts under /System but resolves outside it through .. is not")
    func dotDotOutOfSystemIsNot() {
        #expect(!LiveRunningApps.isMenuBarAgent(bundleID: agentID, bundleURL: URL(fileURLWithPath: "/System/../Applications/MenuBarAgent.app")))
    }

    @Test("a6: another bundle id under /System is not the agent, and a non-file URL never is")
    func otherIDOrSchemeIsNot() {
        #expect(!LiveRunningApps.isMenuBarAgent(bundleID: "com.apple.dock", bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/Dock.app")))
        #expect(!LiveRunningApps.isMenuBarAgent(bundleID: nil, bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/MenuBarAgent.app")))
        #expect(!LiveRunningApps.isMenuBarAgent(bundleID: agentID, bundleURL: URL(string: "https://example.com/System/MenuBarAgent.app")))
    }
}
