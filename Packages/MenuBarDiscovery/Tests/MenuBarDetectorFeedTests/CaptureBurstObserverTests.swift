import Foundation
import Testing
import IceCore
import MenuBarCapture
import MenuBarDiscovery
@testable import MenuBarDetectorFeed

/// The observer keeps its capture sessions out of the capture indicator's
/// reach, and says what an observation's matcher read (plan
/// 2026-10-09-lab-first-run-followup, S3 design D2 and D3).
@Suite("HiddenLengthObserver in capture bursts")
struct CaptureBurstObserverTests {
    typealias Base = HiddenLengthObserverTests

    struct Rig {
        let observer: HiddenLengthObserver
        let burst: CaptureBurstClock
        let capturer: FakeStripCapturer
        let sleeps: Box<[Double]>
        let now: Box<Double>
    }

    /// An observer whose baseline sees both members drawn and whose
    /// observation reads `observeImage`. Sleeping moves the clock on;
    /// `onSleep` runs inside every sleep, before that.
    static func rig(
        observeImage: StripImage = Base.hiddenImage,
        onSleep: (@Sendable (Double) -> Void)? = nil,
        chevronReader: (any MenuBarAXReading)? = nil,
        holdFirstSettle: Box<Bool>? = nil,
        observations: Int = 1
    ) -> Rig {
        let captures = Scenario.repeated(HidingVerificationTests.drawnImage(), count: Scenario.baselineCaptureCount())
            + Scenario.repeated(observeImage, count: Scenario.observeCaptureCount() * observations)
        let reads = Scenario.repeated(Base.drawnSnapshot, count: Scenario.baselineReadCount())
            + Scenario.repeated(Base.hiddenSnapshot, count: Scenario.observeReadCount() * observations)
        let (verification, _, capturer, _, _) = Scenario.makeVerification(
            discoveryResults: [Scenario.discovery([Base.items.t1, Base.items.t2, Base.items.ref])],
            capturerResults: captures,
            axResults: reads,
            retries: 1
        )
        let burst = CaptureBurstClock()
        let sleeps = Box([Double]())
        let now = Box(0.0)
        let held = Box(false)
        let observer = HiddenLengthObserver(
            verification: verification,
            chevron: ChevronReader(
                reader: chevronReader ?? FakeMenuBarAXReader(results: Array(repeating: Base.agents(chevron: false), count: observations)),
                barHeight: Double(TestBar.heightPt)
            ),
            settle: 1,
            sleep: {
                sleeps.set(sleeps.get() + [$0])
                onSleep?($0)
                // The first settle waits until the test lets it go: a session superseded meanwhile.
                if let holdFirstSettle, $0 == 1, !held.get() {
                    held.set(true)
                    while !holdFirstSettle.get() { await Task.yield() }
                }
                now.set(now.get() + $0)
            },
            burst: burst,
            now: { now.get() }
        )
        return Rig(observer: observer, burst: burst, capturer: capturer, sleeps: sleeps, now: now)
    }

    @Test("after a baseline's captures the first observation waits until the bar is clear, and says how long")
    func waitsAfterBaseline() async {
        let rig = Self.rig()
        #expect(await rig.observer.takeBaseline(sectionMap: Base.sectionMap) == .covered)
        rig.burst.noteCapture(at: 100)
        rig.burst.noteCapture(at: 104.5)
        rig.now.set(107)
        let reading = await rig.observer.observe()
        #expect(rig.sleeps.get() == [1, 18.5])
        #expect(reading.waited == 18.5)
        #expect(reading.checks.values.allSatisfy { $0 == Base.clean })
    }

    @Test("a capture taken elsewhere during the wait extends it (Codex review, round 3)")
    func waitIsRechecked() async {
        let noted = Box(false)
        let burst = Box<CaptureBurstClock?>(nil)
        let rig = Self.rig(onSleep: { seconds in
            // The hiding check captures at 110, while the observer sleeps to 126.5.
            if seconds > 1, !noted.get() {
                noted.set(true)
                burst.get()?.noteCapture(at: 110)
            }
        })
        burst.set(rig.burst)
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        rig.burst.noteCapture(at: 100)
        rig.burst.noteCapture(at: 104.5)
        rig.now.set(107)
        let reading = await rig.observer.observe()
        #expect(rig.sleeps.get() == [1, 18.5, 5.5])
        #expect(reading.waited == 24)
    }

