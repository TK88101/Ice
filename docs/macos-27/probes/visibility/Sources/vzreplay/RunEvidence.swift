import Foundation

/// One run directory under `~/IceReverse-evidence/`: the manifest, every JSONL
/// record in file order, and where its captures live. Read-only — vzreplay
/// never writes here.
struct RunEvidence {
    let runId: String
    let directory: URL
    let manifest: Record
    let records: [Record]

    init(directory: URL) throws {
        self.directory = directory
        self.runId = directory.lastPathComponent
        self.manifest = try JSONHelpers.loadObject(directory.appendingPathComponent("manifest.json"))
        self.records = try JSONHelpers.loadRecords(directory.appendingPathComponent("samples.jsonl"))
    }

    func captureURL(_ name: String) -> URL {
        directory.appendingPathComponent("captures").appendingPathComponent(name)
    }

    /// The physical notch (camera housing), read from the manifest —
    /// `NSScreen.auxiliaryTopLeftArea.maxX` / `auxiliaryTopRightArea.minX`
    /// (swctl `Evidence.swift:95-96`). Every run on record has the same span,
    /// 771.5–956.5 pt, which is NOT the plan's assumed default of 640–1088 pt;
    /// see the deviation note in the final report.
    func notchSpan() throws -> (lo: Double, hi: Double) {
        let lo = try manifest.double("notchLeft", context: "manifest")
        let hi = try manifest.double("notchRight", context: "manifest")
        return (lo, hi)
    }

    /// `screenFrame` is `[x, y, width, height]` in points.
    func screenWidthPt() throws -> Double {
        guard let frame = manifest["screenFrame"] as? [Any], frame.count == 4, let width = frame[2] as? Double else {
            throw ReplayError.missingField("screenFrame", in: "manifest")
        }
        return width
    }

    func records(kind: String) -> [Record] {
        records.filter { $0.kind == kind }
    }

    /// The one `baseline` record: swctl's own pre-helper calibration (every
    /// user item's x/w/kind and the run's ink), taken before `com.icespike4.*`
    /// exists.
    func swctlBaseline() throws -> Record {
        guard let record = records(kind: "baseline").first else {
            throw ReplayError.reconstructionFailed("\(runId): no 'baseline' record")
        }
        return record
    }

    /// The nearest `assess` record to a wall-clock instant, and how far away it
    /// was (seconds). `assess` is the only kind that carries `ownAX` and
    /// `newAgentItems`; captures from other kinds (`probe`, `rest.check`,
    /// `teardown`) borrow the nearest one's Accessibility facts.
    func nearestAssess(to wallSeconds: Double) throws -> (record: Record, gap: Double) {
        var best: (Record, Double)?
        for record in records where record.kind == "assess" {
            guard let wall = record.wall, let seconds = try? WallClock.seconds(wall) else { continue }
            let gap = abs(seconds - wallSeconds)
            if best == nil || gap < best!.1 {
                best = (record, gap)
            }
        }
        guard let best else { throw ReplayError.reconstructionFailed("\(runId): no assess record at all") }
        return (best.0, best.1)
    }
}
