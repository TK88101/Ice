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
        onSleep: (@Sendable (Double) -> Void)? = nil
    ) -> Rig {
        let captures = Scenario.repeated(HidingVerificationTests.drawnImage(), count: Scenario.baselineCaptureCount())
            + Scenario.repeated(observeImage, count: Scenario.observeCaptureCount())
        let reads = Scenario.repeated(Base.drawnSnapshot, count: Scenario.baselineReadCount())
            + Scenario.repeated(Base.hiddenSnapshot, count: Scenario.observeReadCount())
        let (verification, _, capturer, _, _) = Scenario.makeVerification(
            discoveryResults: [Scenario.discovery([Base.items.t1, Base.items.t2, Base.items.ref])],
            capturerResults: captures,
            axResults: reads,
            retries: 1
        )
        let burst = CaptureBurstClock()
        let sleeps = Box([Double]())
        let now = Box(0.0)
        let observer = HiddenLengthObserver(
            verification: verification,
            chevron: ChevronReader(reader: FakeMenuBarAXReader(results: [Base.agents(chevron: false)]), barHeight: Double(TestBar.heightPt)),
            settle: 1,
            sleep: {
                sleeps.set(sleeps.get() + [$0])
                onSleep?($0)
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
        #expect(rig.burst.decision(for: .observation, now: 100.5) == .go)
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        #expect(rig.burst.decision(for: .observation, now: 100.5) == .wait(until: 122))
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
        #expect(reading.burstAge == 1.5)
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
    }

    @Test("a clean observation's diagnostics say the reference stood still")
    func cleanDiagnostics() async {
        let rig = Self.rig()
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        let diagnostics = await rig.observer.observe().diagnostics
        #expect(diagnostics?.captureStable == true)
        #expect(diagnostics?.references.first?.offset == 0)
        #expect(diagnostics?.fold == "absent")
    }
}
