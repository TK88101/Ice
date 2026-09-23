import Foundation
import IceCore
import MenuBarCapture
import MenuBarDiscovery

/// Runs the detector's prepare/verify sessions around a fresh AX discovery
/// (plan section 4.3, D16, D19). The detector itself (`StripAssessor`,
/// `MenuBarItemVisibility`, everything in `MenuBarCapture`) is never touched
/// here -- this only decides *what* to feed it and *when*.
///
/// Every seam is injected; the live composition lives in `Self.live`, the one
/// place this type ever imports a real screen, a real capturer, or a real AX
/// walk. Everything -- the fresh discovery's blocking hand-off aside -- runs
/// on `queue`, a dedicated serial queue, never the main thread or the
/// cooperative pool (D19): the serial queue is also what gives "one session
/// at a time" for free, since a second `prepare`/`verify` call's blocking
/// work is simply queued behind the first's.
public final class HidingVerification: @unchecked Sendable {
    private let discoverer: any Discovering
    private let capturer: any StripCapturing
    private let readerFactory: @Sendable (DiscoveryOrigin) -> any MenuBarAXReading
    private let geometry: @Sendable () -> BarGeometry?
    private let preflight: @Sendable () -> PreflightResult
    private let sleep: @Sendable (Double) -> Void
    private let now: @Sendable () -> Double
    private let queue: DispatchQueue
    private let parameters: DetectorParameters
    private let warmUpCount: Int
    private let warmUpSpacing: Double
    private let retries: Int
    private let retrySpacing: Double

    private let generationLock = NSLock()
    private var generationCounter = 0

    public init(
        discoverer: any Discovering,
        capturer: any StripCapturing,
        readerFactory: @escaping @Sendable (DiscoveryOrigin) -> any MenuBarAXReading,
        geometry: @escaping @Sendable () -> BarGeometry?,
        preflight: @escaping @Sendable () -> PreflightResult,
        sleep: @escaping @Sendable (Double) -> Void = { Thread.sleep(forTimeInterval: $0) },
        now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
        queue: DispatchQueue = DispatchQueue(label: "com.icereverse.MenuBarDetectorFeed.HidingVerification"),
        parameters: DetectorParameters = .preRegistered,
        warmUpCount: Int = 24,
        warmUpSpacing: Double = 0.25,
        retries: Int = 5,
        retrySpacing: Double = 1.0
    ) {
        self.discoverer = discoverer
        self.capturer = capturer
        self.readerFactory = readerFactory
        self.geometry = geometry
        self.preflight = preflight
        self.sleep = sleep
        self.now = now
        self.queue = queue
        self.parameters = parameters
        self.warmUpCount = warmUpCount
        self.warmUpSpacing = warmUpSpacing
        self.retries = retries
        self.retrySpacing = retrySpacing
    }

    // MARK: - prepare

