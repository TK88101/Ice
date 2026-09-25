// I5: section 3's own preflight and section 5 step 2's one cycle (jump,
// settle, verdicts, collapse, settle, restored?, reset check) -- shared by
// the scan (one cycle per length) and the smoke (five cycles at the
// midpoint). P0-2: every capture goes through `latchingCapturer`. P0-3/4:
// the expansion window and its guaranteed collapse come from
// `StageC1.withExpansionWindow` (`C1StageMachine`, C1Live). G-a: the fold
// is only a credible trip while that window is closed. G-b: untemplated
// owner items are watched by keyed AX, not pixels.
import C1Core
import C1Live
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed

struct C1CycleResult {
    let reading: TargetReading
    /// Fold absent at the expansion, Protected and every templated owner
    /// item drawn, every untemplated owner item listed and stationary
    /// (G-b), and Target `restored` after the collapse: section 1's PASS
    /// list besides the reading itself.
    let otherChecksPassed: Bool
}

extension StageC1 {
    /// One full cycle: preflight -> jump -> settle -> read -> collapse ->
    /// settle -> restored? -> reset check. `nil` when the preflight never
    /// passes, a capture goes unreadable, or the run has gone terminal
    /// (P0-3: the caller's scan/smoke loop stops on the next check of
    /// `isTerminal`).
    func runCycle(length: Double, label: String) -> C1CycleResult? {
        guard performPreflight(label: label) else {
            capturesStayedUnreadable = capturesStayedUnreadable || !preflightEverPassed
            return nil
        }
        guard !isTerminal else { return nil }
        preflightEverPassed = true

        let hiddenReading: TargetReading? = withExpansionWindow(to: length) {
            Pump.run(1.0)
            return readTarget(label: "\(label).hidden")
        }
        // `withExpansionWindow`'s own `defer` has already sent `rest` and
        // closed the window (P0-4) by the time control reaches here,
        // whether `body` returned normally or a trip cut it short.
        guard !isTerminal, let hiddenReading else { return nil }
        // The fold is allowed here -- an expansion was in progress by
        // definition -- so this read is PASS-list bookkeeping only, never
        // fed to the latch (the window was open for the whole of it).
        let foldAbsentAtExpansion = readFoldValue(label: "\(label).fold") == .absent
        guard !isTerminal else { return nil }

        Pump.run(1.0)
        guard let restoredCheck = verifyOnce() else { return nil }
        guard !isTerminal else { return nil }
        let restored = classify(restoredCheck[targetKey!], expected: .stillDrawn) == .expected

        let protectedAndOwnersDrawn = readOwnerAndProtectedDrawn(label: "\(label).drawn")
        let untemplatedFailures = UntemplatedOwnerWatch.check(current: currentUntemplatedReadings(), baseline: untemplatedOwnerBaseline)
        guard !isTerminal else { return nil }

        // Item 7: a reset-check (baseline-equivalence) failure is itself
        // an immediate safety stop -- no result for this cycle, and the
        // caller's scan/smoke loop stops on `isTerminal` without any
        // further scan length or smoke cycle running.
        guard performResetCheck(label: "\(label).reset") else {
            markResetCheckFailed()
            return nil
        }
        guard !isTerminal else { return nil }

        let otherChecksPassed = foldAbsentAtExpansion && protectedAndOwnersDrawn && untemplatedFailures.isEmpty && restored
        evidence.record("cycle", ["label": label, "reading": "\(hiddenReading)", "otherChecksPassed": otherChecksPassed, "untemplatedFailures": untemplatedFailures.map { "\($0)" }])
        return C1CycleResult(reading: hiddenReading, otherChecksPassed: otherChecksPassed)
    }

    /// Reads Target's own `Hiding` through the C1-discoverer-backed
    /// verification (I4), mapped to C1Core's `TargetReading`.
    private func readTarget(label: String) -> TargetReading? {
        guard let results = verifyOnce(), let targetKey else { return nil }
        guard case .checked(let hiding)? = results[targetKey] else { return .refused }
        switch hiding {
        case .hidden(let folded): return .hidden(folded: folded)
        case .stillDrawn: return .stillDrawn
        case .unverifiable: return .refused
        }
    }

    private func verifyOnce() -> [ItemKey: SectionItemCheck]? {
        guard let prepared else { return nil }
        return Pump.blocking { await self.verification.verify(prepared) }
    }

    private func classify(_ check: SectionItemCheck?, expected: Hiding) -> CheckOutcome {
        if case .checked(let hiding)? = check, hiding == expected { return .expected }
        return .unexpected
    }

    private enum CheckOutcome { case expected, unexpected }

