// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q20): the argument
// list of one `vizprobe icebar-step` process, built by the sitting's sequencer
// and parsed back by the step (round trip, tested), with the step's watchdog.
import C2Core
import IceBarRunCore

public struct StepArguments: Equatable {
    /// vzhelper's own cap (`--lifetime` <= 1800 s); every watchdog sits inside it.
    public static let helperLifetimeSeconds = 1800

    public let kind: StepKind
    public let members: Int
    public let menu: C2MenuWidth
    public let appsPath: String
    /// The step's own evidence directory (must not exist yet).
    public let evidencePath: String

    public init(kind: StepKind, members: Int, menu: C2MenuWidth, appsPath: String, evidencePath: String) {
        self.kind = kind
        self.members = members
        self.menu = menu
        self.appsPath = appsPath
        self.evidencePath = evidencePath
    }

    public var colouredMembers: Bool {
        if case .sAdvSweep(let variant) = kind { return variant.colouredMembers }
        return false
    }

    /// S0 is five to fifteen cycles; every other step is sized to finish well inside the helpers' lifetime.
    public var watchdogMinutes: Double { kind == .s0 ? 20 : 28 }

    public func plan(glyphOrder: [String]) -> StepPlan {
        StepPlan(kind: kind, members: members, menu: menu, colouredMembers: colouredMembers, glyphOrder: glyphOrder,
                 helperLifetimeSeconds: Self.helperLifetimeSeconds)
    }

    public var arguments: [String] {
        var list = ["icebar-step", "--kind", kindName]
        switch kind {
        case .sAdvSweep(let variant), .sAdvChevron(let variant): list += ["--variant", variant.name]
        case .s1Bracket(let lengths): list += ["--lengths", lengths.map { "\($0)" }.joined(separator: ",")]
        case .s1Confirm(let length): list += ["--length", "\(length)"]
        case .s0: break
        }
        return list + ["--members", "\(members)", "--menu", menu.rawValue, "--apps", appsPath, "--evidence", evidencePath]
    }

    private var kindName: String {
        switch kind {
        case .s0: "s0"
        case .sAdvSweep: "sadv-sweep"
        case .sAdvChevron: "sadv-chevron"
        case .s1Bracket: "s1-bracket"
        case .s1Confirm: "s1-confirm"
        }
    }

    public enum ParseError: Error, Equatable {
        case missing(String)
        case invalid(String)
    }

    public static func parse(_ arguments: [String]) -> Result<StepArguments, ParseError> {
        func value(_ name: String) -> String? {
            guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        func require(_ name: String) -> Result<String, ParseError> {
            value(name).map(Result.success) ?? .failure(.missing(name))
        }
        func variant() -> Result<SAdvVariant, ParseError> {
            require("--variant").flatMap { name in SAdvVariant.all.first { $0.name == name }.map(Result.success) ?? .failure(.invalid("--variant")) }
        }
        let kind: Result<StepKind, ParseError> = require("--kind").flatMap { name in
            switch name {
            case "s0": return .success(.s0)
            case "sadv-sweep": return variant().map(StepKind.sAdvSweep)
            case "sadv-chevron": return variant().map(StepKind.sAdvChevron)
            case "s1-bracket":
                return require("--lengths").flatMap { list in
                    let lengths = list.split(separator: ",").map { Double($0) }
                    guard !lengths.isEmpty, lengths.allSatisfy({ $0 != nil }) else { return .failure(.invalid("--lengths")) }
                    return .success(.s1Bracket(lengths.compactMap { $0 }))
                }
            case "s1-confirm":
                return require("--length").flatMap { Double($0).map { .success(.s1Confirm($0)) } ?? .failure(.invalid("--length")) }
            default: return .failure(.invalid("--kind"))
            }
        }
        return kind.flatMap { kind in
            require("--members").flatMap { m in
                guard let members = Int(m), (1...Roster.maxMembers).contains(members) else { return .failure(.invalid("--members")) }
                return require("--menu").flatMap { w in
                    guard let menu = C2MenuWidth(rawValue: w) else { return .failure(.invalid("--menu")) }
                    return require("--apps").flatMap { apps in
                        require("--evidence").map { StepArguments(kind: kind, members: members, menu: menu, appsPath: apps, evidencePath: $0) }
                    }
                }
            }
        }
    }
}
