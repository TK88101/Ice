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
        let cycleStart = environment.pump.now()
        defer { lastCycleDurationSeconds = environment.pump.now() - cycleStart }

        // F3 (Amendment v6, crosscheck #2/#7): before this cycle's own
        // preflight, at confirmed rest, re-prepare the verifier's baseline
        // whenever it would otherwise go stale before this cycle's own
        // verifies run.
        guard maybeRefreshVerificationBaseline(label: label) else { return nil }

        guard performPreflight(label: label) else {
            capturesStayedUnreadable = capturesStayedUnreadable || !preflightEverPassed
            return nil
        }
        guard !isTerminal else { return nil }
        preflightEverPassed = true

        let hiddenReading: TargetReading? = withExpansionWindow(to: length) {
            environment.pump.run(1.0)
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

        environment.pump.run(1.0)
        guard let restoredCheck = verifyOnce() else { return nil }
        guard !isTerminal else { return nil }
        // F3 (#7): a `.skipped` restored-check result (a stale baseline, a
        // failed capture, cancellation) means the verifier itself did not
        // run this pass -- not a real "Target stayed drawn or not" answer
        // `otherChecksPassed` can average out. Abort this cycle instead.
        guard !recordIfSkipped(restoredCheck[targetKey!], label: "\(label).restored") else { return nil }
        let restored = classify(restoredCheck[targetKey!], expected: .stillDrawn) == .expected

        let protectedAndOwnersDrawn = readOwnerAndProtectedDrawn(label: "\(label).drawn")
        let untemplatedFailures = UntemplatedOwnerWatch.check(current: currentUntemplatedReadings(), baseline: untemplatedOwnerBaseline)
        // Item 5: this cycle checkpoint's own keyed-check failure feeds
        // the latch at once -- an observed untemplated owner disappearance
        // must be a credible trip here, not only bookkeeping that lowers
        // `otherChecksPassed`.
        feedUntemplatedFailuresToLatch(untemplatedFailures)
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
        evidence?.record("cycle", ["label": label, "reading": "\(hiddenReading)", "otherChecksPassed": otherChecksPassed, "untemplatedFailures": untemplatedFailures.map { "\($0)" }])
        return C1CycleResult(reading: hiddenReading, otherChecksPassed: otherChecksPassed)
    }

    /// Reads Target's own `Hiding` through the C1-discoverer-backed
    /// verification (I4), mapped to C1Core's `TargetReading`.
    ///
    /// F3 (#7): a `.skipped` result (`.checked`'s sibling, meaning the
    /// verifier itself did not run this pass) is not folded into
    /// `.refused` any more -- see `recordIfSkipped`.
    private func readTarget(label: String) -> TargetReading? {
        guard let results = verifyOnce(), let targetKey else { return nil }
        let check = results[targetKey]
        guard !recordIfSkipped(check, label: label) else { return nil }
        guard case .checked(let hiding)? = check else { return .refused }
        switch hiding {
        case .hidden(let folded): return .hidden(folded: folded)
        case .stillDrawn: return .stillDrawn
        case .unverifiable: return .refused
        }
    }

    /// F3 (#7): `true`, and recorded, only for `.skipped(reason)` -- the
    /// infrastructure-level "this pass did not run at all" outcome
    /// (`baselineStale`, `captureFailed`, `cancelled`, ...), never
    /// `.refusedAtBaseline` (a genuine, if unfavourable, reading of
    /// Target itself, which stays an ordinary `.refused`).
    private func recordIfSkipped(_ check: SectionItemCheck?, label: String) -> Bool {
        guard case .skipped(let reason)? = check else { return false }
        evidence?.record("verify.skipped", ["label": label, "reason": "\(reason)"])
        return true
    }

    private func verifyOnce() -> [ItemKey: SectionItemCheck]? {
        guard let prepared else { return nil }
        // F3: recorded right before every verify, so a margin
        // miscalculation in `maybeRefreshVerificationBaseline` is visible
        // in evidence rather than silently producing `.skipped(.baselineStale)`.
        evidence?.record("verify.age", ["age": environment.pump.now() - prepared.createdAt])
        return environment.pump.blocking { await self.verification.verify(prepared) }
    }

    /// F3 (Amendment v6, crosscheck #2/#7): before this cycle's own
    /// preflight, at confirmed rest, re-prepares the verifier's baseline
    /// (`reusing: nil`) whenever its age plus a conservative estimate of
    /// *this* cycle's own duration would pass `BaselineReuse.maxAge`
    /// (600 s) less a safety margin -- `initialCycleDurationEstimateSeconds`
    /// for the very first cycle (nothing measured yet), then 1.5x the
    /// previous cycle's own measured wall time. The prediction is recorded
    /// in evidence either way. A failed re-prepare (never `.ready`) ends
    /// this cycle (`nil`) -- the caller's scan/smoke loop then falls
    /// through to teardown, never a smoke refusal that would erode toward
    /// PROVISIONAL FAIL.
    private func maybeRefreshVerificationBaseline(label: String) -> Bool {
        guard let prepared, let targetKey, let protectedKey else { return false }
        let age = environment.pump.now() - prepared.createdAt
        let predictedNext = lastCycleDurationSeconds.map { $0 * 1.5 } ?? StageC1.initialCycleDurationEstimateSeconds
        let shouldRefresh = age + predictedNext > BaselineReuse.maxAge - StageC1.baselineRefreshMarginSeconds
        evidence?.record("baseline.freshnessCheck", ["label": label, "age": age, "predictedNext": predictedNext, "refreshing": shouldRefresh])
        guard shouldRefresh else { return true }

        let sectionMap: [TagKey: ItemSection] = [targetKey.tagKey(isSelf: false): .hidden]
        let refreshed = environment.pump.blocking { await self.verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [protectedKey], reusing: nil) }
        guard case .ready = refreshed.state else {
            evidence?.record("baseline.refreshFailed", ["label": label, "state": "\(refreshed.state)"])
            return false
        }
        self.prepared = refreshed
        evidence?.record("baseline.refreshed", ["label": label, "createdAt": refreshed.createdAt])
        return true
    }

    private func classify(_ check: SectionItemCheck?, expected: Hiding) -> CheckOutcome {
        if case .checked(let hiding)? = check, hiding == expected { return .expected }
        return .unexpected
    }

    private enum CheckOutcome { case expected, unexpected }

    /// G-a: one bracketed (capture -> AX -> capture), two-sample settled
    /// read of `targets`/`references` -- `nil` on a capture/AX failure, an
    /// unsettled/unstable single read, or the two samples disagreeing.
    ///
    /// F4 (Amendment v6, crosscheck #3): only an *absent* observation (the
    /// sampler itself returned nothing -- a real capture or AX failure)
    /// latches `captureFailed`, an immediate abort. A successful but
    /// unstable read, or two successful reads that disagree, is recorded
    /// (`pairedRead.unstable`) and returned as `nil` *without* latching --
    /// section 4 only makes a failed capture or a late AX read an
    /// immediate abort; a transient (e.g. the spacer still animating back
    /// right after a collapse) is exactly what the caller's own retry
    /// budget (rest confirmation's 10 s deadline, the preflight's 3
    /// attempts) exists to absorb.
    func settledPairedRead(targets: [String], references: [String]) -> ObservationResult? {
        guard let first = ownerObserver.observe(baseline: ownerBaseline, targets: targets, references: references, items: ownerItemIDs) else {
            latchingCapturer.feed(.init(captureFailed: true))
            return nil
        }
        guard first.reading.captureStable else {
            evidence?.record("pairedRead.unstable", [:])
            return nil
        }
        environment.pump.run(1.0)
        guard let second = ownerObserver.observe(baseline: ownerBaseline, targets: targets, references: references, items: ownerItemIDs) else {
            latchingCapturer.feed(.init(captureFailed: true))
            return nil
        }
        guard second.reading.captureStable else {
            evidence?.record("pairedRead.unstable", [:])
            return nil
        }
        guard first.reading.fold == second.reading.fold, targets.allSatisfy({ first.visibility[$0] == second.visibility[$0] }) else {
            evidence?.record("pairedRead.unstable", [:])
            return nil
        }
        return second
    }

    /// The fold's plain value (P0-2's bracketed read, via the owner
    /// observer -- its sampler reads through `latchingCapturer`), with no
    /// window gating: used only where the fold is expected to be able to
    /// go either way (mid-expansion bookkeeping) and at the reset check.
    ///
    /// F1 (Amendment v6, crosscheck #0): references are the *templated*
    /// ids only -- `helperBaselineReadings` (Target, the spacer, Protected
    /// -- still alive during cycles) plus `ownerBaselineReadings`
    /// (templated owner items) -- never the raw `ownerItemIDs` keys, which
    /// also carry every baseline-rejected (untemplated) owner item.
    /// `CaptureStability.isStable` requires a template for *every*
    /// reference, so one untemplated id in that set made the fold
    /// unreadable on any real bar with at least one rejection (the owner's
    /// own bar recorded 2-6 every preflight). Every listed item is still
    /// sampled (`items: ids`) -- only the reference set narrows. Both call
    /// sites (mid-cycle bookkeeping and the reset check) run only once the
    /// spacer is confirmed back at rest, so Target is genuinely drawn at
    /// its baseline x here -- included as a reference is correct, not a
    /// repeat of the same bug. An empty templated reference set fails
    /// closed.
    func readFoldValue(label: String) -> Fold? {
        guard let ids = ownerObserverIDs() else {
            latchingCapturer.feed(.init(captureFailed: true))
            return nil
        }
        let templatedReferenceIDs = helperBaselineReadings.map(\.id) + ownerBaselineReadings.map(\.id)
        guard !templatedReferenceIDs.isEmpty,
              let result = ownerObserver.observe(baseline: ownerBaseline, targets: [], references: templatedReferenceIDs, items: ids)
        else {
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
        evidence?.record("fold.appearedWithoutExpansion", ["label": label])
        latchingCapturer.feed(.init(foldAppearedWithoutExpansion: true))
    }

    /// Item 5: any keyed (untemplated) check failure feeds the latch
    /// immediately, from every checkpoint that runs one -- a no-op when
    /// there is nothing to report.
    func feedUntemplatedFailuresToLatch(_ failures: [UntemplatedOwnerWatch.Failure]) {
        guard !failures.isEmpty else { return }
        latchingCapturer.feed(LatchObservationMerge.merge(templated: .init(), untemplated: failures))
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
        let deadline = environment.pump.now() + 10
        var attempt = 0
        while attempt < 3, environment.pump.now() < deadline {
            attempt += 1
            if passesPreflightOnce(label: "\(label).\(attempt)") { return true }
            guard !isTerminal else { return false }
        }
        guard !preflightEverPassed, !isTerminal else { return false }
        evidence?.record("preflight.relaunchOnce", ["label": label])
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
        guard let fresh = environment.pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }) else {
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
            evidence?.record("preflight.notSettled", ["label": label])
            return false
        }

        let pixelOrder = targets.compactMap { id -> (String, Double)? in
            if case .drawn(let x)? = settled.visibility[id] { return (id, x) }
            return nil
        }.sorted { $0.1 < $1.1 }.map(\.0)

        watchFold(settled.reading.fold, label: "\(label).fold")
        guard !isTerminal else { return false }

        guard PreflightOrderCheck.check(axOrder: axProjected, pixelOrder: pixelOrder, target: targetKey.encoded, spacer: spacerKey.encoded) == nil else {
            evidence?.record("preflight.orderFailed", ["label": label, "axProjected": axProjected, "pixel": pixelOrder])
            return false
        }
        guard settled.reading.fold == .absent else {
            evidence?.record("preflight.foldNotAbsent", ["label": label])
            return false
        }
        guard targets.allSatisfy({ if case .drawn? = settled.visibility[$0] { return true }; return false }) else {
            evidence?.record("preflight.notAllDrawn", ["label": label])
            return false
        }

        let untemplatedFailures = UntemplatedOwnerWatch.check(current: currentUntemplatedReadings(), baseline: untemplatedOwnerBaseline)
        // Item 5: a preflight's own keyed-check failure feeds the latch at
        // once too -- previously this only failed one preflight attempt,
        // which the caller simply retried.
        feedUntemplatedFailuresToLatch(untemplatedFailures)
        guard untemplatedFailures.isEmpty else {
            evidence?.record("preflight.untemplatedFailed", ["label": label, "failures": untemplatedFailures.map { "\($0)" }])
            return false
        }

        let indicator = detectIndicatorFrame()
        guard indicator == baselineIndicatorFrame else {
            evidence?.record("preflight.indicatorMoved", ["label": label])
            return false
        }

        let snapshot = RosterSnapshot(items: axOrder, indicatorFrame: indicator)
        guard RosterSnapshotCheck.compare(current: snapshot, previous: rosterSnapshot) == .equal else {
            evidence?.record("preflight.rosterChanged", ["label": label])
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
        // Item 5: the reset check's own keyed-check failure feeds the
        // latch at once too, same as the other two checkpoints -- on top
        // of `markResetCheckFailed()` (item 7), which the caller still
        // calls when this returns `false`; whichever reaches the machine
        // first is recorded, and either way the run stops here.
        feedUntemplatedFailuresToLatch(untemplatedFailures)
        evidence?.record("resetCheck", ["label": label, "failures": failures.map { "\($0)" }, "untemplatedFailures": untemplatedFailures.map { "\($0)" }])
        guard failures.isEmpty, untemplatedFailures.isEmpty else { return false }

        resetLatchIfNotTerminal()
        // F6 (Amendment v6, crosscheck #8/#11): through `timedDiscoverer`,
        // not the raw `discoverer` -- this fresh roster read runs every
        // cycle with all three helpers on the bar, so a hung pass here
        // must trip like every other post-launch discovery read.
        guard let fresh = environment.pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }) else {
            latchingCapturer.feed(.init(captureFailed: true))
            return false
        }
        guard !isTerminal else { return false }
        let items = fresh.set.listedItems.filter { $0.frame != nil }.sorted { $0.frame!.minX < $1.frame!.minX }.map(\.key.encoded)
        rosterSnapshot = RosterSnapshot(items: items, indicatorFrame: detectIndicatorFrame())
        return true
    }

    /// `.protected` and every templated owner item drawn (section 3
    /// condition 2 / section 1's PASS list).
    /// Rework #5 item 2 (r5b item 2, P0): Protected is the reference (an
    /// empty reference set was never stable, so `otherChecksPassed` could
    /// never be true -- the same class of bug as item 1); an unstable
    /// capture, same as a failed one, fails this check closed rather than
    /// silently reporting every target undrawn.
    func readOwnerAndProtectedDrawn(label: String) -> Bool {
        guard let ids = ownerObserverIDs(), let protectedKey else { return false }
        let targets = ownerBaselineReadings.map(\.id) + [protectedKey.encoded]
        guard let result = ownerObserver.observe(baseline: ownerBaseline, targets: targets, references: [protectedKey.encoded], items: ids),
              result.reading.captureStable
        else { return false }
        return targets.allSatisfy {
            if case .drawn? = result.visibility[$0] { return true }
            return false
        }
    }
}
