import Darwin
import Foundation
import Testing
import IceCore
import MenuBarCapture
import MenuBarDiscovery
@testable import MenuBarDetectorFeed

/// `HidingVerification` runs the detector's prepare/verify sessions around a
/// fresh AX discovery (plan section 4.3, T7). Every test here drives it
/// through fake discovery/capture/AX seams -- no real sleep, screen, or
/// Accessibility -- over a small synthetic bar (`TestBar`).
///
/// Shared geometry used throughout: `t1` (raw AX frame [59,68], 2 pt raw
/// overlap with `t2`'s [66,75] -- D15's measured overlap, cancelled by
/// `CheckFrames.trim`), `t2` ([66,75]), a reference `ref` ([150,159]). Their
/// capture-level (already-trimmed, detector-facing) frames sit at 60, 70 and
/// 150 pt respectively -- `TestBar.frame(atPt:)`'s own convention.
@Suite("HidingVerification")
struct HidingVerificationTests {
    // MARK: - Shared fixtures

    static func basicItems() -> (t1: DiscoveredItem, t2: DiscoveredItem, ref: DiscoveredItem) {
        (
            Scenario.discoveredItem(identifier: "t1", pid: 601, rawMinX: 59, rawWidth: 9),
            Scenario.discoveredItem(identifier: "t2", pid: 602, rawMinX: 66, rawWidth: 9),
            Scenario.discoveredItem(identifier: "ref", pid: 603, rawMinX: 150, rawWidth: 9)
        )
    }

    static func drawnImage() -> StripImage {
        Scenario.image([(TestBar.shapeA, 60), (TestBar.shapeC, 70), (TestBar.shapeB, 150)])
    }

    static func drawnSnapshot(t1: ItemKey, t2: ItemKey, ref: ItemKey, agentMinX: Double = 200) -> MenuBarAXSnapshot {
        Scenario.snapshot([(t1.encoded, 60), (t2.encoded, 70), (ref.encoded, 150)], agentMinX: agentMinX)
    }

    // MARK: - 2. Two adjacent targets: hidden / still drawn

    @Test("two adjacent inked targets with a 2pt raw overlap, both hidden -> both .hidden(folded: false)")
    func bothHiddenReadsHiddenNotFolded() async {
        let (t1, t2, ref) = Self.basicItems()
        let sectionMap = Scenario.sectionMap([t1, t2])

        let drawn = Self.drawnImage()
        let drawnSnap = Self.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)
        let hidden = Scenario.image([(TestBar.shapeB, 150)])
        let hiddenSnap = Scenario.snapshot([(ref.key.encoded, 150)])

        let captures = Scenario.repeated(drawn, count: Scenario.baselineCaptureCount()) + Scenario.repeated(hidden, count: Scenario.observeCaptureCount())
        let reads = Scenario.repeated(drawnSnap, count: Scenario.baselineReadCount()) + Scenario.repeated(hiddenSnap, count: Scenario.observeReadCount())

