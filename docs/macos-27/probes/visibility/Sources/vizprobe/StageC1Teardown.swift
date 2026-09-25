// I5: section 5 step 4's teardown (rest, quit and reap, stop caffeinate,
// helper domains empty, baseline-equivalent within 30 s) and section 1's
// run accounting, both driven by `RunAccounting.decide` (C1Core). P0-5:
// every exit funnels through the one idempotent cleanup
// (`StageC1.runCleanup()`/`C1StageMachine.cleanup()`). P0-6: a reap
// failure here is a safety stop needing attention, not a silent PASS.
import AppKit
import C1Core
import Foundation
import IceCore
import MenuBarCapture

extension StageC1 {
    /// Section 5 step 4: teardown, then section 1's run accounting.
    func runTeardownAndDecide(scan: [(length: Double, reading: TargetReading)], smoke: [TargetReading], smokeChecks: [Bool]) -> Verdict {
        // P0-5: idempotent -- a no-op if a trip or the watchdog already
        // ran it.
        runCleanup()

        // P0-6: teardown's own authoritative reap check, whether or not
        // `runCleanup()`'s own `.reapHelpers` action just ran one.
        if !confirmReap() {
            markTeardownReapFailed()
        }

        for bundleID in C1HelperRole.all { HelperDefaults.forget(bundleID) }
        let domainsEmpty = C1HelperRole.all.allSatisfy { HelperDefaults.keys($0)?.isEmpty == true }
        evidence.record("teardown.helperDomains", ["empty": domainsEmpty])
        // P1: a non-empty or unreadable helper preference domain fails
        // teardown -- a safety stop needing attention, not a plain PASS.
        if !domainsEmpty {
            safetyStop = safetyStop ?? .needingAttention
            evidence.record("teardown.domainsNotEmpty", [:])
        }

        let teardownEquivalent = waitForTeardownBaselineEquivalence()
        if !teardownEquivalent {
            safetyStop = safetyStop ?? .needingAttention
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
    /// here -- they are gone by design once torn down. Includes G-b's
    /// untemplated owner check.
    private func waitForTeardownBaselineEquivalence() -> Bool {
        guard ownerBaseline != nil else { return true } // never reached baseline: nothing to compare
        let deadline = Date().addingTimeInterval(30)
        repeat {
            guard let capture = latchingCapturer.capture(), let ink = ownerBaseline.ink else {
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
            if fold == .present { watchFoldAtTeardown() }
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
            let untemplatedFailures = UntemplatedOwnerWatch.check(current: currentUntemplatedReadings(), baseline: untemplatedOwnerBaseline)
            if BaselineEquivalence.check(input).isEmpty, untemplatedFailures.isEmpty {
                evidence.record("teardown.baselineEquivalent", ["matched": true])
                return true
            }
            Pump.run(1.0)
        } while Date() < deadline
        evidence.record("teardown.baselineEquivalent", ["matched": false])
        return false
    }

    /// G-a at teardown: the expansion window is always closed by this
    /// point (there is no more scanning), so a present fold here is
    /// always credible.
    private func watchFoldAtTeardown() {
        guard !expansionWindowOpen else { return }
        latchingCapturer.feed(.init(foldAppearedWithoutExpansion: true))
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
