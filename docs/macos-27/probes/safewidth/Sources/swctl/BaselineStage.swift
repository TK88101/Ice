// Stage B0 — session baseline with nothing of ours in the menu bar.
//
// Read-only: captures the strip and an AX snapshot once per interval for the
// given duration, with the user's own frontmost app. The analysis (static vs
// dynamic items, marker colours absent from the strip, negative control for the
// marker search) runs later over these files, so this stage only records.
import Foundation

enum BaselineStage {
    static func run(seconds: Double, interval: Double, evidence: Evidence, capture: StripCapture) {
        let clock = Session.clock
        let start = clock()
        var index = 0
        var failures = 0
        while clock() - start < seconds {
            let tick = clock()
            let snapshot = AXReader.snapshot()
            if let frame = capture.capture(clock: clock) {
                let name = evidence.keep(frame.file, label: "b0") ?? "?"
                evidence.record("b0.sample", [
                    "index": index,
                    "t": tick - start,
                    "captureStarted": frame.started - start,
                    "captureFinished": frame.finished - start,
                    "capture": name,
                    "pixelWidth": frame.bitmap.width,
                    "pixelHeight": frame.bitmap.height,
                    "scale": frame.bitmap.scale,
                ])
            } else {
                failures += 1
                evidence.record("b0.captureFailed", ["index": index, "t": tick - start])
            }
            evidence.record("b0.ax", value: snapshot)
            index += 1
            let remaining = interval - (clock() - tick)
            if remaining > 0 {
                Session.spin(remaining)
            }
        }
        evidence.record("b0.done", ["samples": index, "captureFailures": failures])
        print("b0: \(index) samples, \(failures) capture failures -> \(evidence.directory.path)")
    }
}
