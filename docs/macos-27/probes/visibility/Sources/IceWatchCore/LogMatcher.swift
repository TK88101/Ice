import Foundation

/// One `log stream --style ndjson` line, reduced to what T-post reads.
public struct LogLine: Equatable, Sendable {
    public let subsystem: String
    public let category: String
    public let message: String
}

public enum LogMatcher {
    /// `nil` for the stream's header, a partial line or anything else that is
    /// not a JSON object.
    public static func parse(_ line: String) -> LogLine? {
        guard
            let data = line.data(using: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }
        return LogLine(
            subsystem: object["subsystem"] as? String ?? "",
            category: object["category"] as? String ?? "",
            message: object["eventMessage"] as? String ?? ""
        )
    }

    /// Ice logs this just before every synthesized event
    /// (`MenuBarItemManager.swift:2037-2050`).
    public static func isPosting(_ line: LogLine) -> Bool {
        line.subsystem == "com.jordanbaird.Ice" && line.category == "MenuBarItemManager" && line.message.hasPrefix("Posting ")
    }
}

/// Splits appended bytes into complete lines, keeping a trailing partial one
/// for the next append (the stream's file output may be block-buffered).
public struct LineBuffer {
    private var pending: [UInt8] = []

    public init() {}

    public mutating func append(_ bytes: [UInt8]) -> [String] {
        pending += bytes
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            lines.append(String(decoding: pending[..<newline], as: UTF8.self))
            pending.removeSubrange(...newline)
        }
        return lines
    }
}
