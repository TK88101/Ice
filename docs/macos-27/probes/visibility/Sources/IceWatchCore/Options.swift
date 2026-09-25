/// Strict command-line parsing: every option is known, every valued option
/// has its value, only listed options repeat, and everything after `--`
/// belongs to the child. A safety tool must not run with an option silently
/// dropped (Codex, icewatch review round 2).
public enum Options {
    public struct Problem: Error, CustomStringConvertible {
        public let description: String
    }

    public struct Parsed: Equatable {
        public var values: [String: [String]] = [:]
        public var flags: Set<String> = []
        public var child: [String] = []

        public func value(_ name: String) -> String? { values[name]?.last }
    }

    public static func parse(_ tokens: [String], valued: Set<String>, flags: Set<String>, repeatable: Set<String> = ["--set"]) throws -> Parsed {
        var parsed = Parsed()
        var index = tokens.startIndex
        while index < tokens.endIndex {
            let token = tokens[index]
            if token == "--" {
                parsed.child = Array(tokens[(index + 1)...])
                return parsed
            }
            if flags.contains(token) {
                guard parsed.flags.insert(token).inserted else {
                    throw Problem(description: "\(token) given twice")
                }
                index += 1
                continue
            }
            guard valued.contains(token) else {
                throw Problem(description: "unknown option or stray word \(token)")
            }
            let next = index + 1
            guard next < tokens.endIndex, !tokens[next].hasPrefix("--") else {
                throw Problem(description: "\(token) needs a value")
            }
            if parsed.values[token] != nil, !repeatable.contains(token) {
                throw Problem(description: "\(token) given twice")
            }
            parsed.values[token, default: []].append(tokens[next])
            index = next + 1
        }
        return parsed
    }
}
