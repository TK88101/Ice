/// Whether a PID is still the child icewatch spawned. Both paths must be the
/// kernel's canonical ones (the caller resolves `/tmp` to `/private/tmp`),
/// and an unknown start time never matches: a PID that cannot be proven to
/// be the child is never signalled.
public enum ChildIdentity {
    public static func matches(expectedPath: String?, expectedStart: UInt64?, actualPath: String?, actualStart: UInt64?) -> Bool {
        guard
            let expectedPath, let actualPath, let expectedStart, let actualStart
        else {
            return false
        }
        return expectedPath == actualPath && expectedStart == actualStart
    }
}

/// Every process of any Ice -- the release, any local build, their XPC
/// services -- recognised by the bundle identifiers of the bundles that
/// enclose its executable, not by a list of paths (seven local builds are
/// registered on this machine).
public enum IceProcesses {
    public static let bundleIDPrefix = "com.jordanbaird.Ice"

    /// The `.app` / `.xpc` / `.appex` bundles enclosing `path`, innermost
    /// first.
    public static func enclosingBundles(of path: String) -> [String] {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        var bundles: [String] = []
        for index in components.indices {
            let component = components[index]
            guard component.hasSuffix(".app") || component.hasSuffix(".xpc") || component.hasSuffix(".appex") else { continue }
            bundles.append(components[...index].joined(separator: "/"))
        }
        return bundles.reversed()
    }

    public static func isIce(_ path: String, bundleID: (String) -> String?) -> Bool {
        enclosingBundles(of: path).contains { bundleID($0)?.hasPrefix(bundleIDPrefix) == true }
    }

    /// The path of a process that must not be there while the child runs:
    /// any Ice outside the supervised bundle, or another process of the
    /// child's own executable. `nil` when there is none.
    public static func secondIce(_ running: [(pid: Int32, path: String)], childPID: Int32?, supervisedBundle: String?, childExecutable: String, bundleID: (String) -> String?) -> String? {
        for process in running {
            if process.path == childExecutable {
                if process.pid != childPID { return process.path }
                continue
            }
            if let supervisedBundle, process.path.hasPrefix(supervisedBundle + "/") {
                continue
            }
            if isIce(process.path, bundleID: bundleID) {
                return process.path
            }
        }
        return nil
    }

    /// The restore imports the export only while no Ice process at all
    /// runs: a running one would write its settings back over it.
    public static func noneRunning(_ running: [(pid: Int32, path: String)], bundleID: (String) -> String?) -> Bool {
        !running.contains { isIce($0.path, bundleID: bundleID) }
    }
}

/// `--set Key=true|false`, refused whole on any problem, before anything is
/// written.
public enum SettingsArguments {
    public struct Problem: Error, CustomStringConvertible {
        public let description: String
    }

    public static func parse(_ arguments: [String]) throws -> [(key: String, value: Bool)] {
        var seen: Set<String> = []
        return try arguments.map { argument in
            let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty else {
                throw Problem(description: "bad --set \(argument)")
            }
            guard let value = ["true": true, "false": false][parts[1]] else {
                throw Problem(description: "bad value in --set \(argument)")
            }
            guard seen.insert(parts[0]).inserted else {
                throw Problem(description: "repeated --set key \(parts[0])")
            }
            return (parts[0], value)
        }
    }
}
