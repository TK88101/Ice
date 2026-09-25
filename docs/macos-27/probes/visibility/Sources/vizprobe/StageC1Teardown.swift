// I5: section 5 step 4's teardown (rest, quit and reap, stop caffeinate,
// helper domains empty, baseline-equivalent within 30 s) and section 1's
// run accounting, both driven by `RunAccounting.decide` (C1Core).
import AppKit
import C1Core
import Foundation
import IceCore
import MenuBarCapture

extension StageC1 {
    /// Rests the spacer, quits every helper, and confirms none of their
    /// items is listed any more -- section 2's relaunch rule and section
    /// 5 step 4's teardown share this.
    func reapAll() -> Bool {
        expansionDriver?.collapse()
        channel?.quitAll()
        Pump.run(1.0)
        let helperPIDs = [targetHelper, spacerHelper, protectedHelper].compactMap { $0?.pid }
        guard !helperPIDs.isEmpty else { return true }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let result = Pump.blocking({ await self.discoverer.discover(previous: nil) }),
               !result.set.items.contains(where: { helperPIDs.contains($0.key.pid) }) {
                return true
            }
            Pump.run(0.2)
        }
        return false
    }

    /// Section 5 step 4: teardown, then section 1's run accounting.
    func runTeardownAndDecide(scan: [(length: Double, reading: TargetReading)], smoke: [TargetReading], smokeChecks: [Bool]) -> Verdict {
        _ = reapAll()
        stopCaffeinate()
        for bundleID in C1HelperRole.all { HelperDefaults.forget(bundleID) }
        let domainsEmpty = C1HelperRole.all.allSatisfy { HelperDefaults.keys($0)?.isEmpty == true }
        evidence.record("teardown.helperDomains", ["empty": domainsEmpty])

        let teardownEquivalent = waitForTeardownBaselineEquivalence()
        if !teardownEquivalent {
            safetyStop = .needingAttention
        }

        let input = RunAccounting.Input(
            preflightEverPassed: preflightEverPassed,
            capturesStayedUnreadable: capturesStayedUnreadable,
            scanReadings: scan.map(\.reading),
            smokeReadings: smoke,
            smokeChecksPassed: smokeChecks,
            safetyStop: safetyStop
        )
        return RunAccounting.decide(input)
    }

    /// Section 5 step 4: "the bar -- now without the helpers -- must be
    /// baseline-equivalent for the owner population within 30 s, else a
    /// safety stop needing the owner's attention." No helper readings
    /// here -- they are gone by design once torn down.
    private func waitForTeardownBaselineEquivalence() -> Bool {
        guard ownerBaseline != nil else { return true } // never reached baseline: nothing to compare
        let deadline = Date().addingTimeInterval(30)
        repeat {
            guard let capture = capturer.capture(), let ink = ownerBaseline.ink else {
                Pump.run(1.0)
                continue
            }
            let map = ink.map(capture)
            let current = ownerBaselineReadings.compactMap { reading -> BaselineEquivalence.Reading? in
                guard let template = ownerBaseline.templates[reading.id],
                      case .unique(let x, let mismatch) = TemplateMatcher.match(template, in: map, geometry: geometry, parameters: parameters),
                      mismatch <= parameters.maxMismatch
                else { return nil }
                return .init(id: reading.id, x: x)
            }
            let fold = readFoldForTeardown()
            let input = BaselineEquivalence.Input(
                templatedOwnerItems: current,
                baselineTemplatedOwnerItems: ownerBaselineReadings,
                residualStripChanged: false,
                indicatorFrame: detectIndicatorFrame(),
                baselineIndicatorFrame: baselineIndicatorFrame,
                fold: fold,
                helpers: nil,
                baselineHelpers: nil
            )
            if BaselineEquivalence.check(input).isEmpty {
                evidence.record("teardown.baselineEquivalent", ["matched": true])
                return true
            }
            Pump.run(1.0)
        } while Date() < deadline
        evidence.record("teardown.baselineEquivalent", ["matched": false])
        return false
    }

    private func readFoldForTeardown() -> FoldState {
        guard !ownerItemIDs.isEmpty,
              let result = ownerObserver.observe(baseline: ownerBaseline, targets: [], references: Array(ownerItemIDs.keys), items: ownerItemIDs)
        else { return .unreadable }
        switch result.reading.fold {
        case .present: return .present
        case .absent: return .absent
        case .unreadable: return .unreadable
        }
    }

}