    @Test("a baseline closes its burst: the observation after it waits however soon it comes")
    func baselineClosesItsBurst() async {
        let rig = Self.rig()
        rig.burst.noteCapture(at: 100)
        rig.now.set(100.5)
        #expect(rig.burst.snapshot.decision(for: .observation, now: 100.5) == .go)
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        // The baseline waited for a clear bar until 122 and took its place
        // there: the bar is clear 22 s after that.
        #expect(rig.burst.snapshot.decision(for: .observation, now: 122.5) == .wait(until: 144))
    }

    @Test("a second observation that fits the burst does not wait")
    func sharesABurst() async {
        let rig = Self.rig()
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        rig.burst.noteCapture(at: 100)
        rig.burst.noteCapture(at: 101.5)
        rig.now.set(103)
        let reading = await rig.observer.observe()
        #expect(rig.sleeps.get() == [1])
        #expect(reading.waited == 0)
        #expect(reading.burst?.age == 1.5)
    }

    @Test("a baseline asked for while the bar is not clear waits too")
    func baselineWaits() async {
        let rig = Self.rig()
        rig.burst.noteCapture(at: 100)
        rig.now.set(103.5)
        #expect(await rig.observer.takeBaseline(sectionMap: Base.sectionMap) == .covered)
        #expect(rig.sleeps.get() == [18.5])
        #expect(rig.now.get() == 122)
    }

    @Test("an observation cancelled while it waits captures nothing")
    func cancelledWait() async {
        // The settle is 1 s; the only longer sleep is the wait.
        let rig = Self.rig(onSleep: { seconds in
            if seconds > 1 { withUnsafeCurrentTask { $0?.cancel() } }
        })
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        let baselineCaptures = rig.capturer.callCount
        rig.burst.noteCapture(at: 100)
        rig.burst.noteCapture(at: 104.5)
        rig.now.set(107)
        let observer = rig.observer
        let reading = await Task { await observer.observe() }.value
        #expect(reading == .nothing)
        #expect(rig.capturer.callCount == baselineCaptures)
    }

    // MARK: - Sessions (plan 2026-10-19-verify-in-a-clean-burst, D4 and D5)

    @Test("an observation on a clear bar is the first session of a burst of its own, read when it ends")
    func firstSessionOfItsOwn() async {
        let rig = Self.rig()
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        rig.now.set(200)
        let reading = await rig.observer.observe()
        #expect(reading.burst?.ordinal == 1)
        #expect(reading.burst?.burstStartedAt == 201)
        #expect(reading.burst?.burstID == rig.burst.snapshot.burstID)
    }

    @Test("an observation that joins a burst reads as its second session")
    func joiningIsSecond() async {
        let rig = Self.rig()
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        rig.burst.noteCapture(at: 100)
        rig.burst.noteCapture(at: 101.5)
        rig.now.set(103)
        let reading = await rig.observer.observe()
        #expect(reading.burst == ObservationBurst(burstID: rig.burst.snapshot.burstID, ordinal: 2, burstStartedAt: 100, capturedAt: 101.5))
    }

    @Test("an observation that closes its burst leaves nothing to join it; one that does not, leaves it open")
    func closesItsBurst() async {
        for closes in [true, false] {
            let rig = Self.rig()
            _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
            rig.now.set(200)
            _ = await rig.observer.observe(closesBurst: closes)
            #expect(rig.burst.snapshot.isClosed == closes)
        }
    }

    @Test("an observation that closes its burst closes it when cancelled after it began, and the next reading is a new burst's first")
    func closesWhenCancelled() async {
        let handle = Box<Task<HiddenLengthReading, Never>?>(nil)
        let rig = Self.rig(chevronReader: CancellingAXReader(handle: handle))
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        rig.now.set(200)
        let observer = rig.observer
        let task = Task { await observer.observe(closesBurst: true) }
        handle.set(task)
        let cancelled = await task.value
        #expect(cancelled == .nothing)
        #expect(rig.burst.snapshot.isClosed)
        let first = rig.burst.snapshot.burstID
        let next = await observer.observe()
        #expect(next.burst?.ordinal == 1)
        #expect(next.burst.map { $0.burstID > first } == true)
    }