    public func prepare(
        sections: Set<ItemSection>,
        sectionMap: [TagKey: ItemSection],
        iceIconKey: ItemKey?,
        explicitCandidates: [ItemKey]?,
        reusing previous: PreparedVerification?
    ) async -> PreparedVerification {
        let flag = CancellationFlag()
        let generation = nextGeneration()

        return await withTaskCancellationHandler {
            guard !flag.isSet() else {
                return self.skipResult(.cancelled, targets: [], generation: generation)
            }
            guard let discovery = await self.discoverer.discover(previous: nil) else {
                // The discoverer also returns nil when there is no display.
                return self.skipResult(flag.isSet() || Task.isCancelled ? .cancelled : .noGeometry, targets: [], generation: generation)
            }
            guard !flag.isSet() else {
                return self.skipResult(.cancelled, targets: [], generation: generation)
            }

            return await withCheckedContinuation { (continuation: CheckedContinuation<PreparedVerification, Never>) in
                self.queue.async {
                    let result = self.runPrepareBody(
                        discovery: discovery,
                        sections: sections,
                        sectionMap: sectionMap,
                        iceIconKey: iceIconKey,
                        explicitCandidates: explicitCandidates,
                        previous: previous,
                        flag: flag,
                        generation: generation
                    )
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            flag.set()
        }
    }

    /// Runs entirely on `queue`. `discovery` is already fresh (`prepare`
    /// awaited it before hopping here); everything below is synchronous and
    /// may block (captures, `sleep`).
    private func runPrepareBody(
        discovery: DiscoveryResult,
        sections: Set<ItemSection>,
        sectionMap: [TagKey: ItemSection],
        iceIconKey: ItemKey?,
        explicitCandidates: [ItemKey]?,
        previous: PreparedVerification?,
        flag: CancellationFlag,
        generation: Int
    ) -> PreparedVerification {
        let set = discovery.set
        let origin = discovery.origin

        var itemsByKey = Dictionary(uniqueKeysWithValues: set.items.map { ($0.key, $0) })
        if let visible = set.visibleControlItem { itemsByKey[visible.key] = visible }

        func rosterTargets() -> [ItemKey] {
            set.items.filter { item in
                guard let section = sectionMap[item.tagKey] else { return false }
                return sections.contains(section)
            }.map(\.key)
        }

        guard !flag.isSet() else {
            return skipResult(.cancelled, targets: [], generation: generation)
        }

        guard let geometry = self.geometry() else {
            return skipResult(.noGeometry, targets: rosterTargets(), generation: generation)
        }

        let plan = CheckPlan.make(sections: sections, set: set, sectionMap: sectionMap, iceIconKey: iceIconKey, explicitCandidates: explicitCandidates)

        let targets: [ItemKey]
        let alsoObserved: [ItemKey]
        let referenceCandidates: [ItemKey]
        let planSkipped: [ItemKey: CheckSkipReason]
        switch plan {
        case .skip(let reason):
            return skipResult(reason, targets: rosterTargets(), generation: generation)
        case .observe(let t, let a, let r, let s):
            targets = t
            alsoObserved = a
            referenceCandidates = r
            planSkipped = s
        }

        let fullRoster = targets + Array(planSkipped.keys)

        guard !flag.isSet() else {
            return skipResult(.cancelled, targets: fullRoster, generation: generation)
        }

        guard RoomGuard.hasRoom(set: set, notchMaxX: geometry.notch?.hi ?? 0) else {
            return skipResult(.noRoom, targets: fullRoster, generation: generation)
        }

        let baselineKeys = targets + alsoObserved + referenceCandidates

        // D16 reuse: same capture geometry, the same roster (Deviation 5),
        // and exactly the previous baseline's items at essentially the same
        // fresh AX frames, within `BaselineReuse.maxAge` of when that
        // baseline was originally taken (never reset by a reuse --
        // `createdAt` is carried, not refreshed).
        if let previous, case .ready(let readyPrev) = previous.state, geometry == readyPrev.geometry,
           BaselineReuse.sameRoster(baselineTargets: readyPrev.checkableTargets, baselineSkipped: readyPrev.planSkipped, freshTargets: targets, freshSkipped: planSkipped) {
            let freshFrames = frames(for: baselineKeys, in: itemsByKey)
            let age = now() - previous.createdAt
            if BaselineReuse.isReusable(baselineFrames: readyPrev.baselineFrames, freshFrames: freshFrames, age: age) {
                return PreparedVerification(state: previous.state, targets: fullRoster, createdAt: previous.createdAt, generation: generation)
            }
        }

        guard !flag.isSet() else {
            return skipResult(.cancelled, targets: fullRoster, generation: generation)
        }

        switch preflight() {
        case .unavailable(let reason):
            return skipResult(.preflight(String(describing: reason)), targets: fullRoster, generation: generation)
        case .ready:
            break
        }

        let cancelCapturer = CancellableCapturer(wrapping: capturer, flag: flag)
        let cancelReader = CancellableReader(wrapping: readerFactory(origin), flag: flag)

        for _ in 0..<warmUpCount {
            guard !flag.isSet() else { return skipResult(.cancelled, targets: fullRoster, generation: generation) }
            _ = cancelCapturer.capture()
            sleep(warmUpSpacing)
        }

        let observer = VisibilityObserver(
            sampler: Sampler(capturer: cancelCapturer, axReader: cancelReader, now: now),
            parameters: parameters,
            sleep: sleep
        )
        let baselineItems = DiscoveredTargets.items(baselineKeys)

        var lastBaseline: BaselineResult?
        for attempt in 0..<retries {
            guard !flag.isSet() else { return skipResult(.cancelled, targets: fullRoster, generation: generation) }
            if let result = observer.baseline(items: baselineItems, geometry: geometry) {
                lastBaseline = result
                if result.foldAtBaseline == .absent { break }
            }
            if attempt < retries - 1 { sleep(retrySpacing) }
        }

        guard !flag.isSet() else {
            return skipResult(.cancelled, targets: fullRoster, generation: generation)
        }

        guard let baseline = lastBaseline else {
            return skipResult(.captureFailed, targets: fullRoster, generation: generation)
        }

        let acceptedKeys = Set(baseline.templates.keys.compactMap(ItemKey.decode))
        let references = CheckPlan.references(candidates: referenceCandidates, accepted: acceptedKeys)
        guard !references.isEmpty else {
            return skipResult(.noReference, targets: fullRoster, generation: generation)
        }

        // D15: an observed item the baseline marked dynamic is dropped, so
        // one animated item cannot make every target read unsettled.
        let keptAlsoObserved = alsoObserved.filter { key in
            guard let template = baseline.templates[key.encoded] else { return true }
            return !template.isDynamic
        }

        var baselineRejections = [ItemKey: Rejection]()
        for key in targets {
            if let rejection = baseline.rejections[key.encoded] {
                baselineRejections[key] = rejection
            }
        }

        let baselineFrames = frames(for: baselineKeys, in: itemsByKey)

        let ready = PreparedVerification.Ready(
            baseline: baseline,
            geometry: geometry,
            origin: origin,
            checkableTargets: targets,
            alsoObserved: keptAlsoObserved,
            references: references,
            planSkipped: planSkipped,
            baselineRejections: baselineRejections,
            baselineFrames: baselineFrames
        )
        return PreparedVerification(state: .ready(ready), targets: fullRoster, createdAt: now(), generation: generation)
    }

    // MARK: - verify

    public func verify(_ prepared: PreparedVerification) async -> [ItemKey: SectionItemCheck] {
        let flag = CancellationFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[ItemKey: SectionItemCheck], Never>) in
                self.queue.async {
                    let result = self.runVerifyBody(prepared, flag: flag)
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            flag.set()
        }
    }

    private func runVerifyBody(_ prepared: PreparedVerification, flag: CancellationFlag) -> [ItemKey: SectionItemCheck] {
        func allSkipped(_ reason: CheckSkipReason) -> [ItemKey: SectionItemCheck] {
            Dictionary(uniqueKeysWithValues: prepared.targets.map { ($0, .skipped(reason)) })
        }

        guard case .ready(let ready) = prepared.state else {
            if case .skip(let reason) = prepared.state {
                return allSkipped(reason)
            }
            return allSkipped(.cancelled)
        }

        let age = now() - prepared.createdAt
        guard age <= BaselineReuse.maxAge else {
            return allSkipped(.baselineStale)
        }

        guard !flag.isSet() else {
            return allSkipped(.cancelled)
        }

        let observedTargets = ready.checkableTargets.filter { ready.baselineRejections[$0] == nil }
        let observeKeys = observedTargets + ready.alsoObserved
        let referenceKeys = ready.references

        let cancelCapturer = CancellableCapturer(wrapping: capturer, flag: flag)
        let cancelReader = CancellableReader(wrapping: readerFactory(ready.origin), flag: flag)

        for _ in 0..<warmUpCount {
            guard !flag.isSet() else { return allSkipped(.cancelled) }
            _ = cancelCapturer.capture()
            sleep(warmUpSpacing)
        }

        let observer = VisibilityObserver(
            sampler: Sampler(capturer: cancelCapturer, axReader: cancelReader, now: now),
            parameters: parameters,
            sleep: sleep
        )
        let observeItems = DiscoveredTargets.items(observeKeys + referenceKeys)

        var lastResult: ObservationResult?
        for attempt in 0..<retries {
            guard !flag.isSet() else { return allSkipped(.cancelled) }
            if let result = observer.observe(baseline: ready.baseline, targets: observeKeys.map(\.encoded), references: referenceKeys.map(\.encoded), items: observeItems) {
                lastResult = result
                if result.reading.fold != .unreadable { break }
            }
            if attempt < retries - 1 { sleep(retrySpacing) }
        }

        guard !flag.isSet() else {
            return allSkipped(.cancelled)
        }

        guard let reading = lastResult?.reading else {
            return allSkipped(.captureFailed)
        }

        let decision = MenuBarItemVisibility(maxMismatch: parameters.maxMismatch)
        var results = [ItemKey: SectionItemCheck]()
        for (key, reason) in ready.planSkipped {
            results[key] = .skipped(reason)
        }
        for key in ready.checkableTargets {
            if let rejection = ready.baselineRejections[key] {
                results[key] = .refusedAtBaseline(rejection)
            } else {
                results[key] = .checked(decision.hiding(of: key.encoded, in: reading))
            }
        }
        return results
    }

    // MARK: - Helpers

    private func nextGeneration() -> Int {
        generationLock.withLock {
            generationCounter += 1
            return generationCounter
        }
    }

    private func skipResult(_ reason: CheckSkipReason, targets: [ItemKey], generation: Int) -> PreparedVerification {
        PreparedVerification(state: .skip(reason), targets: targets, createdAt: now(), generation: generation)
    }

    private func frames(for keys: [ItemKey], in itemsByKey: [ItemKey: DiscoveredItem]) -> [ItemKey: BarRect] {
        var result = [ItemKey: BarRect]()
        for key in keys {
            if let frame = itemsByKey[key]?.frame { result[key] = frame }
        }
        return result
    }

}
