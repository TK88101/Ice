import Testing
@testable import IceWatchCore

/// Which processes icewatch may signal, and which count as an Ice (plan
/// 2026-09-24-ice-first-run.md, section 5; Codex's review of icewatch).
@Suite("ChildIdentity")
struct ChildIdentityTests {
    let path = "/private/tmp/claude-501/ice-main-build3/Build/Products/Debug/Ice.app/Contents/MacOS/Ice"

    @Test("matches only the same canonical path and the same known start time")
    func matches() {
        #expect(ChildIdentity.matches(expectedPath: path, expectedStart: 42, actualPath: path, actualStart: 42))
        #expect(!ChildIdentity.matches(expectedPath: path, expectedStart: 42, actualPath: path, actualStart: 43))
        #expect(!ChildIdentity.matches(expectedPath: path, expectedStart: 42, actualPath: "/Applications/Ice.app/Contents/MacOS/Ice", actualStart: 42))
        // The P2 defect: a path spelled through the /tmp symlink is not the
        // kernel's path, so callers must canonicalize before comparing.
        #expect(!ChildIdentity.matches(expectedPath: "/tmp/x/Ice", expectedStart: 42, actualPath: "/private/tmp/x/Ice", actualStart: 42))
    }

    @Test("an unknown start time never matches, on either side")
    func unknownStart() {
        #expect(!ChildIdentity.matches(expectedPath: path, expectedStart: nil, actualPath: path, actualStart: nil))
        #expect(!ChildIdentity.matches(expectedPath: path, expectedStart: 42, actualPath: path, actualStart: nil))
        #expect(!ChildIdentity.matches(expectedPath: path, expectedStart: nil, actualPath: path, actualStart: 42))
        #expect(!ChildIdentity.matches(expectedPath: nil, expectedStart: 42, actualPath: path, actualStart: 42))
    }
}

@Suite("IceProcesses")
struct IceProcessesTests {
    let ids = [
        "/Applications/Ice.app": "com.jordanbaird.Ice",
        "/Users/u/Library/Developer/Xcode/DerivedData/Ice-x/Build/Products/Debug/Ice.app": "com.jordanbaird.Ice",
        "/private/tmp/b/Ice.app": "com.jordanbaird.Ice",
        "/private/tmp/b/Ice.app/Contents/XPCServices/MenuBarItemService.xpc": "com.jordanbaird.Ice.MenuBarItemService",
        "/Applications/Other.app": "com.example.other",
    ]

    func lookup(_ bundle: String) -> String? { ids[bundle] }

    @Test("enclosing bundles, innermost first")
    func enclosing() {
        let xpc = "/private/tmp/b/Ice.app/Contents/XPCServices/MenuBarItemService.xpc/Contents/MacOS/MenuBarItemService"
        #expect(IceProcesses.enclosingBundles(of: xpc) == ["/private/tmp/b/Ice.app/Contents/XPCServices/MenuBarItemService.xpc", "/private/tmp/b/Ice.app"])
        #expect(IceProcesses.enclosingBundles(of: "/bin/zsh").isEmpty)
    }

    @Test("any process inside a bundle whose id is Ice's, or starts with it, is an Ice")
    func isIce() {
        #expect(IceProcesses.isIce("/Applications/Ice.app/Contents/MacOS/Ice", bundleID: lookup))
        #expect(IceProcesses.isIce("/Users/u/Library/Developer/Xcode/DerivedData/Ice-x/Build/Products/Debug/Ice.app/Contents/MacOS/Ice", bundleID: lookup))
        #expect(IceProcesses.isIce("/private/tmp/b/Ice.app/Contents/XPCServices/MenuBarItemService.xpc/Contents/MacOS/MenuBarItemService", bundleID: lookup))
        #expect(!IceProcesses.isIce("/Applications/Other.app/Contents/MacOS/Other", bundleID: lookup))
        #expect(!IceProcesses.isIce("/usr/bin/defaults", bundleID: lookup))
    }

    @Test("a second Ice is any Ice outside the supervised bundle, or the child's executable under another PID")
    func secondIce() {
        let running: [(pid: Int32, path: String)] = [
            (100, "/private/tmp/b/Ice.app/Contents/MacOS/Ice"),
            (101, "/private/tmp/b/Ice.app/Contents/XPCServices/MenuBarItemService.xpc/Contents/MacOS/MenuBarItemService"),
            (7, "/bin/zsh"),
        ]
        #expect(IceProcesses.secondIce(running, childPID: 100, supervisedBundle: "/private/tmp/b/Ice.app", childExecutable: "/private/tmp/b/Ice.app/Contents/MacOS/Ice", bundleID: lookup) == nil)
        let release = running + [(200, "/Applications/Ice.app/Contents/MacOS/Ice")]
        #expect(IceProcesses.secondIce(release, childPID: 100, supervisedBundle: "/private/tmp/b/Ice.app", childExecutable: "/private/tmp/b/Ice.app/Contents/MacOS/Ice", bundleID: lookup) == "/Applications/Ice.app/Contents/MacOS/Ice")
        let twin = running + [(300, "/private/tmp/b/Ice.app/Contents/MacOS/Ice")]
        #expect(IceProcesses.secondIce(twin, childPID: 100, supervisedBundle: "/private/tmp/b/Ice.app", childExecutable: "/private/tmp/b/Ice.app/Contents/MacOS/Ice", bundleID: lookup) == "/private/tmp/b/Ice.app/Contents/MacOS/Ice")
        // Before the child exists every process of the child's executable is a second one.
        #expect(IceProcesses.secondIce(running, childPID: nil, supervisedBundle: "/private/tmp/b/Ice.app", childExecutable: "/private/tmp/b/Ice.app/Contents/MacOS/Ice", bundleID: lookup) == "/private/tmp/b/Ice.app/Contents/MacOS/Ice")
    }

    @Test("the restore waits while any Ice at all runs, the supervised bundle's included")
    func restoreGate() {
        let running: [(pid: Int32, path: String)] = [(101, "/private/tmp/b/Ice.app/Contents/XPCServices/MenuBarItemService.xpc/Contents/MacOS/MenuBarItemService")]
        #expect(!IceProcesses.noneRunning(running, bundleID: lookup))
        #expect(IceProcesses.noneRunning([(7, "/bin/zsh")], bundleID: lookup))
    }
}

@Suite("SettingsArguments")
struct SettingsArgumentsTests {
    @Test("Key=true|false pairs, in order")
    func parse() throws {
        let parsed = try SettingsArguments.parse(["UseIceBar=false", "ShowOnClick=true"])
        #expect(parsed.map(\.key) == ["UseIceBar", "ShowOnClick"])
        #expect(parsed.map(\.value) == [false, true])
    }

    @Test("a repeated key, a bad value or a missing '=' is refused before anything is written")
    func refuse() {
        #expect(throws: SettingsArguments.Problem.self) { try SettingsArguments.parse(["A=false", "A=true"]) }
        #expect(throws: SettingsArguments.Problem.self) { try SettingsArguments.parse(["A=no"]) }
        #expect(throws: SettingsArguments.Problem.self) { try SettingsArguments.parse(["A"]) }
        #expect(throws: SettingsArguments.Problem.self) { try SettingsArguments.parse(["=true"]) }
    }
}
