// Pieces both 2026-09-23 stages use: step 2 (launch the reference, then the
// target, and discover both), and the verification wiring of steps 5 and
// 6(b), where a stand-in takes the place of Ice's hidden divider.
import AppKit
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

/// Steps 5 and 6(b) are composition checks: there is no Ice in the harness,
/// so no hidden divider. The plan puts a stand-in at the section's rightmost
/// item's `maxX` (its `minX` is what `CheckPlan` reads) and reports the own
/// read as ok; everything else comes from the fresh discovery unchanged.
struct StandInDividerDiscoverer: Discovering {
    let base: MenuBarDiscoverer
    let sectionKeys: Set<ItemKey>

    func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? {
        guard let result = await base.discover(previous: previous) else { return nil }
        let set = result.set
        let frames = set.items.filter { sectionKeys.contains($0.key) }.compactMap(\.frame)
        let divider = frames.max(by: { $0.maxX < $1.maxX }).map { rightmost in
            DividerReading.make(frame: BarRect(minX: rightmost.maxX, minY: rightmost.minY, width: 1, height: rightmost.height), in: result.bounds)
        }
        let stoodIn = DiscoveredItemSet(
            items: set.items,
            visibleControlItem: nil,
            hiddenDivider: divider,
            alwaysHiddenDivider: nil,
            ownRead: .ok,
            systemElements: set.systemElements,
            dropped: set.dropped,
            staleProcesses: set.staleProcesses,
            completeness: set.completeness
        )
        return DiscoveryResult(set: stoodIn, duration: result.duration, origin: result.origin, bounds: result.bounds, nextCursor: result.nextCursor)
    }
}

extension StageRun {
    /// Section 6 step 2: reference, then target; both `.declared` and owned
    /// by the pids just launched. Their keys are fixed here, once.
    func step2LaunchReferenceAndTarget() -> StepResult {
        switch room(forItems: 2, step: "step2") {
        case .ok: break
        case .skip: return .abort("step 2 skipped for room, and every later step needs its helpers")
        case .abort(let reason): return .abort(reason)
        }
        guard let referenceHelper = launch(label: "reference", app: apps.reference, bundleID: HelperRole.reference,
                                           arguments: ["--items", "1", "--identifiers", "vz-reference", "--glyphs", "reference"])
        else { return .abort("could not launch the reference") }
        reference = referenceHelper
        guard let referenceItem = discoverDeclared(helper: referenceHelper, identifier: "vz-reference") else {
            return .abort("the reference was not discovered as one .declared item vz-reference of its pid")
        }
        referenceKey = referenceItem.key
        if case .abort(let reason) = barCheck("step2.reference") { return .abort(reason) }

        guard let targetHelper = launch(label: "target", app: apps.target, bundleID: HelperRole.target,
                                        arguments: ["--items", "1", "--identifiers", "vz-target", "--glyphs", "target"])
        else { return .abort("could not launch the target") }
        target = targetHelper
        guard let targetItem = discoverDeclared(helper: targetHelper, identifier: "vz-target") else {
            return .abort("the target was not discovered as one .declared item vz-target of its pid")
        }
        targetKey = targetItem.key

        evidence.record("step2.discovered", ["reference": describe(referenceItem), "target": describe(targetItem)])
        return safetyCheck("step2")
    }

    /// The one listed item of `helper`'s pid, if it is `.declared` with
    /// `identifier`.
    func discoverDeclared(helper: HelperControl, identifier: String) -> DiscoveredItem? {
        guard let found = discoverItems(of: helper.pid, count: 1) else { return nil }
        let item = found.items[0]
        guard item.basis == .declared, item.key.identifier == identifier, item.key.pid == helper.pid else {
            evidence.record("discovery.unexpected", ["helper": helper.role, "item": describe(item)])
            return nil
        }
        return item
    }

