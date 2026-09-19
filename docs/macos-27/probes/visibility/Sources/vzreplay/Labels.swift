import Foundation

/// One frozen expectation. Every field traces to a swctl-recorded fact —
/// never to IceCore's own output (the oracle-discipline rule this whole tool
/// exists to honour). `vzreplay label` writes these; `vzreplay check` only
/// reads them.
struct LabelEntry: Codable, Equatable {
    let id: String
    let run: String
    /// Which comparison `check` runs: see `Replay.swift`.
    let kind: String
    let captures: [String]
    /// The swctl field(s) this expectation was read from.
    let oracleField: String
    /// The raw value(s) read from that field.
    let oracleValue: String
    /// What IceCore is expected to say, in `Replay.swift`'s vocabulary for `kind`.
    let expected: String
    let note: String
}

struct LabelFile: Codable {
    var entries: [LabelEntry]
}

enum Labels {
    static func load(_ url: URL) throws -> LabelFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return LabelFile(entries: []) }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LabelFile.self, from: data)
    }

    /// Replaces every existing entry for `run` with `entries`, keeping every
    /// other run's entries untouched, and writes the file sorted by id so
    /// diffs stay small.
    static func merge(_ url: URL, run: String, entries: [LabelEntry]) throws {
        var file = try load(url)
        file.entries.removeAll { $0.run == run }
        file.entries.append(contentsOf: entries)
        file.entries.sort { $0.id < $1.id }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: url)
    }
}
