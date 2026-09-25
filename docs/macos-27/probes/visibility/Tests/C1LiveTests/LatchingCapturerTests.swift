import C1Core
import IceCore
import Testing
@testable import C1Live

/// I3: "a trip sends rest before the capture is returned; a failed capture
/// aborts." Both with a fake capturer and a fake helper channel -- nothing
/// here touches the screen or a real helper.
@Suite("LatchingCapturer")
struct LatchingCapturerTests {
    func image() -> StripImage {
        StripImage(width: 1, height: 1, scale: 1, bytes: [0, 0, 0, 0])
    }

    @Test("a quiet capture passes through untouched, and the channel is never used")
    func quietCapturePassesThrough() {
        let base = FakeStripCapturer(results: [image()])
        let channel = FakeC1HelperChannel()
        let capturer = LatchingCapturer(base: base, channel: channel) { _ in .init() }
        #expect(capturer.capture() == image())
        #expect(channel.commands.isEmpty)
    }

    @Test("a trip sends rest, then quits every helper, before the capture is returned")
    func tripSendsRestThenQuitsBeforeReturning() {
        let base = FakeStripCapturer(results: [image()])
        let channel = FakeC1HelperChannel()
        let capturer = LatchingCapturer(base: base, channel: channel) { _ in .init(protectedMissing: true) }
        let returned = capturer.capture()
        #expect(returned == image())
        #expect(channel.commands == [.rest, .quitAll])
    }

    @Test("a failed capture aborts: the channel still gets rest then quit, and capture() reports nil")
    func failedCaptureAborts() {
        let base = FakeStripCapturer(results: [nil])
        let channel = FakeC1HelperChannel()
        let assessCalls = CallCounter()
        let capturer = LatchingCapturer(base: base, channel: channel) { _ in
            assessCalls.increment()
            return .init()
        }
        #expect(capturer.capture() == nil)
        #expect(channel.commands == [.rest, .quitAll])
        // A failed capture never reaches the assess closure -- there is no
        // image to hand it.
        #expect(assessCalls.count == 0)
    }

    @Test("once tripped, a later quiet capture does not trip again")
    func staysTrippedAcrossLaterCaptures() {
        let base = FakeStripCapturer(results: [image(), image()])
        let channel = FakeC1HelperChannel()
        let capturer = LatchingCapturer(base: base, channel: channel) { _ in .init(protectedMissing: true) }
        _ = capturer.capture()
        _ = capturer.capture()
        #expect(channel.commands == [.rest, .quitAll])
    }

    @Test("resetAfterPassingCheck lets a fresh trip fire again")
    func resetAllowsAnotherTrip() {
        let base = FakeStripCapturer(results: [image(), image()])
        let channel = FakeC1HelperChannel()
        let capturer = LatchingCapturer(base: base, channel: channel) { _ in .init(protectedMissing: true) }
        _ = capturer.capture()
        capturer.resetAfterPassingCheck()
        _ = capturer.capture()
        #expect(channel.commands == [.rest, .quitAll, .rest, .quitAll])
    }

    @Test("feed() reports an observation the stage gathered outside a single capture (e.g. the fold), same trip behaviour")
    func feedAppliesTheSameTripBehaviour() {
        let base = FakeStripCapturer(results: [image()])
        let channel = FakeC1HelperChannel()
        let capturer = LatchingCapturer(base: base, channel: channel) { _ in .init() }
        capturer.feed(.init(foldAppearedWithoutExpansion: true))
        #expect(channel.commands == [.rest, .quitAll])
        // A quiet capture afterwards does not trip a second time.
        _ = capturer.capture()
        #expect(channel.commands == [.rest, .quitAll])
    }
}
