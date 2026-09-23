import Darwin
import Testing
@testable import MenuBarCapture
import IceCore

@Suite("VisibilityObserver")
struct VisibilityObserverTests {
    static let items: [String: pid_t] = ["target": 1, "reference": 2]

    /// Builds an observer over scripted capture/AX results and a fake, non-
    /// sleeping clock: `clockStep` seconds pass on every `Sampler.sample`
    /// call, so the test controls exactly how many samples span how much
    /// time without a real wait.
    static func makeObserver(
        capturerResults: [StripImage?],
        axResults: [MenuBarAXSnapshot?],
        clockStep: Double = 1.0
    ) -> (observer: VisibilityObserver, sleepCount: () -> Int) {
        let clock = FakeClock(step: clockStep)
        let capturer = FakeStripCapturer(results: capturerResults)
        let ax = FakeMenuBarAXReader(results: axResults)
        let sampler = Sampler(capturer: capturer, axReader: ax, now: clock.now)
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let observer = VisibilityObserver(sampler: sampler, sleep: { _ in counter.value += 1 })
        return (observer, { counter.value })
    }

    /// Four samples (eight captures) of the same drawn strip: enough to span
    /// `DetectorParameters.preRegistered.baselineMinSpan` (3s) at
    /// `clockStep = 1` and satisfy `baselineMinSamples` (4).
    static func drawnBaselineFixture() -> (capturer: [StripImage?], ax: [MenuBarAXSnapshot?]) {
        let image = TestBar.image(target: true, reference: true)
        return (Array(repeating: image, count: 4).flatMap { [$0, $0] }, Array(repeating: TestBar.snapshot(), count: 4))
    }

    @Test("gathers a real baseline that accepts both items and reads no fold")
    func baselineAcceptsBoth() {
        let fixture = Self.drawnBaselineFixture()
        let (observer, _) = Self.makeObserver(capturerResults: fixture.capturer, axResults: fixture.ax)

        let result = observer.baseline(items: Self.items, geometry: TestBar.geometry)

        #expect(result?.acceptedIDs == ["reference", "target"])
        #expect(result?.foldAtBaseline == .absent)
        #expect(result?.rejections.isEmpty == true)
    }

    @Test("nil baseline when a sample fails partway through")
    func baselineNilOnFailure() {
        let image = TestBar.image(target: true, reference: true)
        // Two good samples (4 captures), then a failed capture before a third.
        let capturerResults: [StripImage?] = [image, image, image, image, nil]
        let (observer, _) = Self.makeObserver(capturerResults: capturerResults, axResults: Array(repeating: TestBar.snapshot(), count: 4))

        #expect(observer.baseline(items: Self.items, geometry: TestBar.geometry) == nil)
    }

    @Test("nil baseline when the AX read fails partway through")
    func baselineNilOnAXFailure() {
        let image = TestBar.image(target: true, reference: true)
        let capturerResults: [StripImage?] = Array(repeating: image, count: 6).map { $0 }
        let axResults: [MenuBarAXSnapshot?] = [TestBar.snapshot(), TestBar.snapshot(), nil]
        let (observer, _) = Self.makeObserver(capturerResults: capturerResults, axResults: axResults)

        #expect(observer.baseline(items: Self.items, geometry: TestBar.geometry) == nil)
    }

    @Test("observe reports the target drawn while both items are present")
    func observeReportsDrawn() throws {
        let baselineFixture = Self.drawnBaselineFixture()
        let (baselineObserver, _) = Self.makeObserver(capturerResults: baselineFixture.capturer, axResults: baselineFixture.ax)
        let baseline = try #require(baselineObserver.baseline(items: Self.items, geometry: TestBar.geometry))

        let drawn = TestBar.image(target: true, reference: true)
        let (observer, sleepCount) = Self.makeObserver(
            capturerResults: Array(repeating: drawn, count: 2).flatMap { [$0, $0] },
            axResults: Array(repeating: TestBar.snapshot(), count: 2)
        )

        let result = observer.observe(baseline: baseline, targets: ["target"], references: ["reference"], items: Self.items)

        #expect(result?.reading.captureStable == true)
        #expect(result?.visibility["target"] == .drawn(x: 59))
        #expect(sleepCount() == 1, "one sleep between the two minimum samples")
    }

    @Test("observe reports the target not drawn once its AX frame and ink are both gone")
    func observeReportsHidden() throws {
        let baselineFixture = Self.drawnBaselineFixture()
        let (baselineObserver, _) = Self.makeObserver(capturerResults: baselineFixture.capturer, axResults: baselineFixture.ax)
        let baseline = try #require(baselineObserver.baseline(items: Self.items, geometry: TestBar.geometry))

        let hidden = TestBar.image(target: false, reference: true)
        let (observer, _) = Self.makeObserver(
            capturerResults: Array(repeating: hidden, count: 2).flatMap { [$0, $0] },
            axResults: Array(repeating: TestBar.snapshot(includeTarget: false), count: 2)
        )

        let result = observer.observe(baseline: baseline, targets: ["target"], references: ["reference"], items: Self.items)

        #expect(result?.reading.captureStable == true)
        #expect(result?.visibility["target"] == .notDrawn)
    }

    @Test("nil observation when a sample fails")
    func observeNilOnFailure() throws {
        let baselineFixture = Self.drawnBaselineFixture()
        let (baselineObserver, _) = Self.makeObserver(capturerResults: baselineFixture.capturer, axResults: baselineFixture.ax)
        let baseline = try #require(baselineObserver.baseline(items: Self.items, geometry: TestBar.geometry))

        let image = TestBar.image(target: true, reference: true)
        let (observer, _) = Self.makeObserver(
            capturerResults: [image, image, nil],
            axResults: Array(repeating: TestBar.snapshot(), count: 2)
        )

        #expect(observer.observe(baseline: baseline, targets: ["target"], references: ["reference"], items: Self.items) == nil)
    }
}
