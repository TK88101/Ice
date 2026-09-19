// `vizprobe --dry-run`: preflight and one baseline attempt against the
// user's own bar, nothing launched, no helper, no evidence beyond this
// printed summary (T13 DoD).
import AppKit
import Foundation
import IceCore
import MenuBarCapture

enum DryRun {
    static func run() -> Int32 {
        let capturer = CGWindowListStripCapturer()
        let axReader = NSScreen.main.map { LiveMenuBarAXReader(screen: $0) } ?? LiveMenuBarAXReader()
        let outcome = PreflightCheck.run(capturer: capturer, axReader: axReader)

        print("=== vizprobe --dry-run ===")
        guard let geometry = outcome.geometry else {
            print("geometry: could not be read from NSScreen.main (no safe-area top inset?)")
            return 1
        }
        print("geometry: widthPt=\(fmt(geometry.widthPt)) heightPt=\(fmt(geometry.heightPt)) scale=\(fmt(geometry.scale)) notch=\(describeNotch(geometry.notch))")

        switch outcome.preflight {
        case .ready:
            print("preflight: ready")
        case .unavailable(let reason):
            print("preflight: unavailable (\(reason))")
            print("nothing further attempted: preflight is the first of the plan's four checks (section 4), and nothing after it may run once it fails.")
            return 1
        }

        guard let room = outcome.room else {
            print("room check: not attempted")
            return 1
        }
        if let x = room.leftmostThirdPartyX {
            print("leftmost third-party item: x=\(fmt(x)) pt")
        } else {
            print("leftmost third-party item: none found")
        }
        if let free = room.freeRoomPt {
            print("free room right of the notch: \(fmt(free)) pt (needs >= \(fmt(PreflightCheck.minFreeRoomPt)) pt)")
        } else {
            print("free room right of the notch: unknown (no third-party item to measure to)")
        }
        print(
            room.agentFramesLeftOfLeftmost.isEmpty
                ? "MenuBarAgent frames left of the leftmost third-party item: none"
                : "MenuBarAgent frames left of the leftmost third-party item: \(room.agentFramesLeftOfLeftmost.count) (this is what a chevron or a privacy pill looks like)"
        )

        guard let baseline = outcome.baseline else {
            print("baseline attempt: failed (a capture or an Accessibility read did not complete)")
            return 1
        }
        print("baseline attempt: foldAtBaseline=\(baseline.foldAtBaseline) ink=\(baseline.ink != nil ? "calibrated" : "unknown")")
        print("baseline attempt: \(baseline.templates.count) item(s) accepted, \(baseline.rejections.count) rejected")
        for id in baseline.acceptedIDs {
            print("  accepted: \(id)")
        }
        for (id, rejection) in baseline.rejections.sorted(by: { $0.key < $1.key }) {
            print("  rejected: \(id) -- \(rejection)")
        }

        let verdict = outcome.ready ? "would proceed to step 2 (launching helpers)" : "would abort here"
        var reasons = [String]()
        if outcome.chevronOrPillSignal { reasons.append("chevron/pill signal present") }
        if !outcome.freeRoomOK { reasons.append("free room check failed") }
        print("verdict: \(verdict)\(reasons.isEmpty ? "" : " (" + reasons.joined(separator: ", ") + ")") -- nothing was launched")
        return 0
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func describeNotch(_ notch: PtSpan?) -> String {
        guard let notch else { return "none" }
        return "\(fmt(notch.lo))-\(fmt(notch.hi)) pt"
    }
}
