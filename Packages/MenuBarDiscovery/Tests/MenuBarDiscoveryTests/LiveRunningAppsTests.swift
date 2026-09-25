import AppKit
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

    // The same start on the monotonic clock (hardening plan H5).

    @Test("this process has a start uptime, before the clock's now, and it does not move between two reads")
    func ownStartUptimeIsStable() throws {
        let first = try #require(LiveRunningApps.startUptime(of: getpid()))
        let second = try #require(LiveRunningApps.startUptime(of: getpid()))

        #expect(first == second)
        #expect(first > 0)
        #expect(first <= LiveRunningApps.uptimeNow())
    }

    @Test("a pid that does not exist has no start uptime")
    func missingProcessHasNoStartUptime() {
        #expect(LiveRunningApps.startUptime(of: Int32.max) == nil)
    }

    @Test("the enumeration fills the start uptime in for at least one running application")
    func enumerationFillsStartUptime() {
        #expect(LiveRunningApps().processes().contains { $0.startUptime != nil })
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

/// The agent is also the process Apple signed as `com.apple.MenuBarAgent`
/// (security review of H3): the path check alone accepts
/// `/System/Volumes/Data/...`, which the user can write to, so a bundle claiming
/// the agent's id there -- listed before the real agent after it relaunches --
/// would still pass it. The signature is checked by pid, only for a process that
/// already passed the id and path checks.
@Suite("LiveRunningApps: the agent must also be Apple-signed")
struct MenuBarAgentSignatureTests {
    private let agentID = LiveExtrasReader.menuBarAgentBundleID
    private let systemPath = URL(fileURLWithPath: "/System/Library/CoreServices/MenuBarAgent.app")

    @Test("g1: an impostor under /System/Volumes/Data listed first is skipped for the signed agent after it")
    func impostorFirstIsSkipped() {
        let apps: [LiveRunningApps.Candidate] = [
            .init(pid: 700, bundleID: agentID, bundleURL: URL(fileURLWithPath: "/System/Volumes/Data/Users/someone/MenuBarAgent.app")),
            .init(pid: 608, bundleID: agentID, bundleURL: systemPath),
        ]

        #expect(LiveRunningApps.agentPID(among: apps, isAppleSignedAgent: { $0 == 608 }) == 608)
    }

    @Test("g2: the right id and path are not enough without the signature")
    func unsignedIsNotTheAgent() {
        let apps: [LiveRunningApps.Candidate] = [.init(pid: 608, bundleID: agentID, bundleURL: systemPath)]

        #expect(LiveRunningApps.agentPID(among: apps, isAppleSignedAgent: { _ in false }) == nil)
    }

    @Test("g3: the signature is asked only for a process that passed the id and path checks")
    func signatureAskedOnlyForCandidates() {
        let asked = Box([Int32]())
        let apps: [LiveRunningApps.Candidate] = [
            .init(pid: 1, bundleID: "com.apple.dock", bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/Dock.app")),
            .init(pid: 2, bundleID: agentID, bundleURL: URL(fileURLWithPath: "/Applications/MenuBarAgent.app")),
            .init(pid: 608, bundleID: agentID, bundleURL: systemPath),
        ]

        _ = LiveRunningApps.agentPID(among: apps, isAppleSignedAgent: { pid in asked.mutate { $0.append(pid) }; return true })

        #expect(asked.get() == [608])
    }

    @Test("g4 (live): this test process is not the Apple-signed agent, and a pid that does not exist is not either")
    func liveSignatureRejectsOthers() {
        #expect(!LiveRunningApps.isAppleSignedAgent(pid: getpid()))
        #expect(!LiveRunningApps.isAppleSignedAgent(pid: Int32.max))
    }

    @Test("g5 (live): the running menu bar agent, if there is one, passes every check")
    func liveAgentPasses() throws {
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == agentID }
        try #require(!running.isEmpty, "no menu bar agent running on this machine")
        #expect(LiveRunningApps().agentPID() == running.first?.processIdentifier)
    }
}
