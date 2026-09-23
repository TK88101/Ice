// The repository's current commit, for the evidence manifest -- the same
// field probes/safewidth's `Evidence.writeManifest` records, there passed in
// by the caller (`swctl --git <revision>`) rather than discovered. This
// probe discovers it itself so a run can never be evidence-stamped with a
// revision nobody checked.
import Foundation

enum GitRevision {
    /// The package root: three levels up from this file
    /// (Sources/vizprobe/GitRevision.swift -> Sources/ -> package root),
    /// matching vzreplay/main.swift's own `#filePath` trick.
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // vizprobe/
        .deletingLastPathComponent() // Sources/
        .deletingLastPathComponent() // package root

    /// "unknown" rather than throwing: a missing git binary or a detached
    /// worktree must not stop a run from being evidenced, only leave that one
    /// field honestly unresolved.
    static func current() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", packageRoot.path, "rev-parse", "HEAD"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return "unknown"
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return "unknown"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