    /// `HidingVerification` over the live seams, with the stand-in divider
    /// after `sectionKeys`; the same seams as `HidingVerification.live`.
    func makeVerification(sectionKeys: [ItemKey]) -> HidingVerification {
        let capturer = self.capturer
        let origin = CGDisplayBounds(NSScreen.main?.directDisplayID ?? CGMainDisplayID()).origin
        let liveOrigin = DiscoveryOrigin(x: Double(origin.x), y: Double(origin.y))
        return HidingVerification(
            discoverer: StandInDividerDiscoverer(base: discoverer, sectionKeys: Set(sectionKeys)),
            capturer: capturer,
            readerFactory: { origin in
                DiscoveredFrameReader(extras: LiveExtrasReader(), apps: LiveRunningApps(), origin: origin)
            },
            geometry: {
                NSScreen.main.flatMap { BarGeometry(screen: $0) }
            },
            preflight: {
                guard let geometry = NSScreen.main.flatMap({ BarGeometry(screen: $0) }) else {
                    return .unavailable(.captureUnavailable)
                }
                let reader = DiscoveredFrameReader(extras: LiveExtrasReader(), apps: LiveRunningApps(), origin: liveOrigin)
                return Preflight.run(capturer: capturer, axReader: reader, geometry: geometry)
            }
        )
    }

    func describe(_ prepared: PreparedVerification) -> [String: Any] {
        var object: [String: Any] = [
            "targets": prepared.targets.map(\.encoded),
            "createdAt": prepared.createdAt,
        ]
        switch prepared.state {
        case .skip(let reason):
            object["state"] = "skip(\(reason))"
        case .ready(let ready):
            object["state"] = "ready"
            object["checkableTargets"] = ready.checkableTargets.map(\.encoded)
            object["alsoObserved"] = ready.alsoObserved.count
            object["references"] = ready.references.map(\.encoded)
            object["baselineRejections"] = Dictionary(uniqueKeysWithValues: ready.baselineRejections.map { ($0.key.encoded, "\($0.value)") })
            object["foldAtBaseline"] = "\(ready.baseline.foldAtBaseline)"
        }
        return object
    }

    /// Whether a section check came out as the plan expects, as one of the
    /// fold outcomes it pre-registers as recorded, or as neither. Only the
    /// hidden/gone halves pre-register `foldUnreadable`: for an item that
    /// should be drawn, an unreadable fold with no sighting is the anomaly.
    enum CheckOutcome {
        case expected
        case recorded
        case unexpected
    }

    func classify(_ check: SectionItemCheck?, expected: Hiding) -> CheckOutcome {
        if case .checked(let hiding)? = check, hiding == expected { return .expected }
        if expected == .hidden(folded: false), case .checked(.unverifiable(.foldUnreadable))? = check { return .recorded }
        return .unexpected
    }

    /// A prepare that produced no baseline. Plan Deviation 7: the plan's
    /// pre-registered `refusedAtBaseline(.foldNotAbsentAtBaseline)` cannot
    /// come out of `HidingVerification` -- that refusal is whole-baseline, so
    /// no reference is accepted and prepare reports `.skip(.noReference)`.
    /// The harness then takes its own baseline over the same ids: a fold
    /// that reads `.unreadable` is the recorded outcome; `.present` (a `«`)
    /// or `.absent` (the reference really was refused) stop the run.
    /// `.skip(.noRoom)` is section 6's room skip.
    enum PrepareFailure {
        case recorded(String)
        case skipped(String)
        case unexpected(String)
    }

    func explain(_ prepared: PreparedVerification, ids: [String: pid_t], referenceID: String, origin: DiscoveryOrigin, step: String) -> PrepareFailure {
        guard case .skip(let reason) = prepared.state else { return .unexpected("\(step): prepare was ready") }
        switch reason {
        case .noRoom:
            evidence.record("step.skipped", ["step": step, "reason": "RoomGuard: under 41 pt free right of the notch"])
            return .skipped("noRoom")
        case .noReference:
            let observer = VisibilityObserver(sampler: Sampler(capturer: capturer, axReader: feedReader(origin: origin)), parameters: parameters)
            let harness = baseline(observer: observer, items: ids)
            let fold = harness?.foldAtBaseline
            let referenceRefusal = harness?.rejections[referenceID]
            evidence.record("\(step).noReferenceFold", ["fold": fold.map { "\($0)" } ?? "no baseline", "reference": referenceRefusal.map { "\($0)" } ?? "accepted or absent"])
            // Only the baseline-level refusal is the pre-registered outcome; a
            // plan-level noReference (no candidate by geometry) is not.
            if fold == .unreadable, referenceRefusal == .foldNotAbsentAtBaseline { return .recorded("fold unreadable at baseline (pre-registered)") }
            return .unexpected("\(step): prepare skipped with noReference, harness fold \(fold.map { "\($0)" } ?? "none")")
        default:
            return .unexpected("\(step): prepare skipped: \(reason)")
        }
    }
}
