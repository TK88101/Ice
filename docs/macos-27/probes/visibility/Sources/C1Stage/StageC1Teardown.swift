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
    /// Section 5 step 4 (F2, Amendment v6: staged teardown), then section
    /// 1's run accounting.
    ///
    /// F2 (crosscheck #1/#18): the old order quit and reaped *every*
    /// helper first (`runCleanup()`'s `.reapHelpers`/`confirmReap()`),
    /// then tried to read the fold with only the templated owner items
    /// left as references -- unreadable whenever an untemplated owner
    /// item sat left of the leftmost templated one (the owner's own bar),
    /// or unconditionally with none templated at all (I7 1b). The staged
    /// order instead: rest, quit and reap Target and the spacer only ->
    /// a settled read with Protected as the *sole* reference (nothing is
    /// left of it in the fold region once Target and the spacer are gone)
    /// -> quit and reap Protected -> the owner-population checks
    /// (templated pixels, keyed untemplated items, the indicator) with no
    /// second fold read. A failure at either staged step is a teardown
    /// mismatch; if Protected is itself already missing here the fold
    /// cannot be read at all -- also a mismatch (fail closed).
    func runTeardownAndDecide(scan: [(length: Double, reading: TargetReading)], smoke: [TargetReading], smokeChecks: [Bool]) -> Verdict {
        // P0-5: idempotent -- a no-op if a trip or the watchdog already
        // ran it. F2: this, and every cleanup path that can run ahead of
        // it (a trip, the watchdog, a signal, an off-main event), only
        // ever quits Target and the spacer -- Protected is untouched.
        runCleanup()

        // Stage 1: Target and the spacer confirmed gone.
        if !confirmNonProtectedReap() {
            markTeardownReapFailed()
        }

        // Stage 2: Protected is still up -- the staged fold read, while
        // it is the sole reference and so the leftmost item on the bar.
        if !confirmFoldAbsentBeforeProtectedQuits() {
            markTeardownMismatch()
        }

        // Stage 3: Protected's own quit and reap, only now. Marked as
        // torn-down *before* the quit so a capture racing this exact
        // moment does not read Protected's own now-expected disappearance
        // as a credible `protectedMissing` trip (mirrors the old,
        // single-stage `helpersTornDown` gate's own ordering).
        markProtectedTornDown()
        if !confirmProtectedReap() {
            markTeardownReapFailed()
        }

        for bundleID in C1HelperRole.all { environment.helperDefaults.forget(bundleID) }
        let domainsEmpty = C1HelperRole.all.allSatisfy { environment.helperDefaults.keys($0)?.isEmpty == true }
        evidence?.record("teardown.helperDomains", ["empty": domainsEmpty])
        // P1: a non-empty or unreadable helper preference domain fails
        // teardown -- a safety stop needing attention, not a plain PASS.
        // Item 1: routed through the machine (`markTeardownMismatch`),
        // never a stage-level flag `RunAccounting` might read before it
        // is set.
        if !domainsEmpty {
            markTeardownMismatch()
            evidence?.record("teardown.domainsNotEmpty", [:])
        }

        // Stage 4: the owner-population checks -- no second fold read
        // (F2): already confirmed absent above, while Protected was still
        // up as the sole reference.
        let teardownEquivalent = waitForTeardownBaselineEquivalence()
        if !teardownEquivalent {
            markTeardownMismatch()
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

    /// F2's own stage 2: a settled paired read (`settledPairedRead`,
    /// C1Cycle) with Protected as the *only* reference -- up to 10 s of
    /// retries for a stable pair (mirrors `confirmRestSettled`'s own
    /// budget). The fold must come back `.absent`; an unstable pair, a
    /// present or unreadable fold, or Protected itself missing by now
    /// (`protectedKey` set but the helper already gone) all fail this
    /// stage the same way -- a teardown mismatch, not a latch trip (a
    /// genuine capture/AX failure still latches through
    /// `settledPairedRead` itself, section 4's own immediate-abort rule).
    private func confirmFoldAbsentBeforeProtectedQuits() -> Bool {
        // Never reached the baseline (e.g. a signal during step2, before
        // step3 ever ran): `ownerObserver`/`ownerBaseline` do not exist
        // yet, so there is nothing to read -- nothing to compare, like
        // `waitForTeardownBaselineEquivalence()`'s own same guard.
        guard ownerBaseline != nil else { return true }
        guard let protectedKey else { return false }
        let deadline = environment.pump.now() + 10
        repeat {
            guard let settled = settledPairedRead(targets: [], references: [protectedKey.encoded]) else {
                guard !isTerminal else { return false }
                continue
            }
            evidence?.record("teardown.protectedFold", ["value": "\(settled.reading.fold)"])
            return settled.reading.fold == .absent
        } while !isTerminal && environment.pump.now() < deadline
        return false
    }

    /// Section 5 step 4: "the bar -- now without the helpers -- must be
    /// baseline-equivalent for the owner population within 30 s, else a
    /// safety stop needing the owner's attention." No helper readings
    /// here -- they are gone by design once torn down. Includes G-b's
    /// untemplated owner check. F2: the fold is not read again here --
    /// `confirmFoldAbsentBeforeProtectedQuits()` already confirmed it
    /// absent, once, before Protected was quit.
    private func waitForTeardownBaselineEquivalence() -> Bool {
        guard ownerBaseline != nil else { return true } // never reached baseline: nothing to compare
        let deadline = environment.pump.now() + 30
        repeat {
            guard let capture = latchingCapturer.capture(), let ink = ownerBaseline.ink else {
                environment.pump.run(1.0)
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
            let input = BaselineEquivalence.Input(
                templatedOwnerItems: current,
                baselineTemplatedOwnerItems: ownerBaselineReadings,
                residualStripChanged: false,
                indicatorFrame: detectIndicatorFrame(),
                baselineIndicatorFrame: baselineIndicatorFrame,
                fold: .absent,
                helpers: nil,
                baselineHelpers: nil
            )
            let untemplatedFailures = UntemplatedOwnerWatch.check(current: currentUntemplatedReadings(), baseline: untemplatedOwnerBaseline)
            if BaselineEquivalence.check(input).isEmpty, untemplatedFailures.isEmpty {
                evidence?.record("teardown.baselineEquivalent", ["matched": true])
                return true
            }
            environment.pump.run(1.0)
        } while environment.pump.now() < deadline
        evidence?.record("teardown.baselineEquivalent", ["matched": false])
        return false
    }
}