    /// G-a: one bracketed (capture -> AX -> capture), two-sample settled
    /// read of `targets`/`references` -- `nil` on a capture/AX failure
    /// (fed to the latch as an immediate abort) or an unsettled/unstable
    /// pair.
    func settledPairedRead(targets: [String], references: [String]) -> ObservationResult? {
        guard let first = ownerObserver.observe(baseline: ownerBaseline, targets: targets, references: references, items: ownerItemIDs), first.reading.captureStable else {
            latchingCapturer.feed(.init(captureFailed: true))
            return nil
        }
        Pump.run(1.0)
        guard let second = ownerObserver.observe(baseline: ownerBaseline, targets: targets, references: references, items: ownerItemIDs), second.reading.captureStable else {
            latchingCapturer.feed(.init(captureFailed: true))
            return nil
        }
        guard first.reading.fold == second.reading.fold, targets.allSatisfy({ first.visibility[$0] == second.visibility[$0] }) else {
            return nil
        }
        return second
    }

    /// The fold's plain value (P0-2's bracketed read, via the owner
    /// observer -- its sampler reads through `latchingCapturer`), with no
    /// window gating: used only where the fold is expected to be able to
    /// go either way (mid-expansion bookkeeping).
    func readFoldValue(label: String) -> Fold? {
        guard let ids = ownerObserverIDs(), let result = ownerObserver.observe(baseline: ownerBaseline, targets: [], references: Array(ids.keys), items: ids) else {
            latchingCapturer.feed(.init(captureFailed: true))
            return nil
        }
        return result.reading.fold
    }

    /// G-a: feeds a credible present fold to the latch, but only while
    /// the expansion window is closed -- the preflight, the reset check
    /// and teardown all call this; the mid-expansion read never does (the
    /// fold going up there is expected, not a violation).
    func watchFold(_ fold: Fold, label: String) {
        guard fold == .present, !expansionWindowOpen else { return }
        evidence.record("fold.appearedWithoutExpansion", ["label": label])
        latchingCapturer.feed(.init(foldAppearedWithoutExpansion: true))
    }

    private func ownerObserverIDs() -> [String: pid_t]? {
        ownerItemIDs.isEmpty ? nil : ownerItemIDs
    }

