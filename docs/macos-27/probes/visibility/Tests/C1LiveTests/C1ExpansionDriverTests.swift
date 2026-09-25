import C1Core
import IceCore
import Testing
@testable import C1Live

/// I5's own testable seam: "test that `--dry` sends no `length`, and that
/// the order of commands around a trip is `rest` then `quit`" (the second
/// half is also covered end to end by `LatchingCapturerTests`; the scenario
/// here exercises it through the same channel the driver uses, so a stage
/// wiring bug that only shows up when both pieces share one channel would
/// still be caught).
@Suite("C1ExpansionDriver")
struct C1ExpansionDriverTests {
    @Test("--dry sends no length, ever")
    func dryNeverSendsLength() {
        let channel = FakeC1HelperChannel()
        let driver = C1ExpansionDriver(channel: channel, dry: true)
        driver.expand(to: 650)
        driver.expand(to: 700)
        driver.collapse()
        #expect(channel.commands.isEmpty)
    }

    @Test("a live run sends length on expand and rest on collapse")
    func liveRunSendsLengthAndRest() {
        let channel = FakeC1HelperChannel()
        let driver = C1ExpansionDriver(channel: channel, dry: false)
        driver.expand(to: 650)
        driver.collapse()
        #expect(channel.commands == [.length(650), .rest])
    }

    @Test("around a trip, sharing the driver's own channel: rest then quit, and --dry still never sent a length")
    func tripOrderThroughTheSameChannelUnderDry() {
        let channel = FakeC1HelperChannel()
        let driver = C1ExpansionDriver(channel: channel, dry: true)
        let base = FakeStripCapturer(results: [StripImage(width: 1, height: 1, scale: 1, bytes: [0, 0, 0, 0])])
        let capturer = LatchingCapturer(base: base, channel: channel) { _ in .init(protectedMissing: true) }

        driver.expand(to: 650) // --dry: no-op
        _ = capturer.capture() // trips
        driver.collapse() // --dry: no-op

        #expect(channel.commands == [.rest, .quitAll])
    }
}
