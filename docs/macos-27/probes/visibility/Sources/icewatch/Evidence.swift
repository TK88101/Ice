// icewatch's evidence: one JSONL file (`icewatch.jsonl`: ticks and events)
// and a status file rewritten once a second, both inside the run's evidence
// directory under ~/IceReverse-evidence, never in the repo.
import Foundation

final class Evidence {
    let directory: URL
    private let handle: FileHandle
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(directory: String) throws {
        self.directory = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let file = self.directory.appendingPathComponent("icewatch.jsonl")
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
    }

    func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path)
    }

    func modificationDate(_ name: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url(name).path))?[.modificationDate] as? Date
    }

    func record(_ kind: String, _ fields: [String: Any] = [:]) {
        var object = fields
        object["kind"] = kind
        object["wall"] = isoFormatter.string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        handle.write(data)
        handle.write(Data([0x0A]))
    }

    func writeStatus(_ status: [String: Any]) {
        var object = status
        object["wall"] = isoFormatter.string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted]) else { return }
        try? data.write(to: url("icewatch-status.json"), options: .atomic)
    }

    func writeMarker(_ name: String, _ text: String) {
        try? Data(text.utf8).write(to: url(name), options: .atomic)
    }
}
