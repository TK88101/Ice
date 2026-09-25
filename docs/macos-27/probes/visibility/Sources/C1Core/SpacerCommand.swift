/// Section 2: the spacer role's own stdin commands. A pure parser so I2
/// (vzhelper's spacer role) and I5 (the stage that sends them) share one
/// reading of "refused" rather than checking the range twice.
public enum SpacerCommand: Equatable, Sendable {
    /// `length <pt>`, already range-checked.
    case length(Double)
    /// `rest`: `variableLength` plus the chevron image.
    case rest
}

public enum SpacerCommandParseError: Error, Equatable, Sendable {
    /// A well-formed `length <pt>` outside `SpacerCommandParser.range`.
    case outOfRange(Double)
    /// Anything else: an unknown word, a missing or non-numeric argument, or
    /// a trailing one `rest` does not take.
    case malformed(String)
}

public enum SpacerCommandParser {
    /// Section 2: "`length <pt>` (0-1000, else refused)".
    public static let range = 0.0...1000.0

    public static func parse(_ line: String) -> Result<SpacerCommand, SpacerCommandParseError> {
        let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = words.first else { return .failure(.malformed(line)) }
        switch first {
        case "rest":
            guard words.count == 1 else { return .failure(.malformed(line)) }
            return .success(.rest)
        case "length":
            guard words.count == 2, let value = Double(words[1]) else { return .failure(.malformed(line)) }
            guard range.contains(value) else { return .failure(.outOfRange(value)) }
            return .success(.length(value))
        default:
            return .failure(.malformed(line))
        }
    }
}
