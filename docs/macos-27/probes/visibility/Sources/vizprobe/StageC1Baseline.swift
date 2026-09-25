// I5 step 3: section 2's "Baseline, taken once with the spacer at rest,"
// the `HidingVerification`/`C1Discoverer` composition that produces
// Target's `Hiding` verdicts, and the roster snapshot / latch baselines
// section 3 and section 4 read afterward. P0-2: every capture here goes
// through `latchingCapturer` (built in `step2Launch`), never the raw
// capturer. G-b: untemplated owner items get their own AX-keyed baseline
// alongside the pixel one.
import AppKit
import C1Core
import C1Live
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

extension StageC1 {
    func step3Baseline() -> StepResult {
        guard let targetKey, let spacerKey, let protectedKey else { return .abort("helpers not launched") }
        guard let pass = Pump.blocking({ await self.discoverer.discover(previous: nil) }) else {
            return .abort("step 3: discovery failed")
        }
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
        // baseline exists, which is exactly this call). Item 8: the AX
        // half of the sampler's bracket is bounded too.
        let reader = TimedAXReader(wrapping: LiveMenuBarAXReader(origin: CGPoint(x: origin.x, y: origin.y)))
        let sampler = Sampler(capturer: latchingCapturer, axReader: reader)
        ownerObserver = VisibilityObserver(sampler: sampler, parameters: parameters)

        var lastBaseline: BaselineResult?
        for attempt in 0..<5 {
            if let result = ownerObserver.baseline(items: ids, geometry: geometry) {
                lastBaseline = result
                if result.foldAtBaseline == .absent { break }
            }
            if attempt < 4 { Pump.run(1.0) }
        }
        guard let ownerBaseline = lastBaseline else { return .abort("step 3: the rest baseline failed") }
        guard ownerBaseline.foldAtBaseline == .absent else { return .abort("step 3: the fold is not absent at the rest baseline") }
        self.ownerBaseline = ownerBaseline
        evidence.record("step3.baseline", ["accepted": ownerBaseline.acceptedIDs.count, "rejected": ownerBaseline.rejections.count])

        // The C1Discoverer-backed verification (I4): Target the only
        // section item, Protected the explicit reference, the divider at
        // the spacer's own minX. P0-2: `latchingCapturer`, not the raw
        // capturer.
        let liveOrigin = origin
        verification = HidingVerification(
            discoverer: C1Discoverer(base: discoverer, targetKey: targetKey, spacerKey: spacerKey, protectedKey: protectedKey),
            capturer: latchingCapturer,
            // Item 8: the reader backing `HidingVerification`'s own
            // internal Sampler is bounded too -- this is the one seam of
            // that frozen type this stage controls.
            readerFactory: { readerOrigin in TimedAXReader(wrapping: DiscoveredFrameReader(extras: LiveExtrasReader(), apps: LiveRunningApps(), origin: readerOrigin)) },
            geometry: { NSScreen.main.flatMap { BarGeometry(screen: $0) } },
            preflight: { [weak self] in
                guard let self, let screen = NSScreen.main, let geometry = BarGeometry(screen: screen) else {
                    return .unavailable(.captureUnavailable)
                }
                let reader = TimedAXReader(wrapping: DiscoveredFrameReader(extras: LiveExtrasReader(), apps: LiveRunningApps(), origin: liveOrigin))
                return Preflight.run(capturer: self.latchingCapturer, axReader: reader, geometry: geometry)
            }
        )
        let sectionMap: [TagKey: ItemSection] = [targetKey.tagKey(isSelf: false): .hidden]
        let firstPrepared = Pump.blocking { await self.verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [protectedKey], reusing: nil) }
        guard case .ready = firstPrepared.state else {
            evidence.record("step3.prepareFailed", ["state": "\(firstPrepared.state)"])
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
    /// `step2Launch`). The fold and untemplated owner items are not
    /// decided here -- they need a full bracketed AX+pixel read this
    /// decorator's bare `StripCapturing` seam does not carry (G-a, G-b);
    /// the stage feeds those separately through `latchingCapturer.feed(_:)`
    /// at the checkpoints in `StageC1Cycle.swift`.
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
        let ownerOnlyIDs = Set(ownerItemIDs.keys).subtracting([targetKey?.encoded, spacerKey?.encoded].compactMap { $0 })
        let missingOwners = ownerOnlyIDs.filter(missing).sorted()
        return Latch.Observation(missingOwnerItems: missingOwners, protectedMissing: missing(protectedKey.encoded))
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
            evidence.record("step3.untemplatedNoFrame", ["ids": missing])
            return .abort("step 3: an untemplated owner item (\(missing.joined(separator: ", "))) has no AX frame at baseline -- G-b fails closed")
        }
        untemplatedOwnerBaseline = untemplatedCandidates.map { UntemplatedOwnerWatch.Reading(id: $0.key.encoded, minX: $0.frame!.minX) }
        return .ok
    }

    /// The capture indicator: a `MenuBarAgent` frame in
    /// `StageRun.captureIndicatorWidthPt`, that is neither the chevron nor
    /// a privacy pill (the same rule `StageRun.readBar` uses).
    func detectIndicatorFrame() -> BarFrame? {
        let onBar = BarScan.items().filter { $0.minY >= 0 && $0.minY < geometry.heightPt && $0.bundleID == BarScan.menuBarAgentBundleID }
        let asFrame = { (item: BarItem) in AgentFrame(minX: item.minX, minY: item.minY, width: item.width) }
        let indicator = onBar.first {
            StageRun.captureIndicatorWidthPt.contains($0.width)
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
        guard let discovery = Pump.blocking({ await self.timedDiscoverer.discover(previous: nil) }) else {
            latchingCapturer.feed(.init(captureFailed: true))
            return Dictionary(uniqueKeysWithValues: untemplatedOwnerBaseline.map { ($0.id, Optional<UntemplatedOwnerWatch.Reading>.none) })
        }
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