        let (verification, _, _, _, _) = Scenario.makeVerification(
            discoveryResults: [Scenario.discovery([t1, t2, ref])],
            capturerResults: captures,
            axResults: reads
        )

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref.key], reusing: nil)
        guard case .ready = prepared.state else { Issue.record("expected .ready, got \(prepared.state)"); return }

        let results = await verification.verify(prepared)

        #expect(results[t1.key] == .checked(.hidden(folded: false)))
        #expect(results[t2.key] == .checked(.hidden(folded: false)))
    }

    @Test("two adjacent inked targets, nothing changes -> both .stillDrawn")
    func bothStillDrawnWhenUnchanged() async {
        let (t1, t2, ref) = Self.basicItems()
        let sectionMap = Scenario.sectionMap([t1, t2])

        let drawn = Self.drawnImage()
        let drawnSnap = Self.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)

        let captures = Scenario.repeated(drawn, count: Scenario.baselineCaptureCount() + Scenario.observeCaptureCount())
        let reads = Scenario.repeated(drawnSnap, count: Scenario.baselineReadCount() + Scenario.observeReadCount())

        let (verification, _, _, _, _) = Scenario.makeVerification(
            discoveryResults: [Scenario.discovery([t1, t2, ref])],
            capturerResults: captures,
            axResults: reads
        )

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref.key], reusing: nil)
        guard case .ready = prepared.state else { Issue.record("expected .ready, got \(prepared.state)"); return }

        let results = await verification.verify(prepared)

        #expect(results[t1.key] == .checked(.stillDrawn))
        #expect(results[t2.key] == .checked(.stillDrawn))
    }

    // MARK: - 3. Reference fallback / none accepted

    @Test("a candidate rejected at baseline (too narrow) falls back to the second, accepted candidate")
    func rejectedCandidateFallsBackToSecond() async {
        let (t1, t2, ref2) = Self.basicItems()
        let ref1 = Scenario.discoveredItem(identifier: "ref1", pid: 604, rawMinX: 95, rawWidth: 9)
        let sectionMap = Scenario.sectionMap([t1, t2])

        // ref1's capture-level frame is deliberately narrower than
        // `DetectorParameters.minTemplateWidthPt` (4pt) -> `.tooNarrow`,
        // independent of any other item.
        let drawn = Scenario.image([(TestBar.shapeA, 60), (TestBar.shapeC, 70), (TestBar.shapeB, 150)])
        let drawnSnap = Scenario.snapshot(explicit: [
            t1.key.encoded: TestBar.frame(id: t1.key.encoded, atPt: 60),
            t2.key.encoded: TestBar.frame(id: t2.key.encoded, atPt: 70),
            ref1.key.encoded: ItemFrame(id: ref1.key.encoded, minX: 99, minY: 0, width: 2, height: Double(TestBar.heightPt)),
            ref2.key.encoded: TestBar.frame(id: ref2.key.encoded, atPt: 150),
        ])

        let captures = Scenario.repeated(drawn, count: Scenario.baselineCaptureCount())
        let reads = Scenario.repeated(drawnSnap, count: Scenario.baselineReadCount())

        let (verification, _, _, _, _) = Scenario.makeVerification(
            discoveryResults: [Scenario.discovery([t1, t2, ref1, ref2])],
            capturerResults: captures,
            axResults: reads
        )

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref1.key, ref2.key], reusing: nil)

        guard case .ready(let ready) = prepared.state else { Issue.record("expected .ready, got \(prepared.state)"); return }
        #expect(ready.references == [ref2.key])
    }

    @Test("every candidate rejected at baseline -> .skip(.noReference)")
    func everyCandidateRejectedSkipsNoReference() async {
        let (t1, t2, _) = Self.basicItems()
        let ref1 = Scenario.discoveredItem(identifier: "ref1", pid: 604, rawMinX: 95, rawWidth: 9)
        let ref2 = Scenario.discoveredItem(identifier: "ref2", pid: 605, rawMinX: 150, rawWidth: 9)
        let sectionMap = Scenario.sectionMap([t1, t2])

        let drawn = Scenario.image([(TestBar.shapeA, 60), (TestBar.shapeC, 70)])
        let drawnSnap = Scenario.snapshot(explicit: [
            t1.key.encoded: TestBar.frame(id: t1.key.encoded, atPt: 60),
            t2.key.encoded: TestBar.frame(id: t2.key.encoded, atPt: 70),
            ref1.key.encoded: ItemFrame(id: ref1.key.encoded, minX: 99, minY: 0, width: 2, height: Double(TestBar.heightPt)),
            ref2.key.encoded: ItemFrame(id: ref2.key.encoded, minX: 154, minY: 0, width: 2, height: Double(TestBar.heightPt)),
        ])

        let captures = Scenario.repeated(drawn, count: Scenario.baselineCaptureCount())
        let reads = Scenario.repeated(drawnSnap, count: Scenario.baselineReadCount())

        let (verification, _, _, _, _) = Scenario.makeVerification(
            discoveryResults: [Scenario.discovery([t1, t2, ref1, ref2])],
            capturerResults: captures,
            axResults: reads
        )

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref1.key, ref2.key], reusing: nil)

        #expect(prepared.state == .skip(.noReference))
    }

    // MARK: - 4-7, 11: verify()-focused (a hand-built `Ready` around a real `StripAssessor.baseline`)

    /// A real, clean `BaselineResult` for `t1`/`t2`/`ref` -- fold absent,
    /// every template accepted -- built directly through `StripAssessor`
    /// rather than through `HidingVerification.prepare`, so these tests can
    /// focus purely on `verify`'s own logic (D17's mapping, the frozen
    /// detector's placement/fold rules) without re-deriving the exact
    /// baseline-retry contract each time.
    static func cleanBaseline(t1: ItemKey, t2: ItemKey, ref: ItemKey, agentMinX: Double = 200) -> BaselineResult {
        let image = Self.drawnImage()
        let snapshot = Self.drawnSnapshot(t1: t1, t2: t2, ref: ref, agentMinX: agentMinX)
        let samples = (0..<4).map { i in
            ObservationSample(time: Double(i), before: image, after: image, agentFrames: snapshot.agentFrames, itemFrames: snapshot.itemFrames)
        }
        return StripAssessor.baseline(samples: samples, geometry: TestBar.geometry, parameters: .preRegistered)
    }

    static func readyPreparedVerification(
        baseline: BaselineResult,
        checkableTargets: [ItemKey],
        alsoObserved: [ItemKey] = [],
        references: [ItemKey],
        planSkipped: [ItemKey: CheckSkipReason] = [:],
        baselineRejections: [ItemKey: Rejection] = [:]
    ) -> PreparedVerification {
        let ready = PreparedVerification.Ready(
            baseline: baseline,
            geometry: TestBar.geometry,
            origin: DiscoveryOrigin(x: 0, y: 0),
            checkableTargets: checkableTargets,
            alsoObserved: alsoObserved,
            references: references,
            planSkipped: planSkipped,
            baselineRejections: baselineRejections,
            baselineFrames: [:]
        )
        let roster = checkableTargets + Array(planSkipped.keys)
        return PreparedVerification(state: .ready(ready), targets: roster, createdAt: 0, generation: 1)
    }

    @Test("a target refused at baseline (.foldNotAbsentAtBaseline) reads .refusedAtBaseline, never .notObserved")
    func refusedAtBaselineIsReportedNotNotObserved() async {
        let (t1, t2, ref) = Self.basicItems()
        let baseline = Self.cleanBaseline(t1: t1.key, t2: t2.key, ref: ref.key)
        let prepared = Self.readyPreparedVerification(
            baseline: baseline, checkableTargets: [t1.key, t2.key], references: [ref.key],
            baselineRejections: [t1.key: .foldNotAbsentAtBaseline]
        )

        let drawn = Self.drawnImage()
        let drawnSnap = Self.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)
        let (verification, _, _, _, _) = Scenario.makeVerification(
            discoveryResults: [],
            capturerResults: Scenario.repeated(drawn, count: Scenario.observeCaptureCount()),
            axResults: Scenario.repeated(drawnSnap, count: Scenario.observeReadCount())
        )

        let results = await verification.verify(prepared)

        #expect(results[t1.key] == .refusedAtBaseline(.foldNotAbsentAtBaseline))
        if case .checked(.unverifiable(.notObserved)) = results[t1.key] {
            Issue.record("must not collapse into notObserved")
        }
    }

    @Test("inked, non-observed ink left of the reference makes a genuinely hidden target read .foldUnreadable, not .hidden")
    func unobservedInkBlocksHiddenVerdict() async {
        let (t1, _, ref) = Self.basicItems()
        // A baseline with only t1 + ref (a "ghost" item must not be part of
        // `wanted` at observe time, so it is never part of the baseline
        // either).
        let cleanImage = Scenario.image([(TestBar.shapeA, 60), (TestBar.shapeB, 150)])
        let cleanSnapshot = Scenario.snapshot([(t1.key.encoded, 60), (ref.key.encoded, 150)])
        let samples = (0..<4).map { i in
            ObservationSample(time: Double(i), before: cleanImage, after: cleanImage, agentFrames: cleanSnapshot.agentFrames, itemFrames: cleanSnapshot.itemFrames)
        }
        let realBaseline = StripAssessor.baseline(samples: samples, geometry: TestBar.geometry, parameters: .preRegistered)
        #expect(realBaseline.foldAtBaseline == .absent)

        let prepared = Self.readyPreparedVerification(baseline: realBaseline, checkableTargets: [t1.key], references: [ref.key])

        // t1 is gone (frame and ink both); an unrelated "ghost" glyph, never
        // requested by any id, is drawn left of the reference.
        // Distinct from t1's own shape (shapeA), so the matcher cannot
        // confuse the ghost's ink for a moved sighting of t1 itself -- the
        // point is that its ink is unexplained, not that it fools the match.
        let observeImage = Scenario.image([(TestBar.shapeC, 100), (TestBar.shapeB, 150)])
        let observeSnapshot = Scenario.snapshot([(ref.key.encoded, 150)])

        let (verification, _, _, _, _) = Scenario.makeVerification(
            discoveryResults: [],
            capturerResults: Scenario.repeated(observeImage, count: Scenario.observeCaptureCount()),
            axResults: Scenario.repeated(observeSnapshot, count: Scenario.observeReadCount())
        )

        let results = await verification.verify(prepared)

        #expect(results[t1.key] == .checked(.unverifiable(.foldUnreadable)))
    }

    @Test("a target moved 32pt, with its AX frame moving too, still reads .stillDrawn")
    func movedTargetStillReadsDrawn() async {
        let (t1, t2, ref) = Self.basicItems()
        let baseline = Self.cleanBaseline(t1: t1.key, t2: t2.key, ref: ref.key)
        let prepared = Self.readyPreparedVerification(baseline: baseline, checkableTargets: [t1.key], references: [ref.key])

        let movedImage = Scenario.image([(TestBar.shapeA, 92), (TestBar.shapeB, 150)])
        let movedSnapshot = Scenario.snapshot([(t1.key.encoded, 92), (ref.key.encoded, 150)])

        let (verification, _, _, _, _) = Scenario.makeVerification(
            discoveryResults: [],
            capturerResults: Scenario.repeated(movedImage, count: Scenario.observeCaptureCount()),
            axResults: Scenario.repeated(movedSnapshot, count: Scenario.observeReadCount())
        )

        let results = await verification.verify(prepared)

        #expect(results[t1.key] == .checked(.stillDrawn))
        _ = t2
    }

    @Test("an agent frame that moved between baseline and observation keeps .stillDrawn for a drawn target, and reads .foldUnreadable for a hidden one")
    func movedAgentFrameAffectsOnlyTheFoldDependentVerdict() async {
        let (t1, t2, ref) = Self.basicItems()
        let baseline = Self.cleanBaseline(t1: t1.key, t2: t2.key, ref: ref.key, agentMinX: 200)
        let prepared = Self.readyPreparedVerification(baseline: baseline, checkableTargets: [t1.key, t2.key], references: [ref.key])

        // t1 stays drawn; t2 is genuinely hidden; the agent's own frame moved
        // by 10pt (past `agentXTolerancePt`).
        let observeImage = Scenario.image([(TestBar.shapeA, 60), (TestBar.shapeB, 150)])
        let observeSnapshot = Scenario.snapshot([(t1.key.encoded, 60), (ref.key.encoded, 150)], agentMinX: 210)

        let (verification, _, _, _, _) = Scenario.makeVerification(
            discoveryResults: [],
            capturerResults: Scenario.repeated(observeImage, count: Scenario.observeCaptureCount()),
            axResults: Scenario.repeated(observeSnapshot, count: Scenario.observeReadCount())
        )

        let results = await verification.verify(prepared)

        #expect(results[t1.key] == .checked(.stillDrawn))
        #expect(results[t2.key] == .checked(.unverifiable(.foldUnreadable)))
    }

    // MARK: - 8. Baseline retries

    @Test("baseline retries while the fold reads unreadable, then absent -> prepared, exactly the scripted number of attempts consumed")
    func baselineRetriesUntilFoldReadable() async {
        let (t1, t2, ref) = Self.basicItems()
        let sectionMap = Scenario.sectionMap([t1, t2])

        let drawn = Self.drawnImage()
        let unreadableSnap = MenuBarAXSnapshot(
            itemFrames: Self.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key).itemFrames,
            agentFrames: [] // no agent frames at all -> FoldWitness.verdict returns .unreadable
        )
        let readableSnap = Self.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)

        let captures = Scenario.repeated(drawn, count: Scenario.baselineCaptureCount() * 3)
        let reads = Scenario.repeated(unreadableSnap, count: Scenario.baselineReadCount() * 2) + Scenario.repeated(readableSnap, count: Scenario.baselineReadCount())

        let (verification, _, capturer, ax, _) = Scenario.makeVerification(
            discoveryResults: [Scenario.discovery([t1, t2, ref])],
            capturerResults: captures,
            axResults: reads,
            retries: 5
        )

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref.key], reusing: nil)

        guard case .ready = prepared.state else { Issue.record("expected .ready after the fold became readable, got \(prepared.state)"); return }
        #expect(capturer.callCount == Scenario.baselineCaptureCount() * 3, "exactly 3 attempts' worth of captures")
        #expect(ax.callCount == Scenario.baselineReadCount() * 3, "exactly 3 attempts' worth of reads")
    }

    // MARK: - 9. Reuse

    @Test("a reused baseline captures nothing when frames and geometry match; a changed geometry recaptures")
    func reuseAvoidsRecaptureUntilGeometryChanges() async {
        let (t1, t2, ref) = Self.basicItems()
        let sectionMap = Scenario.sectionMap([t1, t2])

        let drawn = Self.drawnImage()
        let drawnSnap = Self.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)

        let discoverer = FakeDiscoverer(results: [
            Scenario.discovery([t1, t2, ref]),
            Scenario.discovery([t1, t2, ref]),
            Scenario.discovery([t1, t2, ref]),
        ])
        let capturer = FakeStripCapturer(results: Scenario.repeated(drawn, count: Scenario.baselineCaptureCount() * 2))
        let ax = FakeMenuBarAXReader(results: Scenario.repeated(drawnSnap, count: Scenario.baselineReadCount() * 2))
        let clock = FakeClock(step: 1.0)
        let geometryBox = Box<BarGeometry>(TestBar.geometry)
        let verification = HidingVerification(
            discoverer: discoverer,
            capturer: capturer,
            readerFactory: { _ in ax },
            geometry: { geometryBox.get() },
            preflight: { .ready(geometry: geometryBox.get()) },
            sleep: { _ in },
            now: clock.now,
            queue: DispatchQueue(label: "test.reuse.\(UUID().uuidString)"),
            parameters: .preRegistered,
            warmUpCount: 0,
            retries: 5
        )

        let first = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref.key], reusing: nil)
        guard case .ready = first.state else { Issue.record("expected .ready, got \(first.state)"); return }
        let afterFirst = capturer.callCount
        #expect(afterFirst == Scenario.baselineCaptureCount())

        // Same geometry, same fresh frames (a fresh discovery with identical
        // items) -> reused, no capture.
        let second = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref.key], reusing: first)
        guard case .ready = second.state else { Issue.record("expected .ready (reused), got \(second.state)"); return }
        #expect(capturer.callCount == afterFirst, "no capture should happen on a reusable baseline")
        #expect(second.createdAt == first.createdAt, "reuse must not reset the baseline's original creation time")

        // Now the geometry changes -> not reusable -> recaptured. Only
        // `widthPt` changes (not `scale`): the fixture's images are rendered
        // at a fixed pixel scale, so changing the declared `scale` here would
        // desync the geometry from the actual pixels and break template
        // cutting for an unrelated reason -- `widthPt` alone is enough to
        // make `BarGeometry` unequal (D16's reuse rule) without touching
        // pixel math.
        geometryBox.set(BarGeometry(widthPt: TestBar.geometry.widthPt + 1, heightPt: TestBar.geometry.heightPt, scale: TestBar.geometry.scale, notch: nil))
        let third = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref.key], reusing: second)
        guard case .ready = third.state else { Issue.record("expected .ready after recapture, got \(third.state)"); return }
        #expect(capturer.callCount == afterFirst + Scenario.baselineCaptureCount(), "a changed geometry must recapture")
    }

    // MARK: - 10. Cancellation, main-thread, serialization

    @Test("cancellation stops captures within one sample, and the cancelled result is .skip(.cancelled), never a verdict")
    func cancellationStopsWithinOneSample() async {
        let (t1, t2, ref) = Self.basicItems()
        let sectionMap = Scenario.sectionMap([t1, t2])
        let drawn = Self.drawnImage()
        let drawnSnap = Self.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)

        let reachedCheckpoint = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let capturer = FakeStripCapturer(results: Scenario.repeated(drawn, count: Scenario.baselineCaptureCount()), onCall: { index in
            if index == 3 {
                reachedCheckpoint.signal()
                release.wait()
            }
        })
        let ax = FakeMenuBarAXReader(results: Scenario.repeated(drawnSnap, count: Scenario.baselineReadCount()))
        let discoverer = FakeDiscoverer(results: [Scenario.discovery([t1, t2, ref])])
        let clock = FakeClock(step: 1.0)
        let verification = HidingVerification(
            discoverer: discoverer,
            capturer: capturer,
            readerFactory: { _ in ax },
            geometry: { TestBar.geometry },
            preflight: { .ready(geometry: TestBar.geometry) },
            sleep: { _ in },
            now: clock.now,
            queue: DispatchQueue(label: "test.cancel.\(UUID().uuidString)"),
            parameters: .preRegistered,
            warmUpCount: 0,
            retries: 5
        )

        let task = Task {
            await verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref.key], reusing: nil)
        }

        blockingWait(reachedCheckpoint)
        task.cancel()
        release.signal()

        let result = await task.value

        #expect(result.state == .skip(.cancelled))
        #expect(capturer.callCount == 3, "only the captures already in flight before cancellation should have been delegated")
        #expect(ax.callCount == 1, "the read of the sample cancellation landed inside should never reach the fake")
    }

    @Test("HidingVerification never runs a session on the main thread", .tags(.mainThread))
    @MainActor
    func neverRunsOnMainThread() async {
        let (t1, t2, ref) = Self.basicItems()
        let sectionMap = Scenario.sectionMap([t1, t2])
        let drawn = Self.drawnImage()
        let drawnSnap = Self.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)

        let captures = Scenario.repeated(drawn, count: Scenario.baselineCaptureCount() + Scenario.observeCaptureCount())
        let reads = Scenario.repeated(drawnSnap, count: Scenario.baselineReadCount() + Scenario.observeReadCount())

        let (verification, _, capturer, ax, _) = Scenario.makeVerification(
            discoveryResults: [Scenario.discovery([t1, t2, ref])],
            capturerResults: captures,
            axResults: reads
        )

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref.key], reusing: nil)
        _ = await verification.verify(prepared)

        #expect(!capturer.mainThreadCalls.isEmpty)
        #expect(capturer.mainThreadCalls.allSatisfy { $0 == false })
        #expect(!ax.mainThreadCalls.isEmpty)
        #expect(ax.mainThreadCalls.allSatisfy { $0 == false })
    }

    @Test("one session at a time: two concurrent prepares never capture concurrently")
    func oneSessionAtATimeIsSerialized() async {
        let (t1, t2, ref) = Self.basicItems()
        let sectionMap = Scenario.sectionMap([t1, t2])
        let drawn = Self.drawnImage()
        let drawnSnap = Self.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)

        let tracker = ConcurrencyTracker()
        let discoverer = FakeDiscoverer(results: [Scenario.discovery([t1, t2, ref]), Scenario.discovery([t1, t2, ref])])
        let capturer = FakeStripCapturer(results: Scenario.repeated(drawn, count: Scenario.baselineCaptureCount() * 2), tracker: tracker)
        let ax = FakeMenuBarAXReader(results: Scenario.repeated(drawnSnap, count: Scenario.baselineReadCount() * 2))
        let clock = FakeClock(step: 1.0)
        let verification = HidingVerification(
            discoverer: discoverer,
            capturer: capturer,
            readerFactory: { _ in ax },
            geometry: { TestBar.geometry },
            preflight: { .ready(geometry: TestBar.geometry) },
            sleep: { _ in },
            now: clock.now,
            queue: DispatchQueue(label: "test.serial.\(UUID().uuidString)"),
            parameters: .preRegistered,
            warmUpCount: 0,
            retries: 5
        )

        async let first = verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref.key], reusing: nil)
        async let second = verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref.key], reusing: nil)
        _ = await (first, second)

        #expect(tracker.peak <= 1, "captures from two prepare() sessions must never overlap")
    }

    // MARK: - 11. A dynamic alsoObserved item is dropped

    @Test("a dynamic alsoObserved item is dropped from the observed set, and the target still settles")
    func dynamicAlsoObservedItemIsDropped() async {
        let t1 = Scenario.discoveredItem(identifier: "t1", pid: 606, rawMinX: 59, rawWidth: 9)
        let ref = Scenario.discoveredItem(identifier: "ref", pid: 603, rawMinX: 150, rawWidth: 9)
        let dyn = Scenario.discoveredItem(identifier: "dyn", pid: 607, rawMinX: 100, rawWidth: 9)
        let sectionMap = Scenario.sectionMap([t1])

        // `StripAssessor.baseline` drops the first *kept* sample
        // (`DetectorParameters.baselineDroppedSamples`, 1), so every id's
        // template is actually cut from the second sample's "before"
        // capture -- capture index 2 of 8, not index 0. `dyn` is drawn there
        // (and in the two dropped captures before it, harmlessly) with
        // shapeC -- distinct from t1's shapeA and ref's shapeB, so its own
        // cut template cannot collide with either of theirs during their own
        // whole-strip search -- then omitted entirely from every later
        // capture, so its own template's later-capture mismatch (ink where
        // none remains) is what marks it dynamic. `t1` and `ref` stay
        // constant throughout.
        var captures = [StripImage?]()
        for i in 0..<Scenario.baselineCaptureCount() {
            var glyphs: [(shape: [String], atPt: Double)] = [(TestBar.shapeA, 60), (TestBar.shapeB, 150)]
            if i < 3 { glyphs.append((TestBar.shapeC, 100)) }
            captures.append(Scenario.image(glyphs))
        }
        let baselineSnap = Scenario.snapshot([(t1.key.encoded, 60), (ref.key.encoded, 150), (dyn.key.encoded, 100)])
        let baselineReads = Scenario.repeated(baselineSnap, count: Scenario.baselineReadCount())

        let observeImage = Scenario.image([(TestBar.shapeA, 60), (TestBar.shapeB, 150)])
        let observeSnap = Scenario.snapshot([(t1.key.encoded, 60), (ref.key.encoded, 150)])

        let (verification, _, _, _, _) = Scenario.makeVerification(
            discoveryResults: [Scenario.discovery([t1, ref, dyn])],
            capturerResults: captures + Scenario.repeated(observeImage, count: Scenario.observeCaptureCount()),
            axResults: baselineReads + Scenario.repeated(observeSnap, count: Scenario.observeReadCount())
        )

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, iceIconKey: nil, explicitCandidates: [ref.key], reusing: nil)
        guard case .ready(let ready) = prepared.state else { Issue.record("expected .ready, got \(prepared.state)"); return }
        #expect(ready.alsoObserved.isEmpty, "dyn's dynamic template must be dropped from the observed set")

        let results = await verification.verify(prepared)
        #expect(results[t1.key] == .checked(.stillDrawn))
    }
}

extension Tag {
    @Tag static var mainThread: Self
}
