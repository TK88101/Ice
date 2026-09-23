// Durable evidence for every run, outside the repository on purpose: the strips
// show the user's installed apps and the date. Only RESULTS.md, which cites run
// ids, is committed.
//
// Layout: ~/IceReverse-evidence/<run-id>/
//   manifest.json   run id, stage, git revision, binary path, arguments, screen geometry, times
//   samples.jsonl   one JSON object per line, written as the run goes
//   captures/       PNG copies of the captures worth keeping
import AppKit
import CryptoKit

final class Evidence {
    let runId: String
    let directory: URL
    private let samples: FileHandle
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private var kept = 0

    init(stage: String, arguments: [String], gitRevision: String) throws {
        let stamp = Self.timestamp(Date(), format: "yyyyMMdd-HHmmss")
        runId = "\(stamp)-\(stage)"
        directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("IceReverse-evidence")
            .appendingPathComponent(runId)
        let captures = directory.appendingPathComponent("captures")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        let samplesURL = directory.appendingPathComponent("samples.jsonl")
        FileManager.default.createFile(atPath: samplesURL.path, contents: nil)
        samples = try FileHandle(forWritingTo: samplesURL)
        try writeManifest(stage: stage, arguments: arguments, gitRevision: gitRevision)
    }

    /// Appends one record. Every record carries the wall-clock time it was written.
    func record(_ kind: String, _ fields: [String: Any]) {
        var object = fields
        object["kind"] = kind
        object["wall"] = Self.timestamp(Date(), format: "yyyy-MM-dd'T'HH:mm:ss.SSSXXX")
        guard
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else {
            FileHandle.standardError.write(Data("evidence: unencodable record \(kind)\n".utf8))
            return
        }
        samples.write(data)
        samples.write(Data("\n".utf8))
    }

    /// Appends an Encodable value under `kind`.
    func record<T: Encodable>(_ kind: String, value: T) {
        guard
            let data = try? encoder.encode(value),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return
        }
        record(kind, ["value": object])
    }

    /// Copies a capture into the evidence directory and returns its file name.
    @discardableResult
    func keep(_ file: URL, label: String) -> String? {
        kept += 1
        let name = String(format: "%05d-%@.png", kept, label)
        let target = directory.appendingPathComponent("captures").appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: file, to: target)
            return name
        } catch {
            return nil
        }
    }

    func close() {
        try? samples.close()
    }

    private func writeManifest(stage: String, arguments: [String], gitRevision: String) throws {
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let digest = (try? Data(contentsOf: binary)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        let screen = NSScreen.main
        let manifest: [String: Any] = [
            "runId": runId,
            "stage": stage,
            "gitRevision": gitRevision,
            "binary": binary.path,
            "binarySHA256": digest ?? "?",
            "arguments": arguments,
            "started": Self.timestamp(Date(), format: "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
            "screenFrame": screen.map { [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height] } ?? [],
            "notchLeft": screen?.auxiliaryTopLeftArea?.maxX ?? -1,
            "notchRight": screen?.auxiliaryTopRightArea?.minX ?? -1,
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("manifest.json"))
    }

    /// Built once: a record is written on every capture, and a fresh DateFormatter
    /// each time costs more than the record it stamps.
    private static let formatters: [String: DateFormatter] = {
        var built: [String: DateFormatter] = [:]
        for format in ["yyyyMMdd-HHmmss", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            built[format] = formatter
        }
        return built
    }()

    static func timestamp(_ date: Date, format: String) -> String {
        guard let formatter = formatters[format] else {
            let fallback = DateFormatter()
            fallback.locale = Locale(identifier: "en_US_POSIX")
            fallback.dateFormat = format
            return fallback.string(from: date)
        }
        return formatter.string(from: date)
    }
}