    /// Section 3: order (AX projected onto templated items vs. pixels,
    /// Target then the spacer leftmost), untemplated items listed and
    /// stationary (G-b), `.protected`/templated items drawn and the fold
    /// absent, the indicator unmoved, and the roster equalling the
    /// snapshot. Up to 3 attempts within 10 s; a first-ever failure
    /// relaunches the helpers once (section 3), after a
    /// discovery-confirmed reap (P0-6).
    func performPreflight(label: String) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        var attempt = 0
        while attempt < 3, Date() < deadline {
            attempt += 1
            if passesPreflightOnce(label: "\(label).\(attempt)") { return true }
            guard !isTerminal else { return false }
        }
        guard !preflightEverPassed, !isTerminal else { return false }
        evidence.record("preflight.relaunchOnce", ["label": label])
        guard confirmReap() else { return false }
        guard case .ok = step2Launch(), case .ok = step3Baseline() else { return false }
        for retryAttempt in 1...3 {
            if passesPreflightOnce(label: "\(label).relaunch.\(retryAttempt)") { return true }
            guard !isTerminal else { return false }
        }
        return false
    }

    /// C1's own settled paired preflight (P1): two stable, capture-active
    /// reads at least 1 s apart, immediately before `length` -- never the
    /// verifier's own `prepare()`-time preflight, which runs once at
    /// setup and never again.
    private func passesPreflightOnce(label: String) -> Bool {
        guard let targetKey, let spacerKey, let protectedKey else { return false }
        // Item 8: bounded, like the untemplated watch's own discovery read.
        guard let fresh = Pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }) else {
            latchingCapturer.feed(.init(captureFailed: true))
            return false
        }
        let axOrder = fresh.set.listedItems
            .filter { $0.frame != nil }
            .sorted { $0.frame!.minX < $1.frame!.minX }
            .map(\.key.encoded)

        // P1: pixel order is compared with the AX order projected onto
        // templated items only -- an untemplated item has no pixel
        // position to compare, so it would fail every preflight otherwise.
        let templatedIDs = Set(ownerBaseline.templates.keys)
        let axProjected = axOrder.filter { templatedIDs.contains($0) }

        let targets = ownerBaselineReadings.map(\.id) + [targetKey.encoded, spacerKey.encoded, protectedKey.encoded]
        guard let settled = settledPairedRead(targets: targets, references: [protectedKey.encoded]) else {
            evidence.record("preflight.notSettled", ["label": label])
            return false
        }

        let pixelOrder = targets.compactMap { id -> (String, Double)? in
            if case .drawn(let x)? = settled.visibility[id] { return (id, x) }
            return nil
        }.sorted { $0.1 < $1.1 }.map(\.0)

        watchFold(settled.reading.fold, label: "\(label).fold")
        guard !isTerminal else { return false }

        guard PreflightOrderCheck.check(axOrder: axProjected, pixelOrder: pixelOrder, target: targetKey.encoded, spacer: spacerKey.encoded) == nil else {
            evidence.record("preflight.orderFailed", ["label": label, "axProjected": axProjected, "pixel": pixelOrder])
            return false
        }
        guard settled.reading.fold == .absent else {
            evidence.record("preflight.foldNotAbsent", ["label": label])
            return false
        }
        guard targets.allSatisfy({ if case .drawn? = settled.visibility[$0] { return true }; return false }) else {
            evidence.record("preflight.notAllDrawn", ["label": label])
            return false
        }

        let untemplatedFailures = UntemplatedOwnerWatch.check(current: currentUntemplatedReadings(), baseline: untemplatedOwnerBaseline)
        guard untemplatedFailures.isEmpty else {
            evidence.record("preflight.untemplatedFailed", ["label": label, "failures": untemplatedFailures.map { "\($0)" }])
            return false
        }

        let indicator = detectIndicatorFrame()
        guard indicator == baselineIndicatorFrame else {
            evidence.record("preflight.indicatorMoved", ["label": label])
            return false
        }

        let snapshot = RosterSnapshot(items: axOrder, indicatorFrame: indicator)
        guard RosterSnapshotCheck.compare(current: snapshot, previous: rosterSnapshot) == .equal else {
            evidence.record("preflight.rosterChanged", ["label": label])
            return false
        }
        return true
    }

    /// Section 5's reset check: baseline-equivalent, including the three
    /// helpers and (G-b) every untemplated owner item. A mismatch is a
    /// safety stop; a pass resets the latch (only while not already
    /// terminal, P0-3) and takes a fresh full-AX-roster snapshot (P1).
    func performResetCheck(label: String) -> Bool {
        guard targetKey != nil, spacerKey != nil, protectedKey != nil else { return false }
        guard let capture = latchingCapturer.capture(), let ink = ownerBaseline.ink else { return false }
        let map = ink.map(capture)

        func x(_ id: String) -> Double? {
            guard let template = ownerBaseline.templates[id],
                  case .unique(let value, let mismatch) = TemplateMatcher.match(template, in: map, geometry: geometry, parameters: parameters),
                  mismatch <= parameters.maxMismatch
            else { return nil }
            return value
        }

        let currentOwners = ownerBaselineReadings.compactMap { reading in x(reading.id).map { BaselineEquivalence.Reading(id: reading.id, x: $0) } }
        let currentHelpers = helperBaselineReadings.compactMap { reading in x(reading.id).map { BaselineEquivalence.Reading(id: reading.id, x: $0) } }
        let fold = readFoldValue(label: "\(label).fold") ?? .unreadable
        watchFold(fold, label: "\(label).fold")
        guard !isTerminal else { return false }

        let input = BaselineEquivalence.Input(
            templatedOwnerItems: currentOwners,
            baselineTemplatedOwnerItems: ownerBaselineReadings,
            residualStripChanged: false,
            indicatorFrame: detectIndicatorFrame(),
            baselineIndicatorFrame: baselineIndicatorFrame,
            fold: fold == .present ? .present : (fold == .absent ? .absent : .unreadable),
            helpers: currentHelpers,
            baselineHelpers: helperBaselineReadings
        )
        let failures = BaselineEquivalence.check(input)
        let untemplatedFailures = UntemplatedOwnerWatch.check(current: currentUntemplatedReadings(), baseline: untemplatedOwnerBaseline)
        evidence.record("resetCheck", ["label": label, "failures": failures.map { "\($0)" }, "untemplatedFailures": untemplatedFailures.map { "\($0)" }])
        guard failures.isEmpty, untemplatedFailures.isEmpty else { return false }

        resetLatchIfNotTerminal()
        guard let fresh = Pump.blocking({ await self.discoverer.discover(previous: nil) }) else {
            latchingCapturer.feed(.init(captureFailed: true))
            return false
        }
        let items = fresh.set.listedItems.filter { $0.frame != nil }.sorted { $0.frame!.minX < $1.frame!.minX }.map(\.key.encoded)
        rosterSnapshot = RosterSnapshot(items: items, indicatorFrame: detectIndicatorFrame())
        return true
    }

    /// `.protected` and every templated owner item drawn (section 3
    /// condition 2 / section 1's PASS list).
    func readOwnerAndProtectedDrawn(label: String) -> Bool {
        guard let ids = ownerObserverIDs(), let protectedKey else { return false }
        let targets = ownerBaselineReadings.map(\.id) + [protectedKey.encoded]
        guard let result = ownerObserver.observe(baseline: ownerBaseline, targets: targets, references: [], items: ids) else { return false }
        return targets.allSatisfy {
            if case .drawn? = result.visibility[$0] { return true }
            return false
        }
    }
}
