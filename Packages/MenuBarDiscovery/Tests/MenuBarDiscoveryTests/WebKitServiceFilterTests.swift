import AppKit
import IceCore
import Testing
@testable import MenuBarDiscovery

/// The live enumeration leaves out WebKit's services (plan
/// 2026-11-16-webkit-services, D2): the path rule and the signature both,
/// checked once per process identity; any doubt keeps the process.
@Suite("WebKitServiceFilter")
struct WebKitServiceFilterTests {
    private static let contentID = "com.apple.WebKit.WebContent"
    private static let contentPath =
        "/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/"
        + "com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"

    private static func record(_ pid: Int32, _ bundleID: String?, startTime: Double? = 100) -> ProcessInfoRecord {
        ProcessInfoRecord(
            pid: pid, bundleID: bundleID, localizedName: nil, executableName: nil, launchTime: nil, isSelf: false,
            startTime: startTime, startUptime: startTime
        )
    }

    /// Records the signature checks it is asked for.
    private final class SignatureLog: @unchecked Sendable {
        var asked = [Int32]()
        var ids = [String]()

        func check(_ pid: Int32, _ id: String) -> Bool {
            asked.append(pid)
            ids.append(id)
            return true
        }
    }

    @Test("a service at its path, signed by Apple as itself, is left out; an ordinary app is kept")
    func leavesOutSignedService() {
        let filter = WebKitServiceFilter()
        let records = [Self.record(1, "com.example.App"), Self.record(2, Self.contentID)]

        let kept = filter.keeping(records, executablePath: { _ in Self.contentPath }, isAppleSigned: { _, _ in true })

        #expect(kept.map(\.pid) == [1])
    }

    @Test("a service whose signature check fails is kept")
    func keepsUnsigned() {
        let filter = WebKitServiceFilter()
        let kept = filter.keeping([Self.record(2, Self.contentID)], executablePath: { _ in Self.contentPath }, isAppleSigned: { _, _ in false })

        #expect(kept.map(\.pid) == [2])
    }

    @Test("a service id at another path is kept, and its signature is not asked")
    func keepsWrongPathWithoutSigning() {
        let filter = WebKitServiceFilter()
        let log = SignatureLog()
        let kept = filter.keeping([Self.record(2, Self.contentID)], executablePath: { _ in "/tmp/com.apple.WebKit.WebContent" }, isAppleSigned: log.check)

        #expect(kept.map(\.pid) == [2])
        #expect(log.asked.isEmpty)
    }

    @Test("a service whose path cannot be read is kept")
    func keepsUnreadablePath() {
        let filter = WebKitServiceFilter()
        let kept = filter.keeping([Self.record(2, Self.contentID)], executablePath: { _ in nil }, isAppleSigned: { _, _ in true })

        #expect(kept.map(\.pid) == [2])
    }

    @Test("the signature is asked once per identity, with the service's own id; a reused pid is asked again")
    func checksOncePerIdentity() {
        let filter = WebKitServiceFilter()
        let log = SignatureLog()

        _ = filter.keeping([Self.record(2, Self.contentID)], executablePath: { _ in Self.contentPath }, isAppleSigned: log.check)
        let again = filter.keeping([Self.record(2, Self.contentID)], executablePath: { _ in Self.contentPath }, isAppleSigned: log.check)
        _ = filter.keeping([Self.record(2, Self.contentID, startTime: 200)], executablePath: { _ in Self.contentPath }, isAppleSigned: log.check)

        #expect(again.isEmpty)
        #expect(log.asked == [2, 2])
        #expect(log.ids == [Self.contentID, Self.contentID])
    }

    @Test("a verdict is forgotten once its process is gone")
    func prunesGoneProcesses() {
        let filter = WebKitServiceFilter()
        let log = SignatureLog()

        _ = filter.keeping([Self.record(2, Self.contentID)], executablePath: { _ in Self.contentPath }, isAppleSigned: log.check)
        _ = filter.keeping([], executablePath: { _ in Self.contentPath }, isAppleSigned: log.check)
        _ = filter.keeping([Self.record(2, Self.contentID)], executablePath: { _ in Self.contentPath }, isAppleSigned: log.check)

        #expect(log.asked == [2, 2])
    }

    @Test("a record without a start time is judged every time, never from a cached verdict")
    func noIdentityNoCache() {
        let filter = WebKitServiceFilter()
        let log = SignatureLog()
        let record = Self.record(2, Self.contentID, startTime: nil)

        let first = filter.keeping([record], executablePath: { _ in Self.contentPath }, isAppleSigned: log.check)
        let second = filter.keeping([record], executablePath: { _ in Self.contentPath }, isAppleSigned: log.check)

        #expect(first.isEmpty && second.isEmpty)
        #expect(log.asked == [2, 2])
    }

    @Test("the live enumeration leaves no matching WebKit service in, by its kernel path")
    func liveEnumerationHasNoMatchingService() {
        let kept = LiveRunningApps().processes()
        let matching = kept.filter {
            WebKitServiceRule.matches(bundleID: $0.bundleID, executablePath: LiveRunningApps.executablePath(of: $0.pid))
        }

        #expect(matching.isEmpty)
    }

    /// Skipped on a machine where no WebKit service runs (a clean or headless host).
    @Test(
        "the real signature check accepts a running WebKit service and refuses it under another id",
        .enabled(if: !NSWorkspaceProbe.serviceProcesses().isEmpty, "no WebKit service is running on this machine")
    )
    func realSignatureCheck() throws {
        let (pid, id) = try #require(NSWorkspaceProbe.serviceProcesses().first)

        #expect(LiveRunningApps.isAppleSigned(pid: pid, identifier: id))
        #expect(!LiveRunningApps.isAppleSigned(pid: pid, identifier: "com.apple.MenuBarAgent"))
        #expect(!LiveRunningApps.isAppleSigned(pid: Int32.max, identifier: id))
    }
}

/// The WebKit services running now, by bundle id.
private enum NSWorkspaceProbe {
    static func serviceProcesses() -> [(Int32, String)] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, WebKitServiceRule.serviceIDs.contains(id) else { return nil }
            return (app.processIdentifier, id)
        }
    }
}
