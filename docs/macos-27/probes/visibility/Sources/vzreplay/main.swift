import Foundation

/// vzreplay — T9's offline replay harness.
///
/// `vzreplay label <run-dir>`  writes this run's expectations into labels.json,
///                              reading only swctl's own recorded fields.
/// `vzreplay check <run-dir>`  loads labels.json and replays this run's
///                              expectations through IceCore, reporting agreement.
/// `vzreplay label-all` / `check-all`  do the same over every run this tool has
///                              a case for (`Cases.knownRuns`), for convenience;
///                              the two required modes above still work alone.
///
/// labels.json lives next to Package.swift, committed, so `check` never runs
/// against an expectation that was not frozen first.
let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // vzreplay/
    .deletingLastPathComponent() // Sources/
    .deletingLastPathComponent() // package root
let labelsURL = packageRoot.appendingPathComponent("labels.json")

func runDirectory(_ argument: String) -> URL {
    if argument.hasPrefix("/") || argument.hasPrefix("~") {
        return URL(fileURLWithPath: (argument as NSString).expandingTildeInPath)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("IceReverse-evidence")
        .appendingPathComponent(argument)
}

func label(_ runDirArgument: String) throws {
    let run = try RunEvidence(directory: runDirectory(runDirArgument))
    let entries = try Cases.labels(for: run)
    try Labels.merge(labelsURL, run: run.runId, entries: entries)
    print("labelled \(entries.count) case(s) for \(run.runId) -> \(labelsURL.path)")
    for entry in entries {
        print("  \(entry.id): expected \(entry.expected) (from \(entry.oracleField) = \(entry.oracleValue))")
    }
}

func check(_ runDirArgument: String) throws -> Bool {
    let run = try RunEvidence(directory: runDirectory(runDirArgument))
    let file = try Labels.load(labelsURL)
    let entries = file.entries.filter { $0.run == run.runId }
    guard !entries.isEmpty else {
        throw ReplayError.usage("no labels for \(run.runId) in \(labelsURL.path) — run 'vzreplay label \(runDirArgument)' first")
    }
    let results = try Replay.run(run, entries: entries)
    Report.print(results)
    return results.allSatisfy(\.agree)
}

let arguments = CommandLine.arguments.dropFirst()
do {
    guard let mode = arguments.first else {
        throw ReplayError.usage("usage: vzreplay <label|check|label-all|check-all> [run-dir]")
    }
    switch mode {
    case "label":
        guard let runDir = arguments.dropFirst().first else { throw ReplayError.usage("usage: vzreplay label <run-dir>") }
        try label(runDir)
    case "check":
        guard let runDir = arguments.dropFirst().first else { throw ReplayError.usage("usage: vzreplay check <run-dir>") }
        let ok = try check(runDir)
        exit(ok ? 0 : 1)
    case "label-all":
        for run in Cases.knownRuns { try label(run) }
    case "check-all":
        var allOK = true
        for run in Cases.knownRuns {
            print("=== \(run) ===")
            allOK = try check(run) && allOK
        }
        exit(allOK ? 0 : 1)
    default:
        throw ReplayError.usage("unknown mode '\(mode)'; usage: vzreplay <label|check|label-all|check-all> [run-dir]")
    }
} catch {
    FileHandle.standardError.write(Data("vzreplay: \(error)\n".utf8))
    exit(2)
}