    @Test("a session superseded by a newer one reads nothing, and closes the burst it began in only if it began")
    func supersededReadsNothing() async {
        let release = Box(false)
        let rig = Self.rig(holdFirstSettle: release)
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        rig.now.set(200)
        let observer = rig.observer
        let older = Task { await observer.observe(closesBurst: true) }
        // Let the older session reach its settle before the newer one starts.
        while rig.sleeps.get().count < 1 { await Task.yield() }
        let newer = await observer.observe()
        release.set(true)
        #expect(await older.value == .nothing)
        #expect(newer.burst?.ordinal == 1)
    }

    @Test("the recording capturer tells the clock of every capture it takes, a failed one too")
    func recordingCapturer() {
        let burst = CaptureBurstClock()
        let times = Box([100.0, 100.3, 130.0])
        let capturer = BurstRecordingCapturer(
            wrapping: FakeStripCapturer(results: [Base.hiddenImage, nil, Base.hiddenImage]),
            burst: burst,
            now: {
                let all = times.get()
                times.set(Array(all.dropFirst()))
                return all[0]
            }
        )
        #expect(capturer.capture() != nil)
        #expect(capturer.capture() == nil)
        #expect(burst.snapshot.burstStart == 100)
        #expect(burst.snapshot.lastCapture == 100.3)
        #expect(capturer.capture() != nil)
        #expect(burst.snapshot.burstStart == 130)
    }

    @Test("an observation whose reference moved says which, and by how far")
    func movedReferenceDiagnostics() async {
        // The reference was baselined at x 150 and is read at 160.
        let rig = Self.rig(observeImage: Scenario.image([(TestBar.shapeB, 160)]))
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        let reading = await rig.observer.observe()
        #expect(reading.checks.values.allSatisfy { $0 == .checked(.unverifiable(.captureUnstable)) })
        #expect(reading.diagnostics?.captureStable == false)
        let reference = reading.diagnostics?.references.first
        #expect(reading.diagnostics?.references.count == 1)
        #expect(reference?.key == Base.items.ref.key)
        #expect(reference?.match == "unique")
        #expect(reference?.offset == 10)
        #expect(!reading.displaced, "one reference alone may have moved by itself")
    }

    @Test("an observation whose two references moved the same way says the bar is displaced under its baseline")
    func displacedBar() async {
        // t2 and the reference stay shown, baselined at x 70 and 150, and are read at 80 and 160.
        let rig = Self.rig(observeImage: Scenario.image([(TestBar.shapeC, 80), (TestBar.shapeB, 160)]))
        let sectionMap = Scenario.sectionMap([Base.items.t1])
            .merging(Scenario.sectionMap([Base.items.t2, Base.items.ref], section: .visible)) { first, _ in first }
        _ = await rig.observer.takeBaseline(sectionMap: sectionMap)
        let reading = await rig.observer.observe()
        #expect(reading.diagnostics?.captureStable == false)
        #expect(reading.diagnostics?.references.map(\.offset) == [10, 10])
        #expect(reading.displaced)
    }

    @Test("a clean observation's diagnostics say the reference stood still")
    func cleanDiagnostics() async {
        let rig = Self.rig()
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        let reading = await rig.observer.observe()
        let diagnostics = reading.diagnostics
        #expect(diagnostics?.captureStable == true)
        #expect(diagnostics?.references.first?.offset == 0)
        #expect(diagnostics?.fold == "absent")
        #expect(!reading.displaced)
    }
}

/// A `MenuBarAgent` read that cancels the observation reading it, once: a
/// session cancelled after its captures, while it reads the `«`. The read
/// runs on a queue of its own, so the task is named, not current.
final class CancellingAXReader: MenuBarAXReading, @unchecked Sendable {
    private let handle: Box<Task<HiddenLengthReading, Never>?>
    private let done = Box(false)

    init(handle: Box<Task<HiddenLengthReading, Never>?>) {
        self.handle = handle
    }

    func read(items: [String: pid_t]) -> MenuBarAXSnapshot? {
        if !done.get() {
            while handle.get() == nil { usleep(1000) }
            handle.get()?.cancel()
            done.set(true)
        }
        return HiddenLengthObserverTests.agents(chevron: false)
    }
}
