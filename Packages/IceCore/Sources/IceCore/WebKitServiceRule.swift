/// WebKit's service processes, which discovery leaves out (plan
/// 2026-11-16-webkit-services, D1). MEASURED 2026-11-16 on macOS 27.2.1: they
/// own no status item (12 of 12 answered no extras bar), and Safari starts a
/// content process per page that stalls Accessibility for its first minute,
/// before the quarantine may take it, so every pass in that minute was
/// incomplete and the hidden items were released.
///
/// The rule is strict on purpose: only the three services measured, only at
/// the kernel paths measured. Anything else stays enumerated and the
/// quarantine handles it as before. The path proves nothing alone (the volume
/// it is on is not sealed); the caller checks the signature too (D2).
public enum WebKitServiceRule {
    public static let serviceIDs: Set<String> = [
        "com.apple.WebKit.WebContent",
        "com.apple.WebKit.GPU",
        "com.apple.WebKit.Networking",
    ]

    /// The roots `proc_pidpath` gave for every service process measured.
    private static let roots: [[String]] = [
        ["System", "Volumes", "Preboot", "Cryptexes", "OS"],
        ["System", "Volumes", "Preboot", "Cryptexes", "Incoming", "OS"],
    ]

    private static let framework = ["System", "Library", "Frameworks", "WebKit.framework"]
    private static let versionsA = ["Versions", "A"]

    /// Whether `bundleID` is one of the services and `executablePath`, the
    /// kernel's path for the process, is that service's executable inside
    /// WebKit's framework at a measured root.
    public static func matches(bundleID: String?, executablePath: String?) -> Bool {
        guard let bundleID, serviceIDs.contains(bundleID), let components = absoluteComponents(of: executablePath) else {
            return false
        }
        let service = ["XPCServices", "\(bundleID).xpc", "Contents", "MacOS", bundleID]
        return roots.contains { root in
            components == root + framework + versionsA + service || components == root + framework + service
        }
    }

    /// The components after the leading `/`; `nil` for a relative path or one
    /// with an empty, `.` or `..` component.
    private static func absoluteComponents(of path: String?) -> [String]? {
        guard let path, path.hasPrefix("/") else {
            return nil
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            return nil
        }
        return components
    }
}
