import Testing
@testable import IceCore

/// WebKit's service processes own no status item and stall Accessibility while
/// young, so discovery leaves them out (plan 2026-11-16-webkit-services, D1):
/// only the three measured services, only at the kernel paths measured.
@Suite("WebKitServiceRule")
struct WebKitServiceRuleTests {
    private static let roots = [
        "/System/Volumes/Preboot/Cryptexes/OS",
        "/System/Volumes/Preboot/Cryptexes/Incoming/OS",
    ]

    private static func path(root: String, id: String, versioned: Bool = true, executable: String? = nil) -> String {
        let versions = versioned ? "/Versions/A" : ""
        return "\(root)/System/Library/Frameworks/WebKit.framework\(versions)/XPCServices/\(id).xpc/Contents/MacOS/\(executable ?? id)"
    }

    @Test("each service at each measured root, with or without Versions/A", arguments: WebKitServiceRule.serviceIDs.sorted())
    func acceptsMeasuredShapes(id: String) {
        for root in Self.roots {
            #expect(WebKitServiceRule.matches(bundleID: id, executablePath: Self.path(root: root, id: id)))
            #expect(WebKitServiceRule.matches(bundleID: id, executablePath: Self.path(root: root, id: id, versioned: false)))
        }
    }

    @Test("the three services are exactly WebContent, GPU and Networking")
    func serviceSet() {
        #expect(WebKitServiceRule.serviceIDs == ["com.apple.WebKit.WebContent", "com.apple.WebKit.GPU", "com.apple.WebKit.Networking"])
    }

    @Test("another bundle id at the same place is kept")
    func otherIDKept() {
        let id = "com.apple.WebKit.WebAuthn"
        #expect(!WebKitServiceRule.matches(bundleID: id, executablePath: Self.path(root: Self.roots[0], id: id)))
    }

    @Test("a service id whose executable is another service's is kept")
    func mismatchedExecutableKept() {
        let path = Self.path(root: Self.roots[0], id: "com.apple.WebKit.GPU", executable: "com.apple.WebKit.WebContent")
        #expect(!WebKitServiceRule.matches(bundleID: "com.apple.WebKit.GPU", executablePath: path))
        let other = Self.path(root: Self.roots[0], id: "com.apple.WebKit.WebContent")
        #expect(!WebKitServiceRule.matches(bundleID: "com.apple.WebKit.GPU", executablePath: other))
    }

    @Test("roots that were not measured, or that anyone can write, are kept", arguments: [
        "",
        "/System/Volumes/Data",
        "/Applications/Safari Technology Preview.app/Contents/Frameworks",
        "/System/Volumes/Preboot/Cryptexes/Other/OS",
        "/Users/someone/System/Volumes/Preboot/Cryptexes/OS",
    ])
    func otherRootsKept(root: String) {
        let id = "com.apple.WebKit.WebContent"
        #expect(!WebKitServiceRule.matches(bundleID: id, executablePath: Self.path(root: root, id: id)))
    }

    @Test("a path with . or .. components, a relative path, or nothing is kept")
    func malformedPathsKept() {
        let id = "com.apple.WebKit.WebContent"
        let good = Self.path(root: Self.roots[0], id: id)
        let dotted = good.replacingOccurrences(of: "/Frameworks/", with: "/Frameworks/./")
        let walked = good.replacingOccurrences(of: "/Frameworks/", with: "/Frameworks/x/../")
        let relative = String(good.dropFirst())
        for path in [dotted, walked, relative, "", "/"] {
            #expect(!WebKitServiceRule.matches(bundleID: id, executablePath: path))
        }
        #expect(!WebKitServiceRule.matches(bundleID: id, executablePath: nil))
        #expect(!WebKitServiceRule.matches(bundleID: nil, executablePath: good))
    }

    @Test("a longer path past the executable is kept")
    func trailingComponentsKept() {
        let id = "com.apple.WebKit.Networking"
        #expect(!WebKitServiceRule.matches(bundleID: id, executablePath: Self.path(root: Self.roots[1], id: id) + "/extra"))
    }
}
