// I5 step 3: section 2's "Baseline, taken once with the spacer at rest,"
// the `HidingVerification`/`C1Discoverer` composition that produces
// Target's `Hiding` verdicts, and the roster snapshot / latch baselines
// section 3 and section 4 read afterward. P0-2: every capture here goes
// through `latchingCapturer` (built in `step2Launch`), never the raw
// capturer. G-b: untemplated owner items get their own AX-keyed baseline
// alongside the pixel one.
//
// Rework #5, step A: geometry, the owner/verification AX readers and the
// trust check now come from `environment` (`C1StageEnvironment`) instead of
// `NSScreen`/`LiveMenuBarAXReader`/`DiscoveredFrameReader`/
// `AXIsProcessTrusted` directly.
import C1Core
import C1Live
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

extension StageC1 {
    func step3Baseline() -> StepResult {
        // F5: checked before this step's own work begins -- no baseline
        // work starts after a stop.
        guard !isTerminal else { return .abort("terminal before step 3") }
        guard let targetKey, let spacerKey, let protectedKey else { return .abort("helpers not launched") }
        // F6 (Amendment v6, crosscheck #8/#11): through `timedDiscoverer`,
        // not the raw `discoverer` -- every discovery pass after the
        // helpers exist goes through the one bounded executor.
        guard let pass = environment.pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }) else {
            return .abort("step 3: discovery failed")
        }
        guard !isTerminal else { return .abort("terminal during step 3's own discovery") }
        let origin = pass.origin

        // Every owner item plus the three helpers, id -> pid (section 2:
        // "Target, the spacer and Protected plus every owner item
        // discovery lists").
        var ids: [String: pid_t] = [
            targetKey.encoded: targetKey.pid,
            spacerKey.encoded: spacerKey.pid,
            protectedKey.encoded: protectedKey.pid,
        ]
        for item in pass.set.items where ![targetKey, spacerKey, protectedKey].contains(item.key) {
            ids[item.key.encoded] = item.key.pid
        }
        ownerItemIDs = ids

        // P0-2: the owner observer's sampler reads through the latch, not
        // the raw capturer -- the very baseline this step takes is itself
        // watched (its own `assess` closure is a no-op until this
        // baseline exists, which is exactly this call). Round 3 item 2:
        // the AX half of the sampler's bracket reads through the one
        // stage-wide `axExecutor`, not a private timed queue of its own.
        let reader = C1ExecutedAXReader(executor: axExecutor, wrapping: environment.ownerAXReaderFactory(origin))
        let pump = environment.pump
        let sampler = Sampler(capturer: latchingCapturer, axReader: reader, now: { pump.now() })
        ownerObserver = VisibilityObserver(sampler: sampler, parameters: parameters, sleep: { pump.sleep($0) })

        var lastBaseline: BaselineResult?
        for attempt in 0..<5 {
            if let result = ownerObserver.baseline(items: ids, geometry: geometry) {
                lastBaseline = result
                if result.foldAtBaseline == .absent { break }
            }
            if attempt < 4 { environment.pump.run(1.0) }
        }
        guard let ownerBaseline = lastBaseline else { return .abort("step 3: the rest baseline failed") }
        guard ownerBaseline.foldAtBaseline == .absent else { return .abort("step 3: the fold is not absent at the rest baseline") }
        self.ownerBaseline = ownerBaseline
        evidence?.record("step3.baseline", ["accepted": ownerBaseline.acceptedIDs.count, "rejected": ownerBaseline.rejections.count])

        // The C1Discoverer-backed verification (I4): Target the only
        // section item, Protected the explicit reference, the divider at
        // the spacer's own minX. P0-2: `latchingCapturer`, not the raw
        // capturer.
        //
        // `capturedEnvironment` (a value type -- see `C1StageEnvironment`),
        // `capturedAXExecutor` and `capturedLatchingCapturer` are all
        // captured by value/strong-reference here, not `self` -- so these
        // closures cannot form a retain cycle through `verification` (both
        // objects are already owned directly by `self` too, and neither
        // one references `self` or `verification` back), and never need a
        // "self/executor already gone" fallback the way a `[weak self]`
        // capture would.
        let liveOrigin = origin
        let capturedEnvironment = environment
        let capturedAXExecutor = axExecutor
        let capturedLatchingCapturer = latchingCapturer!
        verification = HidingVerification(
            // F6: `timedDiscoverer`, not the raw `discoverer` -- so
            // `HidingVerification.prepare()`'s own internal discovery call
            // (and every re-prepare, F3) is bounded like every other
            // post-launch discovery read.
            discoverer: C1Discoverer(base: timedDiscoverer, targetKey: targetKey, spacerKey: spacerKey, protectedKey: protectedKey),
            capturer: latchingCapturer,
            // Round 3 item 2: the reader backing `HidingVerification`'s
            // own internal Sampler shares the one stage-wide
            // `axExecutor` -- this is the one seam of that frozen type
            // this stage controls, and it must not run its own private
            // timed queue independent of every other AX read the stage
            // makes (that was exactly how a timed-out read here used to
            // become a quiet `.skipped(.captureFailed)`/`.refused`
            // instead of aborting the whole run).
            readerFactory: { readerOrigin in
                C1ExecutedAXReader(executor: capturedAXExecutor, wrapping: capturedEnvironment.verificationAXReaderFactory(readerOrigin))
            },
            geometry: { capturedEnvironment.geometryProvider() },
            preflight: {
                guard let geometry = capturedEnvironment.geometryProvider() else {
                    return .unavailable(.captureUnavailable)
                }
                let reader = C1ExecutedAXReader(executor: capturedAXExecutor, wrapping: capturedEnvironment.verificationAXReaderFactory(liveOrigin))
                // Item 10 (trust check): threaded explicitly, never
                // `Preflight.run`'s own `{ AXIsProcessTrusted() }` default.
                return Preflight.run(capturer: capturedLatchingCapturer, axReader: reader, geometry: geometry, isTrusted: capturedEnvironment.isTrusted)
            },
            sleep: { capturedEnvironment.pump.sleep($0) },
            now: { capturedEnvironment.pump.now() }
        )
        let sectionMap: [TagKey: ItemSection] = [targetKey.tagKey(isSelf: false): .hidden]
        let firstPrepared = environment.pump.blocking { await self.verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [protectedKey], reusing: nil) }
        guard case .ready = firstPrepared.state else {
            evidence?.record("step3.prepareFailed", ["state": "\(firstPrepared.state)"])
            return .abort("step 3: Target/Protected composition was not accepted by the C1 discoverer")
        }
        prepared = firstPrepared

        let seeded = seedBaselines(baseline: ownerBaseline, discovery: pass, targetID: targetKey.encoded, spacerID: spacerKey.encoded, protectedID: protectedKey.encoded)
        guard case .ok = seeded else { return seeded }
        preflightEverPassed = false
        return .ok
    }

    /// I3's `assess`: which owner ids (Target/spacer excluded) and which
    /// Protected id are missing from this capture, by the same
    /// unique-match-within-tolerance rule `SafetyMonitor.feed` uses. A
    /// no-op (`.init()`, never trips) before `ownerBaseline` exists -- the
    /// very first captures this decorator ever sees, during `step3Baseline`
    /// itself, have nothing to compare against yet (P0-2's note in
    /// `step2Launch`). The fold is not decided here -- it needs a full
    /// bracketed AX+pixel read this decorator's bare `StripCapturing` seam
    /// does not carry (G-a); the stage feeds it separately through
    /// `latchingCapturer.feed(_:)` at the checkpoints in
    /// `StageC1Cycle.swift`.
    ///
    /// Round 4 item 2: every untemplated owner item is *also* checked
    /// here, on this same capture, via a keyed discovery read (through
    /// `TimedDiscoverer`, so a late read is itself an abort) --
    /// `LatchObservationMerge` folds that into the templated result --
    /// not only at the stage's own checkpoints
    /// (`currentUntemplatedReadings()`, called separately by
    /// preflight/reset/teardown for their own bookkeeping). This makes
    /// every single capture the run takes watch the full owner
    /// population, matching Amendment v4's "used in every latch read."
    /// Rework #5 item 3 (r5b item 3, P0): Protected is never counted as a
    /// generic "owner item" (only its own explicit `protectedMissing`
    /// condition watches it) -- previously only Target/the spacer were
    /// subtracted, so Protected tripped `missingOwnerItems` too, on top of
    /// `protectedMissing`. And once `markProtectedTornDown()` has run (F2:
    /// the staged teardown's own stage 3, right before it quits Protected
    /// -- Target and the spacer are quit far earlier, at stage 1, but
    /// were never part of this gate), `protectedMissing` stops being
    /// watched at all: Protected disappearing is expected and correct
    /// once it is being quit on purpose, not a credible disappearance --
    /// the owner's own templated and keyed (untemplated) checks are
    /// unaffected either way.
    func assessLatch(image: StripImage) -> Latch.Observation {
        guard let ownerBaseline, let ink = ownerBaseline.ink, let protectedKey else { return .init() }
        let map = ink.map(image)
        func missing(_ id: String) -> Bool {
            guard let template = ownerBaseline.templates[id] else { return false }
            guard case .unique(let x, let mismatch) = TemplateMatcher.match(template, in: map, geometry: geometry, parameters: parameters),
                  mismatch <= parameters.maxMismatch,
                  abs(x - template.originXPt) <= parameters.referenceTolerancePt
            else { return true }
            return false
        }
        let helperIDs = [targetKey?.encoded, spacerKey?.encoded, protectedKey.encoded].compactMap { $0 }
        let ownerOnlyIDs = Set(ownerItemIDs.keys).subtracting(helperIDs)
        let missingOwners = ownerOnlyIDs.filter(missing).sorted()
        let protectedMissing = isProtectedTornDown ? false : missing(protectedKey.encoded)
        let templated = Latch.Observation(missingOwnerItems: missingOwners, protectedMissing: protectedMissing)

        guard !untemplatedOwnerBaseline.isEmpty else { return templated }
        let untemplatedFailures = assessUntemplatedFailures()
        return LatchObservationMerge.merge(templated: templated, untemplated: untemplatedFailures)
    }

    /// Section 3's roster snapshot (Amendment v4: "the fresh full AX
    /// roster, taken only after a passing reset" -- here, the baseline
    /// stands in for the first "passing reset"), section 5's
    /// baseline-equivalence readings for templated items, and G-b's AX
    /// baseline for untemplated ones.
    ///
    /// Item 4: a candidate untemplated owner item with no AX frame at
    /// baseline aborts the whole run here, before any expansion -- G-b's
    /// watch is only as good as the baseline it compares against, and an
    /// item this run cannot even place at the start can never be
    /// evaluated "listed and stationary" later. The earlier draft
    /// silently dropped such an item from `untemplatedOwnerBaseline`
    /// instead, which stopped watching it rather than refusing to run.
    func seedBaselines(baseline: BaselineResult, discovery: DiscoveryResult, targetID: String, spacerID: String, protectedID: String) -> StepResult {
        let indicator = detectIndicatorFrame()
        let fullRoster = discovery.set.listedItems
            .filter { $0.frame != nil }
            .sorted { $0.frame!.minX < $1.frame!.minX }
            .map(\.key.encoded)
        rosterSnapshot = RosterSnapshot(items: fullRoster, indicatorFrame: indicator)
        baselineIndicatorFrame = indicator

        ownerBaselineReadings = baseline.acceptedIDs
            .filter { $0 != targetID && $0 != spacerID && $0 != protectedID }
            .compactMap { id in baseline.templates[id].map { .init(id: id, x: $0.originXPt) } }
        helperBaselineReadings = [targetID, spacerID, protectedID].compactMap { id in
            baseline.templates[id].map { .init(id: id, x: $0.originXPt) }
        }

        // G-b: every owner item discovery lists but the pixel baseline did
        // not accept as a template -- watched by AX minX instead.
        let templatedIDs = Set(baseline.templates.keys)
        let untemplatedCandidates = discovery.set.listedItems
            .filter { ![targetKey, spacerKey, protectedKey].contains($0.key) && !templatedIDs.contains($0.key.encoded) }
        guard untemplatedCandidates.allSatisfy({ $0.frame != nil }) else {
            let missing = untemplatedCandidates.filter { $0.frame == nil }.map(\.key.encoded)
            evidence?.record("step3.untemplatedNoFrame", ["ids": missing])
            return .abort("step 3: an untemplated owner item (\(missing.joined(separator: ", "))) has no AX frame at baseline -- G-b fails closed")
        }
        untemplatedOwnerBaseline = untemplatedCandidates.map { UntemplatedOwnerWatch.Reading(id: $0.key.encoded, minX: $0.frame!.minX) }
        return .ok
    }

    /// The capture indicator: an extras-menu-bar item in
    /// `captureIndicatorWidthPt`, that is neither the chevron nor a
    /// privacy pill (the same rule `StageRun.readBar` uses -- restated as
    /// `C1CaptureIndicator`, like `C1HelperRole`/`SpacerIdentifier`,
    /// rather than imported from that internal executable-target file).
    func detectIndicatorFrame() -> BarFrame? {
        let onBar = environment.extrasScanner().filter { $0.minY >= 0 && $0.minY < geometry.heightPt && $0.bundleID == C1CaptureIndicator.menuBarAgentBundleID }
        let asFrame = { (item: C1ExtrasItem) in AgentFrame(minX: item.minX, minY: item.minY, width: item.width) }
        let indicator = onBar.first {
            C1CaptureIndicator.widthPt.contains($0.width)
                && !FoldWitness.isChevron(asFrame($0), parameters: parameters)
                && !FoldWitness.isPill(asFrame($0), parameters: parameters)
        }
        return indicator.map { BarFrame(minX: $0.minX, minY: $0.minY, width: $0.width, height: $0.height) }
    }

    /// G-b: every `untemplatedOwnerBaseline` id's current AX reading, from
    /// one fresh, bounded discovery pass (item 8: `TimedDiscoverer`) --
    /// `nil` for an id the pass could not read conclusively (failed,
    /// quarantined, or -- item 4 -- not actually enumerated this pass, so
    /// a stale carried-over item cannot be mistaken for a fresh read) or
    /// did not list at all, which `UntemplatedOwnerWatch.check` then
    /// fails closed on.
    func currentUntemplatedReadings() -> [String: UntemplatedOwnerWatch.Reading?] {
        guard !untemplatedOwnerBaseline.isEmpty else { return [:] }
        guard let discovery = environment.pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }) else {
            latchingCapturer.feed(.init(captureFailed: true))
            return Dictionary(uniqueKeysWithValues: untemplatedOwnerBaseline.map { ($0.id, Optional<UntemplatedOwnerWatch.Reading>.none) })
        }
        return untemplatedReadings(from: discovery)
    }

    /// Round 4 item 2: the same keyed check as `currentUntemplatedReadings()`,
    /// but safe to call from `assessLatch` -- which `LatchingCapturer.
    /// capture()` may run from any thread, including `HidingVerification`'s
    /// own internal serial queue, where `Pump.blocking`'s `RunLoop.main`
    /// spin would be unsafe. `nil` means the keyed read itself failed or
    /// came back late (through `timedDiscoverer`, whose own `onLate`
    /// already fed `.captureFailed` too); `LatchObservationMerge` treats
    /// that the same as a failed pixel capture.
    private func assessUntemplatedFailures() -> [UntemplatedOwnerWatch.Failure]? {
        guard let discovery = blockingDiscover(timedDiscoverer) else { return nil }
        return UntemplatedOwnerWatch.check(current: untemplatedReadings(from: discovery), baseline: untemplatedOwnerBaseline)
    }

    /// One thread-safe (no `RunLoop.main`) blocking bridge for the one
    /// discovery call `assessLatch` needs -- `Task.detached` plus a
    /// semaphore, not `environment.pump.blocking`.
    private func blockingDiscover(_ discoverer: any Discovering) -> DiscoveryResult? {
        let box = DiscoveryResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await discoverer.discover(previous: nil)
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

    private func untemplatedReadings(from discovery: DiscoveryResult) -> [String: UntemplatedOwnerWatch.Reading?] {
        let byID = Dictionary(uniqueKeysWithValues: discovery.set.listedItems.map { ($0.key.encoded, $0) })
        var result = [String: UntemplatedOwnerWatch.Reading?]()
        for base in untemplatedOwnerBaseline {
            guard let item = byID[base.id], let frame = item.frame else {
                result[base.id] = nil
                continue
            }
            let status = discovery.status(of: item.key.pid)
            guard status.enumerated, !status.failed, !status.quarantined, !status.permissionDenied else {
                result[base.id] = nil
                continue
            }
            result[base.id] = UntemplatedOwnerWatch.Reading(id: base.id, minX: frame.minX)
        }
        return result
    }
}

/// Restated from `Sources/vizprobe/StageRun.swift`/`BarScan.swift`
/// (internal to a different, executable target) rather than imported.
enum C1CaptureIndicator {
    static let menuBarAgentBundleID = "com.apple.MenuBarAgent"
    static let widthPt = 14.0...30.0
}

/// A thread-safe mutable box for `blockingDiscover`'s `Task.detached` to
/// hand its result back across.
private final class DiscoveryResultBox: @unchecked Sendable {
    var value: DiscoveryResult?
}
