// C2 T5 (docs/plans/2026-09-28-c2-protocol.md section 2, T5): the owner-side
// commands -- `vizprobe c2-geometry` (the display's `--expect-geometry`
// value, for stage-c2.sh) and `vizprobe c2-read <run dir>` (verify the
// runner's final manifest, then summarize every step from the evidence
// alone). Read-only.
import AppKit
import C2Core
import Foundation
import IceCore
import MenuBarCapture

enum C2GeometryCommand {
    static func run() -> Never {
        guard let screen = NSScreen.main, let bar = BarGeometry(screen: screen) else { fail("c2-geometry: no main display") }
        print(C2Guards.Geometry(widthPt: bar.widthPt, heightPt: bar.heightPt, notchLo: bar.notch?.lo, notchHi: bar.notch?.hi).spec)
        exit(0)
    }
}

enum C2ReadCommand {
    static func run(_ arguments: [String]) -> Never {
        guard arguments.count >= 2 else { fail("c2-read: usage: vizprobe c2-read <run dir>") }
        let directory = URL(fileURLWithPath: arguments[1])
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("runner.final.json")),
              let final = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recorded = final["files"] as? [String: String]
        else { fail("c2-read: REFUSED -- no readable runner.final.json (the runner did not finish)") }
        let actual = C2RunCommand.hashes(of: directory).filter { $0.key != "runner.final.json" }
        guard C2Manifest.verify(recorded: recorded, actual: actual) else {
            fail("c2-read: REFUSED -- a file differs from runner.final.json")
        }
        print("sitting \(final["sitting"] ?? "?"): \(final["verdict"] ?? "?")")
        let steps = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.filter { !$0.hasPrefix("runner") }.sorted() ?? []
        for step in steps {
            let result = C2RunCommand.readBack(directory.appendingPathComponent(step))
            let band = C2Band.band(result.points).map { "band \(Int($0.lo))-\(Int($0.hi))" } ?? "no band"
            print("  \(step): \(result.status), \(result.points.count) points, \(band)")
        }
        exit(0)
    }
}
