import Testing
import IceCore
import MenuBarCapture
@testable import MenuBarDetectorFeed

/// Whether `MenuBarAgent` lists the system's `«` on the bar, by Accessibility
/// alone (plan 2026-10-03-icebar-build, section 9.3): no capture, so the rest
/// watch does not summon the capture indicator it would then have to explain.
@Suite("ChevronReader")
struct ChevronReaderTests {
    static let barHeight = 24.0

    func listed(_ snapshot: MenuBarAXSnapshot?) -> Bool? {
        ChevronReader(reader: FakeMenuBarAXReader(results: [snapshot]), barHeight: Self.barHeight).read()
    }

    func agents(_ frames: [AgentFrame]) -> MenuBarAXSnapshot {
        MenuBarAXSnapshot(itemFrames: [:], agentFrames: frames)
    }

    @Test("a 17.5 pt agent frame on the bar is the chevron")
    func chevronOnBar() {
        #expect(listed(agents([AgentFrame(minX: 700, minY: 0, width: 26), AgentFrame(minX: 750, minY: 2, width: 17.5)])) == true)
    }

    @Test("agent frames of other widths are not")
    func otherWidths() {
        #expect(listed(agents([AgentFrame(minX: 700, minY: 0, width: 26), AgentFrame(minX: 750, minY: 0, width: 16)])) == false)
    }

    @Test("a chevron-wide frame off the bar is not on the bar", arguments: [-30.0, barHeight])
    func offBar(minY: Double) {
        #expect(listed(agents([AgentFrame(minX: 700, minY: 0, width: 26), AgentFrame(minX: 750, minY: minY, width: 17.5)])) == false)
    }

    @Test("a failed read, an empty agent or a frame that is not a number is unreadable")
    func unreadable() {
        #expect(listed(nil) == nil)
        #expect(listed(agents([])) == nil)
        #expect(listed(agents([AgentFrame(minX: .nan, minY: 0, width: 17.5)])) == nil)
        #expect(listed(agents([AgentFrame(minX: 700, minY: 0, width: .infinity)])) == nil)
    }

    @Test("it asks the reader for no items, only the agent")
    func asksForNoItems() {
        let reader = FakeMenuBarAXReader(results: [agents([AgentFrame(minX: 700, minY: 0, width: 26)])])
        _ = ChevronReader(reader: reader, barHeight: Self.barHeight).read()
        #expect(reader.requestedItems == [[:]])
    }

    @Test("the asynchronous read gives the same answer off the caller's thread")
    func asyncRead() async {
        let reader = FakeMenuBarAXReader(results: [agents([AgentFrame(minX: 750, minY: 0, width: 17.5)])])
        let answer = await ChevronReader(reader: reader, barHeight: Self.barHeight).chevronListed()
        #expect(answer == true)
        #expect(reader.mainThreadCalls == [false])
    }
}
