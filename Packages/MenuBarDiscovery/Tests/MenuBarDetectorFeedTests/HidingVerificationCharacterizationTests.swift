import Foundation
import Testing
import IceCore
import MenuBarCapture
import MenuBarDiscovery
@testable import MenuBarDetectorFeed

/// Characterization tests written against the code before the residuals
/// refactor (plan `2026-09-25-residuals.md` R1, R5, R7) and run green on it
/// first: they pin today's behaviour so the refactor can be shown to keep it.
@Suite("HidingVerification: characterization before the residuals refactor")
struct HidingVerificationCharacterizationTests {
    // MARK: - R1: a skip's roster is every section member, parked included

    @Test("a prepare skipped for no geometry reports every section member -- parked, stacked, positional -- in set order")
    func skipRosterHoldsEverySectionMember() async {
        let parked = fixtureItem(identifier: "parked", pid: 701, minX: 20, position: .parked)
        let stacked = fixtureItem(identifier: "stacked", pid: 702, minX: 30, position: .stacked)
        let positional = fixtureItem(identifier: "pos", pid: 703, minX: 40, basis: .positional)
        let plain = fixtureItem(identifier: "plain", pid: 704, minX: 50)
        let visible = fixtureItem(identifier: "visible", pid: 705, minX: 60)
        let set = fixtureSet(items: [parked, stacked, positional, plain, visible])
        let map: [TagKey: ItemSection] = [
            parked.tagKey: .hidden, stacked.tagKey: .hidden, positional.tagKey: .hidden, plain.tagKey: .hidden, visible.tagKey: .visible,
        ]
        let verification = HidingVerification(
            discoverer: FakeDiscoverer(results: [fixtureDiscovery(set: set)]),
            capturer: FakeStripCapturer(results: []),
            readerFactory: { _ in FakeMenuBarAXReader(results: []) },
            geometry: { nil },
            preflight: { .ready(geometry: TestBar.geometry) },
            sleep: { _ in },
            warmUpCount: 0
        )

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: map, explicitCandidates: nil, reusing: nil)

        #expect(prepared.state == .skip(.noGeometry))
        #expect(prepared.targets == [parked.key, stacked.key, positional.key, plain.key])
    }

    // MARK: - R5: warm-up and retries on each side

    @Test("warm-up precedes each session, and verify retries while the fold reads unreadable -- exact capture and read counts")
    func warmUpAndVerifyRetryCounts() async {
        let (t1, t2, ref) = HidingVerificationTests.basicItems()
        let sectionMap = Scenario.sectionMap([t1, t2])
        let drawn = HidingVerificationTests.drawnImage()
        let readable = HidingVerificationTests.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)
        let unreadable = MenuBarAXSnapshot(itemFrames: readable.itemFrames, agentFrames: [])
        let warmUp = 2

        // prepare: 2 warm-up captures, then one baseline attempt that reads the fold absent.
        // verify: 2 warm-up captures, two observations whose fold is unreadable, a third that is readable.
        let captures = Scenario.repeated(drawn, count: warmUp + Scenario.baselineCaptureCount() + warmUp + Scenario.observeCaptureCount() * 3)
        let reads = Scenario.repeated(readable, count: Scenario.baselineReadCount())
            + Scenario.repeated(unreadable, count: Scenario.observeReadCount() * 2)
            + Scenario.repeated(readable, count: Scenario.observeReadCount())

        let (verification, _, capturer, ax, _) = Scenario.makeVerification(
            discoveryResults: [Scenario.discovery([t1, t2, ref])],
            capturerResults: captures,
            axResults: reads,
            retries: 5,
            warmUpCount: warmUp
        )

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [ref.key], reusing: nil)
        guard case .ready = prepared.state else { Issue.record("expected .ready, got \(prepared.state)"); return }
        #expect(capturer.callCount == warmUp + Scenario.baselineCaptureCount())
        #expect(ax.callCount == Scenario.baselineReadCount())

        let results = await verification.verify(prepared)

        #expect(results[t1.key] == .checked(.stillDrawn))
        #expect(results[t2.key] == .checked(.stillDrawn))
        #expect(capturer.callCount == warmUp + Scenario.baselineCaptureCount() + warmUp + Scenario.observeCaptureCount() * 3)
        #expect(ax.callCount == Scenario.baselineReadCount() + Scenario.observeReadCount() * 3)
    }

    // MARK: - R7: cancelled while prepare awaits discovery

    @Test("cancelled while prepare awaits discovery -> .skip(.cancelled), no capture, whether discovery then returns nil (as the live discoverer does) or a set", arguments: [true, false])
    func cancelWhileAwaitingDiscovery(returnsNilWhenCancelled: Bool) async {
        let (t1, t2, ref) = HidingVerificationTests.basicItems()
        let discoverer = GatedDiscoverer(result: Scenario.discovery([t1, t2, ref]), returnsNilWhenCancelled: returnsNilWhenCancelled)
        let capturer = FakeStripCapturer(results: [])
        let verification = HidingVerification(
            discoverer: discoverer,
            capturer: capturer,
            readerFactory: { _ in FakeMenuBarAXReader(results: []) },
            geometry: { TestBar.geometry },
            preflight: { .ready(geometry: TestBar.geometry) },
            sleep: { _ in },
            warmUpCount: 0
        )

        let task = Task {
            await verification.prepare(sections: [.hidden], sectionMap: Scenario.sectionMap([t1, t2]), explicitCandidates: [ref.key], reusing: nil)
        }
        blockingWait(discoverer.entered)
        task.cancel()
        discoverer.release()
        let prepared = await task.value

        #expect(prepared.state == .skip(.cancelled))
        #expect(capturer.callCount == 0)
    }

    // MARK: - R5: cancellation during a warm-up, on each side

    @Test("cancelled at the first warm-up capture of a session -> prepare .skip(.cancelled) / verify every target .skipped(.cancelled); the warm-up stops there", arguments: ["prepare", "verify"])
    func cancelDuringWarmUp(side: String) async {
        let (t1, t2, ref) = HidingVerificationTests.basicItems()
        let sectionMap = Scenario.sectionMap([t1, t2])
        let drawn = HidingVerificationTests.drawnImage()
        let readable = HidingVerificationTests.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)
        let warmUp = 2

        // The capture to pause at, armed only once the session under test starts,
        // and the number of sleeps taken when it was reached.
        let checkpoint = Box<Int?>(side == "prepare" ? 1 : nil)
        let sleepsAtCheckpoint = Box<Int?>(nil)
        let sleeps = CallCounter()
        let reached = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let capturer = FakeStripCapturer(results: Scenario.repeated(drawn, count: 40), onCall: { index in
            guard index == checkpoint.get() else { return }
            sleepsAtCheckpoint.set(sleeps.count)
            reached.signal()
            release.wait()
        })
        let verification = HidingVerification(
            discoverer: FakeDiscoverer(results: [Scenario.discovery([t1, t2, ref])]),
            capturer: capturer,
            readerFactory: { _ in FakeMenuBarAXReader(results: Scenario.repeated(readable, count: 20)) },
            geometry: { TestBar.geometry },
            preflight: { .ready(geometry: TestBar.geometry) },
            sleep: { _ in sleeps.increment() },
            now: FakeClock(step: 1.0).now,
            queue: DispatchQueue(label: "test.warmupcancel.\(UUID().uuidString)"),
            warmUpCount: warmUp,
            retries: 5
        )

        if side == "prepare" {
            let task = Task { await verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [ref.key], reusing: nil) }
            blockingWait(reached)
            task.cancel()
            release.signal()
            let prepared = await task.value
            #expect(prepared.state == .skip(.cancelled))
        } else {
            let prepared = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [ref.key], reusing: nil)
            guard case .ready = prepared.state else { Issue.record("expected .ready, got \(prepared.state)"); return }
            #expect(capturer.callCount == warmUp + Scenario.baselineCaptureCount())
            checkpoint.set(capturer.callCount + 1)
            let task = Task { await verification.verify(prepared) }
            blockingWait(reached)
            task.cancel()
            release.signal()
            let results = await task.value
            #expect(results == [t1.key: .skipped(.cancelled), t2.key: .skipped(.cancelled)])
        }
        #expect(capturer.callCount == checkpoint.get(), "the capture cancellation landed in completes; no capture reaches the fake after it")
        #expect(sleeps.count == (sleepsAtCheckpoint.get() ?? -1) + 1, "only that capture's own warm-up spacing is slept; the warm-up loop stops at the flag")
    }
}

