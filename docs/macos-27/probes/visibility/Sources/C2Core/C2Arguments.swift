// T4 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 5): `vizprobe c2-config`'s
// arguments, validated before anything launches.

public struct C2ConfigArguments: Equatable, Sendable {
    public let appsPath: String
    public let configuration: C2Configuration
    public let lengths: [Double]
    public let evidencePath: String

    /// `--apps <dir> --k <1-4> --menus short|mid|long --lengths a,b,...
    /// --evidence-dir <path>`; every length 0...1000, at least one.
    public static func parse(_ arguments: [String]) -> Result<C2ConfigArguments, C2ArgumentError> {
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        guard let appsPath = value("--apps") else { return .failure(.missing("--apps")) }
        guard let evidencePath = value("--evidence-dir") else { return .failure(.missing("--evidence-dir")) }
        guard let k = value("--k").flatMap(Int.init), (1...4).contains(k) else { return .failure(.invalid("--k must be 1...4")) }
        guard let width = value("--menus").flatMap(C2MenuWidth.init(rawValue:)) else { return .failure(.invalid("--menus must be short, mid or long")) }
        guard let list = value("--lengths") else { return .failure(.missing("--lengths")) }
        let lengths = list.split(separator: ",").map { Double($0) }
        guard !lengths.isEmpty, lengths.allSatisfy({ $0.map { (C2Band.minimumLengthPt...C2Band.maximumLengthPt).contains($0) } ?? false }) else {
            return .failure(.invalid("--lengths must be comma-separated numbers in 0...1000"))
        }
        return .success(C2ConfigArguments(
            appsPath: appsPath,
            configuration: C2Configuration(hiddenCount: k, width: width),
            lengths: lengths.compactMap { $0 },
            evidencePath: evidencePath
        ))
    }

    /// The same list, back as arguments (the sequencer's side).
    public var arguments: [String] {
        [
            "c2-config", "--apps", appsPath, "--k", "\(configuration.hiddenCount)", "--menus", configuration.width.rawValue,
            "--lengths", lengths.map { $0 == $0.rounded() ? String(Int($0)) : String($0) }.joined(separator: ","),
            "--evidence-dir", evidencePath,
        ]
    }

    public init(appsPath: String, configuration: C2Configuration, lengths: [Double], evidencePath: String) {
        self.appsPath = appsPath
        self.configuration = configuration
        self.lengths = lengths
        self.evidencePath = evidencePath
    }
}

public enum C2ArgumentError: Error, Equatable, Sendable {
    case missing(String)
    case invalid(String)
}
