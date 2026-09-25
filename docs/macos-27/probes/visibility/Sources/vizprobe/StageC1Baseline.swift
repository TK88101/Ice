// I5 step 3: section 2's "Baseline, taken once with the spacer at rest,"
// the `HidingVerification`/`C1Discoverer` composition that produces
// Target's `Hiding` verdicts, and the roster snapshot / latch this
// baseline seeds for section 3 and section 4.
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

        let reader = LiveMenuBarAXReader(origin: CGPoint(x: origin.x, y: origin.y))
        let sampler = Sampler(capturer: capturer, axReader: reader)
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

        // The C1Discoverer-backed verification: Target the only section
        // item, Protected the explicit reference, the divider at the
        // spacer's own minX (I4).
        let liveOrigin = origin
        verification = HidingVerification(
            discoverer: C1Discoverer(base: discoverer, targetKey: targetKey, spacerKey: spacerKey, protectedKey: protectedKey),
            capturer: capturer,
            readerFactory: { readerOrigin in DiscoveredFrameReader(extras: LiveExtrasReader(), apps: LiveRunningApps(), origin: readerOrigin) },
            geometry: { NSScreen.main.flatMap { BarGeometry(screen: $0) } },
            preflight: { [weak self] in
                guard let self, let screen = NSScreen.main, let geometry = BarGeometry(screen: screen) else {
                    return .unavailable(.captureUnavailable)
                }
                let reader = DiscoveredFrameReader(extras: LiveExtrasReader(), apps: LiveRunningApps(), origin: liveOrigin)
                return Preflight.run(capturer: self.capturer, axReader: reader, geometry: geometry)
            }
        )
        let sectionMap: [TagKey: ItemSection] = [targetKey.tagKey(isSelf: false): .hidden]
        let firstPrepared = Pump.blocking { await self.verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [protectedKey], reusing: nil) }
        guard case .ready = firstPrepared.state else {
            evidence.record("step3.prepareFailed", ["state": "\(firstPrepared.state)"])
            return .abort("step 3: Target/Protected composition was not accepted by the C1 discoverer")
        }
        prepared = firstPrepared

        // Section 4's latch: assessed from `ownerBaseline`'s templates,
        // Target and the spacer excluded (owner items and Protected only).
        let ownerOnlyTemplateIDs = Set(ids.keys).subtracting([targetKey.encoded, spacerKey.encoded])
        latchingCapturer = LatchingCapturer(base: capturer, channel: channel) { [weak self] image in
            self?.assessLatch(image: image, ownerOnlyIDs: ownerOnlyTemplateIDs, protectedID: protectedKey.encoded) ?? .init(captureFailed: true)
        }

        // Section 3's roster snapshot and section 5's baseline-equivalence
        // readings, both seeded "at the end of the baseline" (first
        // preflight has none to compare against otherwise).
        seedBaselineReadings(baseline: ownerBaseline, targetID: targetKey.encoded, spacerID: spacerKey.encoded, protectedID: protectedKey.encoded)
        preflightEverPassed = false
        return .ok
    }

    /// I3's `assess`: which owner ids (Target/spacer excluded) and which
    /// Protected id are missing from this capture, by the same
    /// unique-match-within-tolerance rule `SafetyMonitor.feed` uses.
    /// Residual-strip ink change and the fold are not decided here -- they
    /// need a paired AX read this decorator's `StripCapturing` seam does
    /// not carry, so the stage feeds them separately through
    /// `latchingCapturer.feed(_:)` at the points it already takes one
    /// (`Latch.Observation.residualInkChanged` is therefore never set from
    /// this path; see the worker report's "not implemented as specified").
    func assessLatch(image: StripImage, ownerOnlyIDs: Set<String>, protectedID: String) -> Latch.Observation {
        guard let ink = ownerBaseline.ink else { return .init(captureFailed: true) }
        let map = ink.map(image)
        func missing(_ id: String) -> Bool {
            guard let template = ownerBaseline.templates[id] else { return false }
            guard case .unique(let x, let mismatch) = TemplateMatcher.match(template, in: map, geometry: geometry, parameters: parameters),
                  mismatch <= parameters.maxMismatch,
                  abs(x - template.originXPt) <= parameters.referenceTolerancePt
            else { return true }
            return false
        }
        let missingOwners = ownerOnlyIDs.filter(missing).sorted()
        return Latch.Observation(missingOwnerItems: missingOwners, protectedMissing: missing(protectedID))
    }

    /// Section 3's roster snapshot and section 5's baseline-equivalence
    /// readings, taken from a baseline-equivalent reading (here, the rest
    /// baseline itself).
    func seedBaselineReadings(baseline: BaselineResult, targetID: String, spacerID: String, protectedID: String) {
        let sortedIDs = baseline.acceptedIDs
        let indicator = detectIndicatorFrame()
        rosterSnapshot = RosterSnapshot(items: sortedIDs, indicatorFrame: indicator)
        baselineIndicatorFrame = indicator
        ownerBaselineReadings = sortedIDs
            .filter { $0 != targetID && $0 != spacerID && $0 != protectedID }
            .compactMap { id in baseline.templates[id].map { .init(id: id, x: $0.originXPt) } }
        helperBaselineReadings = [targetID, spacerID, protectedID].compactMap { id in
            baseline.templates[id].map { .init(id: id, x: $0.originXPt) }
        }
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
}
