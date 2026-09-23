import Testing
@testable import MenuBarCapture
import IceCore

@Suite("Sampler")
struct SamplerTests {
    static func strip() -> StripImage {
        StripImage(width: 4, height: 4, scale: 1, bytes: [UInt8](repeating: 10, count: 64))
    }

    static func snapshot() -> MenuBarAXSnapshot {
        MenuBarAXSnapshot(itemFrames: [:], agentFrames: [AgentFrame(minX: 0, minY: 0, width: 20)])
    }

    @Test("captures, reads, then captures again, in that order")
    func ordersCaptureReadCapture() {
        let log = OrderLog()
        let capturer = FakeStripCapturer(results: [Self.strip(), Self.strip()], log: log)
        let ax = FakeMenuBarAXReader(results: [Self.snapshot()], log: log)
        let sampler = Sampler(capturer: capturer, axReader: ax, now: { 1.0 })

        let sample = sampler.sample(items: [:])

        #expect(sample != nil)
        #expect(log.events == ["capture", "read", "capture"])
        #expect(capturer.callCount == 2)
        #expect(ax.callCount == 1)
    }

    @Test("no sample when the first capture fails")
    func noSampleOnFirstCaptureFailure() {
        let capturer = FakeStripCapturer(results: [nil])
        let ax = FakeMenuBarAXReader(results: [Self.snapshot()])
        let sampler = Sampler(capturer: capturer, axReader: ax, now: { 1.0 })

        #expect(sampler.sample(items: [:]) == nil)
        #expect(ax.callCount == 0, "a failed capture must never reach the AX read")
    }

    @Test("no sample when the AX read fails")
    func noSampleOnReadFailure() {
        let capturer = FakeStripCapturer(results: [Self.strip(), Self.strip()])
        let ax = FakeMenuBarAXReader(results: [nil])
        let sampler = Sampler(capturer: capturer, axReader: ax, now: { 1.0 })

        #expect(sampler.sample(items: [:]) == nil)
        #expect(capturer.callCount == 1, "the second capture must never run after a failed read")
    }

    @Test("no sample when the second capture fails")
    func noSampleOnSecondCaptureFailure() {
        let capturer = FakeStripCapturer(results: [Self.strip(), nil])
        let ax = FakeMenuBarAXReader(results: [Self.snapshot()])
        let sampler = Sampler(capturer: capturer, axReader: ax, now: { 1.0 })

        #expect(sampler.sample(items: [:]) == nil)
    }

    @Test("passes the requested items through to the AX reader")
    func passesItemsThrough() {
        let capturer = FakeStripCapturer(results: [Self.strip(), Self.strip()])
        let ax = FakeMenuBarAXReader(results: [Self.snapshot()])
        let sampler = Sampler(capturer: capturer, axReader: ax, now: { 1.0 })

        _ = sampler.sample(items: ["target": 111])

        #expect(ax.requestedItems == [["target": 111]])
    }

    @Test("stamps the sample with the clock's time")
    func stampsTime() {
        let capturer = FakeStripCapturer(results: [Self.strip(), Self.strip()])
        let ax = FakeMenuBarAXReader(results: [Self.snapshot()])
        let sampler = Sampler(capturer: capturer, axReader: ax, now: { 42.5 })

        #expect(sampler.sample(items: [:])?.time == 42.5)
    }

    @Test("carries the AX snapshot's frames into the sample")
    func carriesFramesThrough() {
        let capturer = FakeStripCapturer(results: [Self.strip(), Self.strip()])
        let frame = ItemFrame(id: "target", minX: 10, minY: 0, width: 5, height: 12)
        let snapshot = MenuBarAXSnapshot(itemFrames: ["target": frame], agentFrames: [AgentFrame(minX: 0, minY: 0, width: 20)])
        let ax = FakeMenuBarAXReader(results: [snapshot])
        let sampler = Sampler(capturer: capturer, axReader: ax, now: { 1.0 })

        let sample = sampler.sample(items: ["target": 111])

        #expect(sample?.itemFrames == ["target": frame])
        #expect(sample?.agentFrames == snapshot.agentFrames)
    }
}
