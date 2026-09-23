import Testing
@testable import MenuBarCapture
import IceCore

@Suite("Preflight")
struct PreflightTests {
    static let geometry = BarGeometry(widthPt: 100, heightPt: 20, scale: 1, notch: nil)

    static func zeroStrip() -> StripImage {
        StripImage(width: 10, height: 10, scale: 1, bytes: [UInt8](repeating: 0, count: 400))
    }

    static func liveStrip() -> StripImage {
        StripImage(width: 10, height: 10, scale: 1, bytes: [UInt8](repeating: 200, count: 400))
    }

    static func agentSnapshot(minY: Double = 5) -> MenuBarAXSnapshot {
        MenuBarAXSnapshot(itemFrames: [:], agentFrames: [AgentFrame(minX: 0, minY: minY, width: 20)])
    }

    @Test("captureUnavailable when the capture is uniformly zero")
    func captureUnavailableOnZeroStrip() {
        let capturer = FakeStripCapturer(results: [Self.zeroStrip()])
        let ax = FakeMenuBarAXReader(results: [Self.agentSnapshot()])

        let result = Preflight.run(capturer: capturer, axReader: ax, geometry: Self.geometry, isTrusted: { true })

        #expect(result == .unavailable(.captureUnavailable))
    }

    @Test("captureUnavailable when the capturer itself fails")
    func captureUnavailableOnNilCapture() {
        let capturer = FakeStripCapturer(results: [nil])
        let ax = FakeMenuBarAXReader(results: [Self.agentSnapshot()])

        let result = Preflight.run(capturer: capturer, axReader: ax, geometry: Self.geometry, isTrusted: { true })

        #expect(result == .unavailable(.captureUnavailable))
    }

    @Test("accessibilityNotTrusted when AXIsProcessTrusted reports false")
    func accessibilityNotTrusted() {
        let capturer = FakeStripCapturer(results: [Self.liveStrip()])
        let ax = FakeMenuBarAXReader(results: [Self.agentSnapshot()])

        let result = Preflight.run(capturer: capturer, axReader: ax, geometry: Self.geometry, isTrusted: { false })

        #expect(result == .unavailable(.accessibilityNotTrusted))
    }

    @Test("menuBarAgentUnreadable when the AX read fails outright")
    func menuBarAgentUnreadableOnNilRead() {
        let capturer = FakeStripCapturer(results: [Self.liveStrip()])
        let ax = FakeMenuBarAXReader(results: [nil])

        let result = Preflight.run(capturer: capturer, axReader: ax, geometry: Self.geometry, isTrusted: { true })

        #expect(result == .unavailable(.menuBarAgentUnreadable))
    }

    @Test("menuBarAgentUnreadable when the read succeeds with no agent frames")
    func menuBarAgentUnreadableOnEmptyFrames() {
        let capturer = FakeStripCapturer(results: [Self.liveStrip()])
        let ax = FakeMenuBarAXReader(results: [MenuBarAXSnapshot(itemFrames: [:], agentFrames: [])])

        let result = Preflight.run(capturer: capturer, axReader: ax, geometry: Self.geometry, isTrusted: { true })

        #expect(result == .unavailable(.menuBarAgentUnreadable))
    }

    @Test("menuBarAutoHidden when an agent frame sits outside the bar row")
    func menuBarAutoHidden() {
        let capturer = FakeStripCapturer(results: [Self.liveStrip()])
        let ax = FakeMenuBarAXReader(results: [Self.agentSnapshot(minY: 1104)])

        let result = Preflight.run(capturer: capturer, axReader: ax, geometry: Self.geometry, isTrusted: { true })

        #expect(result == .unavailable(.menuBarAutoHidden))
    }

    @Test("ready when every check passes")
    func ready() {
        let capturer = FakeStripCapturer(results: [Self.liveStrip()])
        let ax = FakeMenuBarAXReader(results: [Self.agentSnapshot()])

        let result = Preflight.run(capturer: capturer, axReader: ax, geometry: Self.geometry, isTrusted: { true })

        #expect(result == .ready(geometry: Self.geometry))
    }

    @Test("nothing after the first failure runs")
    func stopsAtFirstFailure() {
        let capturer = FakeStripCapturer(results: [nil])
        let ax = FakeMenuBarAXReader(results: [Self.agentSnapshot()])

        _ = Preflight.run(capturer: capturer, axReader: ax, geometry: Self.geometry, isTrusted: { true })

        #expect(ax.callCount == 0)
    }
}
