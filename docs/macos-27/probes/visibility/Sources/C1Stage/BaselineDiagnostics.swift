// Evidence-only: what step 3's own rest baseline saw, recorded per attempt so
// a "the fold is not absent at the rest baseline" abort says why (dry run
// 20260927-144131 stopped there with nothing recorded to tell `present` from
// `unreadable`). Changes no decision.
import IceCore

public enum BaselineDiagnostics {
    public static func fields(_ result: BaselineResult, parameters: DetectorParameters) -> [String: Any] {
        let notchHi: Double = result.geometry.notch?.hi ?? 0
        let onBar = result.agentFrames.filter { $0.minY >= 0 && $0.minY < result.geometry.heightPt }
        return [
            "fold": describe(result.foldAtBaseline),
            "inkCalibrated": result.ink != nil,
            "accepted": result.templates.count,
            "rejections": result.rejections.keys.sorted().map { "\($0): \(result.rejections[$0]!)" },
            "agentFrames": result.agentFrames.map { [$0.minX, $0.minY, $0.width] },
            "chevronSizedOnBar": onBar.filter { FoldWitness.isChevron($0, parameters: parameters) }.count,
            "notchHi": notchHi,
        ]
    }

    private static func describe(_ fold: Fold) -> String {
        switch fold {
        case .present: "present"
        case .absent: "absent"
        case .unreadable: "unreadable"
        }
    }
}