/// R3's D14 correction, at the seam where it acts: with Ice's icon in the
/// planned set, a reference candidate right of the icon is never used, even
/// when the caller supplies no key for the icon. Red on the code before the
/// residuals refactor (which, given no key, left candidates unbounded and so
/// accepted this one); green after it.
@Suite("HidingVerification: the D14 correction (R3)")
struct HidingVerificationIconBoundTests {
    @Test("a candidate right of Ice's icon is not a reference -> .skip(.noReference) before any capture")
    func candidateRightOfIconIsNotAReference() async {
        let target = fixtureItem(identifier: "target", pid: 801, minX: 50)
        let icon = fixtureItem(identifier: "icon", pid: 900, minX: 150)
        let rightOfIcon = fixtureItem(identifier: "right", pid: 802, minX: 200)
        let set = DiscoveredItemSet(
            items: [target, rightOfIcon], visibleControlItem: icon, hiddenDivider: fixtureDivider(minX: 100), alwaysHiddenDivider: nil,
            ownRead: .ok, systemElements: [], dropped: [], completeness: .complete
        )
        let capturer = FakeStripCapturer(results: [])
        let verification = HidingVerification(
            discoverer: FakeDiscoverer(results: [fixtureDiscovery(set: set)]),
            capturer: capturer,
            readerFactory: { _ in FakeMenuBarAXReader(results: []) },
            geometry: { TestBar.geometry },
            preflight: { .ready(geometry: TestBar.geometry) },
            sleep: { _ in },
            warmUpCount: 0
        )

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: [target.tagKey: .hidden], explicitCandidates: nil, reusing: nil)

        #expect(prepared.state == .skip(.noReference))
        #expect(capturer.callCount == 0)
    }
}

/// A `Discovering` fake that blocks inside `discover` until `release()`, so a
/// test can cancel the caller while discovery is in flight. Afterwards it
/// returns its result, or -- `returnsNilWhenCancelled`, as
/// `MenuBarDiscoverer` does -- `nil` when its task was cancelled.
final class GatedDiscoverer: Discovering, @unchecked Sendable {
    private let result: DiscoveryResult
    private let returnsNilWhenCancelled: Bool
    let entered = DispatchSemaphore(value: 0)
    private let gate = DispatchSemaphore(value: 0)

    init(result: DiscoveryResult, returnsNilWhenCancelled: Bool = false) {
        self.result = result
        self.returnsNilWhenCancelled = returnsNilWhenCancelled
    }

    func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? {
        entered.signal()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                self.gate.wait()
                continuation.resume()
            }
        }
        return returnsNilWhenCancelled && Task.isCancelled ? nil : result
    }

    func release() {
        gate.signal()
    }
}
