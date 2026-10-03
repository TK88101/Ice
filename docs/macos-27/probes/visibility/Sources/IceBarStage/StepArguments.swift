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

    /// S0 is five to fifteen cycles; every other step is sized to finish well inside the helpers' lifetime.
    public var watchdogMinutes: Double { kind == .s0 ? 20 : 28 }

    public func plan(glyphOrder: [String]) -> StepPlan {
        StepPlan(kind: kind, members: members, menu: menu, glyphOrder: glyphOrder, helperLifetimeSeconds: Self.helperLifetimeSeconds)
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
        Result { try parsed(arguments) }.mapError { $0 as? ParseError ?? .invalid("\($0)") }
    }

    private static func parsed(_ arguments: [String]) throws(ParseError) -> StepArguments {
        func value(_ name: String) throws(ParseError) -> String {
            guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { throw .missing(name) }
            return arguments[i + 1]
        }
        func variant() throws(ParseError) -> SAdvVariant {
            let name = try value("--variant")
            guard let variant = SAdvVariant.all.first(where: { $0.name == name }) else { throw .invalid("--variant") }
            return variant
        }
        let kind: StepKind
        switch try value("--kind") {
        case "s0": kind = .s0
        case "sadv-sweep": kind = .sAdvSweep(try variant())
        case "sadv-chevron": kind = .sAdvChevron(try variant())
        case "s1-bracket":
            let lengths = try value("--lengths").split(separator: ",").map { Double($0) }
            guard !lengths.isEmpty, lengths.allSatisfy({ $0 != nil }) else { throw .invalid("--lengths") }
            kind = .s1Bracket(lengths.compactMap { $0 })
        case "s1-confirm":
            guard let length = Double(try value("--length")) else { throw .invalid("--length") }
            kind = .s1Confirm(length)
        default: throw .invalid("--kind")
        }
        guard let members = Int(try value("--members")), (1...Roster.maxMembers).contains(members) else { throw .invalid("--members") }
        guard let menu = C2MenuWidth(rawValue: try value("--menu")) else { throw .invalid("--menu") }
        return StepArguments(kind: kind, members: members, menu: menu, appsPath: try value("--apps"), evidencePath: try value("--evidence"))
    }
}
