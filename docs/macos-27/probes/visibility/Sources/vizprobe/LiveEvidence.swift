// Durable evidence for one live run, outside the repository on purpose --
// the captures show the user's own bar. Only what cites a run id belongs in
// the repo.
//
// Layout: ~/IceReverse-evidence/<run-id>/
//   manifest.json   run id, git SHA, binary hashes, parameters, geometry, times
//   samples.jsonl   one JSON object per line, written as the run goes
//   captures/       PNG copies of the captures worth keeping
//
// Mirrors probes/safewidth/Sources/swctl/Evidence.swift; not shared with it
// because that file lives in a different probe this task may not modify.
import CryptoKit
import Foundation
import IceCore

final class LiveEvidence {
    let runId: String
    let directory: URL
    private let samples: FileHandle
    private var kept = 0

    init(binaryURLs: [String: URL], arguments: [String], geometry: BarGeometry?, parameters: DetectorParameters, suffix: String = "vzlive") throws {
        let stamp = Self.timestamp(Date(), format: "yyyyMMdd-HHmmss")
        runId = "\(stamp)-\(suffix)"
        directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("IceReverse-evidence")
            .appendingPathComponent(runId)
        let captures = directory.appendingPathComponent("captures")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        let samplesURL = directory.appendingPathComponent("samples.jsonl")
        FileManager.default.createFile(atPath: samplesURL.path, contents: nil)
        samples = try FileHandle(forWritingTo: samplesURL)
        try writeManifest(binaryURLs: binaryURLs, arguments: arguments, geometry: geometry, parameters: parameters)
    }

    /// Appends one record, stamped with the wall-clock time it was written.
    func record(_ kind: String, _ fields: [String: Any]) {
        var object = fields
        object["kind"] = kind
        object["wall"] = Self.timestamp(Date(), format: "yyyy-MM-dd'T'HH:mm:ss.SSSXXX")
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else {
            FileHandle.standardError.write(Data("vizprobe: unencodable evidence record \(kind)\n".utf8))
            return
        }
        samples.write(data)
        samples.write(Data("\n".utf8))
    }

    /// Writes a capture into the evidence directory and returns its file name.
    @discardableResult
    func keep(_ image: StripImage, label: String) -> String? {
        kept += 1
        let name = String(format: "%05d-%@.png", kept, label)
        let target = directory.appendingPathComponent("captures").appendingPathComponent(name)
        do {
            try image.writePNG(to: target)
            return name
        } catch {
            return nil
        }
    }

    func close() {
        try? samples.close()
    }

    private func writeManifest(binaryURLs: [String: URL], arguments: [String], geometry: BarGeometry?, parameters: DetectorParameters) throws {
        var binaries = [String: Any]()
        for (name, url) in binaryURLs {
            binaries[name] = ["path": url.path, "sha256": Self.sha256(of: url) ?? "?"]
        }
        var manifest: [String: Any] = [
            "runId": runId,
            "gitRevision": GitRevision.current(),
            "binaries": binaries,
            "arguments": arguments,
            "started": Self.timestamp(Date(), format: "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "parameters": Self.describe(parameters),
        ]
        if let geometry {
            manifest["geometry"] = [
                "widthPt": geometry.widthPt,
                "heightPt": geometry.heightPt,
                "scale": geometry.scale,
                "notchLo": (geometry.notch?.lo).map { $0 as Any } ?? NSNull(),
                "notchHi": (geometry.notch?.hi).map { $0 as Any } ?? NSNull(),
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("manifest.json"))
    }

    /// `DetectorParameters` is not `Codable` (Packages/IceCore keeps its
    /// public surface to the standard library plus `Equatable`/`Sendable`),
    /// so the fields the ledger cares about are copied out by hand rather
    /// than reflected.
    private static func describe(_ parameters: DetectorParameters) -> [String: Any] {
        [
            "maxMismatch": parameters.maxMismatch,
            "foundThreshold": parameters.foundThreshold,
            "weakThreshold": parameters.weakThreshold,
            "coreInkFactor": parameters.coreInkFactor,
            "coreBackgroundFraction": parameters.coreBackgroundFraction,
            "templateMarginPx": parameters.templateMarginPx,
            "suppressionRadiusPx": parameters.suppressionRadiusPx,
            "minTemplateWidthPt": parameters.minTemplateWidthPt,
            "referenceTolerancePt": parameters.referenceTolerancePt,
            "sightingTolerancePt": parameters.sightingTolerancePt,
            "placementSlackPt": parameters.placementSlackPt,
            "readAgreementTolerancePt": parameters.readAgreementTolerancePt,
            "minSamples": parameters.minSamples,
            "minSampleSpacing": parameters.minSampleSpacing,
            "baselineMinSamples": parameters.baselineMinSamples,
            "baselineMinSpan": parameters.baselineMinSpan,
            "baselineDroppedSamples": parameters.baselineDroppedSamples,
            "chevronWidthPt": parameters.chevronWidthPt,
            "chevronWidthTolerancePt": parameters.chevronWidthTolerancePt,
            "pillWidthPt": parameters.pillWidthPt,
            "pillWidthTolerancePt": parameters.pillWidthTolerancePt,
            "agentXTolerancePt": parameters.agentXTolerancePt,
            "agentWidthTolerancePt": parameters.agentWidthTolerancePt,
            "foldClusterMinPx": parameters.foldClusterMinPx,
            "regionAgreementMax": parameters.regionAgreementMax,
        ]
    }

    private static func sha256(of url: URL) -> String? {
        (try? Data(contentsOf: url)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
    }

    private static let formatters: [String: DateFormatter] = {
        var built = [String: DateFormatter]()
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
