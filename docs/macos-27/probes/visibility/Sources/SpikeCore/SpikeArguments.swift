// T0: `vizprobe spike-run`'s arguments, and the vzhelper flag and lines
// spike B relies on (one place, so vzhelper and the stage agree).
import C2Core

public enum SpikeHelperFlags {
    /// vzhelper: give the item a one-item menu and report it opening and closing.
    public static let menu = "--menu"
    /// vzhelper stdin: cancel the open menu.
    public static let closeMenu = "closemenu"
    /// vzhelper's reply kind for `{"event": "open" | "close"}`.
    public static let menuReply = "menu"
    public static let menuItemTitle = "Spike"

    public static func withMenu(_ arguments: [String]) -> [String] { arguments + [menu] }
}

public struct SpikeArguments: Equatable, Sendable {
    /// vzhelper's `--lifetime` cap is 1800 s; `Roster.maxMembers` is 16.
    public static let maxMembers = 16
    public static let allowedMenus: [C2MenuWidth] = [.short, .mid]

    public let appsPath: String
    public let evidenceRoot: String
    public let expectedUser: String
    public let ownerUser: String
    public let expectedGeometry: String
    public let members: [Int]
    public let menus: [C2MenuWidth]
    public let lengths: SpikeLengths
    public let runB: Bool

    public enum ParseError: Error, Equatable, Sendable {
        case missing(String)
        case invalid(String)
    }

    public static func parse(_ arguments: [String]) -> Result<SpikeArguments, ParseError> {
        func value(_ name: String) throws(ParseError) -> String {
            guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { throw .missing(name) }
            return arguments[i + 1]
        }
        func optional(_ name: String) -> String? {
            guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        do {
            let apps = try value("--apps")
            let root = try value("--evidence-root")
            let user = try value("--expect-user")
            let owner = try value("--owner-user")
            let geometry = try value("--expect-geometry")
            var members = SpikeAPlan.standardMembers
            if let spec = optional("--members") {
                let parsed = spec.split(separator: ",").map { Int($0) }
                guard !parsed.isEmpty, parsed.allSatisfy({ $0.map { (1...maxMembers).contains($0) } ?? false }) else { return .failure(.invalid("--members")) }
                members = parsed.compactMap { $0 }
            }
            var menus = SpikeAPlan.standardMenus
            if let spec = optional("--menus") {
                let parsed = spec.split(separator: ",").map { C2MenuWidth(rawValue: String($0)) }
                guard !parsed.isEmpty, parsed.allSatisfy({ $0.map(allowedMenus.contains) ?? false }) else { return .failure(.invalid("--menus")) }
                menus = parsed.compactMap { $0 }
            }
            var lengths = SpikeLengths.standard
            if let spec = optional("--lengths") {
                guard let parsed = SpikeLengths(spec: spec) else { return .failure(.invalid("--lengths")) }
                lengths = parsed
            }
            return .success(SpikeArguments(appsPath: apps, evidenceRoot: root, expectedUser: user, ownerUser: owner, expectedGeometry: geometry,
                                           members: members, menus: menus, lengths: lengths, runB: !arguments.contains("--no-b")))
        } catch {
            return .failure(error)
        }
    }
}
