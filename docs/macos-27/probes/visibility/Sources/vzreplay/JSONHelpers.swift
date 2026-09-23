import Foundation

/// One JSONL record, decoded loosely (the schema differs by `kind`, so a fixed
/// Codable type per record would just duplicate this dictionary anyway).
typealias Record = [String: Any]

enum JSONHelpers {
    /// Reads every line of a `samples.jsonl` file as a `Record`, in file order
    /// (Evidence.swift in swctl writes append-only, so file order is time order).
    static func loadRecords(_ url: URL) throws -> [Record] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var records: [Record] = []
        for line in text.split(separator: "\n") {
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? Record
            else {
                throw ReplayError.malformedRecord(String(line.prefix(120)))
            }
            records.append(object)
        }
        return records
    }

    static func loadObject(_ url: URL) throws -> Record {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? Record else {
            throw ReplayError.malformedRecord(url.lastPathComponent)
        }
        return object
    }
}

enum ReplayError: Error, CustomStringConvertible {
    case malformedRecord(String)
    case missingField(String, in: String)
    case decodeFailed(String)
    case reconstructionFailed(String)
    case unknownCase(String)
    case usage(String)

    var description: String {
        switch self {
        case .malformedRecord(let s): "malformed JSONL record: \(s)"
        case .missingField(let f, let ctx): "missing field '\(f)' in \(ctx)"
        case .decodeFailed(let s): "failed to decode \(s)"
        case .reconstructionFailed(let s): "reconstruction failed: \(s)"
        case .unknownCase(let s): "unknown case id: \(s)"
        case .usage(let s): s
        }
    }
}

/// Typed access into a loosely-decoded record. Every accessor throws by name
/// rather than returning an optional, so a schema surprise in the evidence
/// shows up as a reconstruction failure with a field name, not a silent nil.
extension Dictionary where Key == String, Value == Any {
    func string(_ key: String, context: String) throws -> String {
        guard let v = self[key] as? String else { throw ReplayError.missingField(key, in: context) }
        return v
    }

    func double(_ key: String, context: String) throws -> Double {
        if let v = self[key] as? Double { return v }
        if let v = self[key] as? Int { return Double(v) }
        if let v = self[key] as? NSNumber { return v.doubleValue }
        throw ReplayError.missingField(key, in: context)
    }

    func bool(_ key: String, context: String) throws -> Bool {
        guard let v = self[key] as? Bool else { throw ReplayError.missingField(key, in: context) }
        return v
    }

    func array(_ key: String, context: String) throws -> [Any] {
        guard let v = self[key] as? [Any] else { throw ReplayError.missingField(key, in: context) }
        return v
    }

    func recordArray(_ key: String, context: String) throws -> [Record] {
        try array(key, context: context).compactMap { $0 as? Record }
    }

    var kind: String? { self["kind"] as? String }
    var wall: String? { self["wall"] as? String }
    var capture: String? { self["capture"] as? String }
}

/// swctl stamps every record with `yyyy-MM-dd'T'HH:mm:ss.SSSXXX` (Evidence.swift).
enum WallClock {
    /// A fresh formatter per call, not a shared static one: this tool runs a
    /// handful of times per invocation, not in a hot loop, and
    /// `ISO8601DateFormatter` is not `Sendable` under Swift 6 strict
    /// concurrency.
    static func seconds(_ wall: String) throws -> Double {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: wall) else {
            throw ReplayError.decodeFailed("wall-clock timestamp \(wall)")
        }
        return date.timeIntervalSinceReferenceDate
    }
}
