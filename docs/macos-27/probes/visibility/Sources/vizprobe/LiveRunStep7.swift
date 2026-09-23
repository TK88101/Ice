// Plan 6.1 step 7: teardown. Quits the helpers (EOF, never a signal),
// deletes their defaults, re-baselines, and checks every user item is back
// at its pre-flight x with no chevron up.
import Foundation
import IceCore

extension LiveRun {
    func step7Teardown() -> StepResult {
        quitHelpers()
        Thread.sleep(forTimeInterval: 1.0)

        guard let postBaseline = ThirdPartyBaseline.take(capturer: capturer, geometry: geometry, parameters: parameters) else {
            return .abort("teardown: could not re-baseline the bar")
        }
        evidence.record("teardown.baseline", ["accepted": postBaseline.acceptedIDs, "foldAtBaseline": "\(postBaseline.foldAtBaseline)"])

        guard postBaseline.foldAtBaseline == .absent else {
            return .abort("teardown: the chevron is up after quitting the helpers")
        }

        var displaced = [String]()
        for id in preflightBaseline.acceptedIDs {
            guard let before = preflightBaseline.templates[id], let after = postBaseline.templates[id] else {
                displaced.append(id)
                continue
            }
            if abs(before.originXPt - after.originXPt) > parameters.referenceTolerancePt {
                displaced.append(id)
            }
        }
        evidence.record("teardown.displaced", ["ids": displaced])
        guard displaced.isEmpty else {
            return .abort("teardown: user item(s) not back at their pre-flight x: \(displaced.joined(separator: ", "))")
        }
        return .ok
    }
}
