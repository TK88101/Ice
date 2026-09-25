import Foundation
import Testing
@testable import IceWatchCore

/// The supervisor's pure parts (plan 2026-09-24-ice-first-run.md, section 5):
/// the stop machine, the deadman, the restore gate, the settings comparison,
/// the log-line matcher and the topology record.
@Suite("StopMachine")
struct StopMachineTests {
    @Test("a stop sends TERM, then KILL after one second, then watches 30 s, then restores")
    func fullSequence() {
        var machine = StopMachine()
        #expect(machine.requestStop(now: 100, child: .alive(identityMatches: true)) == [.sendTerm])
        #expect(machine.step(now: 100.5, child: .alive(identityMatches: true)).isEmpty)
        #expect(machine.step(now: 101.0, child: .alive(identityMatches: true)) == [.sendKill])
        #expect(machine.step(now: 101.2, child: .gone) == [.beginPostWatch])
        #expect(machine.step(now: 131.1, child: .gone).isEmpty)
        #expect(machine.step(now: 131.2, child: .gone) == [.restore])
        #expect(machine.restoreFinished() == [.finish])
        #expect(machine.phase == .done)
    }

    @Test("a child that exits after TERM is never sent KILL")
    func exitsAfterTerm() {
        var machine = StopMachine()
        #expect(machine.requestStop(now: 0, child: .alive(identityMatches: true)) == [.sendTerm])
        #expect(machine.step(now: 0.4, child: .gone) == [.beginPostWatch])
        #expect(machine.step(now: 5, child: .gone).isEmpty)
    }

    @Test("a PID whose path or start time changed is never signalled")
    func identityChanged() {
        var machine = StopMachine()
        #expect(machine.requestStop(now: 0, child: .alive(identityMatches: false)) == [.beginPostWatch])
        var other = StopMachine()
        #expect(other.requestStop(now: 0, child: .alive(identityMatches: true)) == [.sendTerm])
        #expect(other.step(now: 1.5, child: .alive(identityMatches: false)) == [.beginPostWatch])
    }

    @Test("a child that exits on its own is watched and then restored")
    func childExitsOnItsOwn() {
        var machine = StopMachine()
        #expect(machine.requestStop(now: 10, child: .gone) == [.beginPostWatch])
        #expect(machine.step(now: 40.1, child: .gone) == [.restore])
    }

    @Test("a stop before the child was started restores at once")
    func stopBeforeStart() {
        var machine = StopMachine()
        #expect(machine.requestStop(now: 0, child: .notStarted) == [.restore])
    }

    @Test("a second stop request changes nothing")
    func secondRequest() {
        var machine = StopMachine()
        #expect(machine.requestStop(now: 0, child: .alive(identityMatches: true)) == [.sendTerm])
        #expect(machine.requestStop(now: 0.2, child: .alive(identityMatches: true)).isEmpty)
    }
}

@Suite("Deadman")
struct DeadmanTests {
    @Test("expires after 30 min, extends by 15 min, never past 60 min")
    func extendAndCap() {
        var deadman = Deadman(start: 0)
        #expect(!deadman.isExpired(now: 1799))
        #expect(deadman.isExpired(now: 1800))
        deadman.extend()
        #expect(!deadman.isExpired(now: 2699))
        #expect(deadman.isExpired(now: 2700))
        deadman.extend()
        deadman.extend()
        #expect(deadman.deadline == 3600)
    }
}

@Suite("PrefsCompare")
struct PrefsCompareTests {
    let backup: [String: Any] = [
        "UseIceBar": true,
        "ShowOnClick": true,
        "RehideInterval": 15,
        "IceIcon": Data(#"{"name":"Ellipsis","hidden":{"catalog":{"_0":"EllipsisFill"}}}"#.utf8),
        "SULastCheckTime": Date(timeIntervalSince1970: 1_790_000_000),
        "NSStatusItem Preferred Position Ice.ControlItem.Hidden": 465,
    ]

    @Test("the expected dictionary is the backup with the run's values applied")
    func expected() {
        let expected = PrefsCompare.expected(backup: backup, setting: ["UseIceBar": false, "ShowOnScroll": false])
        #expect(PrefsCompare.isEqual(expected["UseIceBar"], false))
        #expect(PrefsCompare.isEqual(expected["ShowOnScroll"], false))
        #expect(PrefsCompare.isEqual(expected["ShowOnClick"], true))
        #expect(expected.count == backup.count + 1)
    }

    @Test("runtime keys may change; settings keys and SU keys may not")
    func allowlist() {
        var actual = backup
        actual["NSStatusItem Preferred Position Ice.ControlItem.Hidden"] = 470
        actual["NSStatusItem Visible Ice.ControlItem.AlwaysHidden"] = false
        actual["NSWindow Frame SettingsWindow"] = "1 2 3 4"
        actual["NSSplitView Subview Frames SettingsWindow"] = ["a"]
        #expect(PrefsCompare.differingKeys(expected: backup, actual: actual, allowedPrefixes: PrefsCompare.runtimeAllowlist).isEmpty)

        actual["ShowOnClick"] = false
        actual["SULastCheckTime"] = Date(timeIntervalSince1970: 1_790_100_000)
        actual["NewKey"] = 1
        actual.removeValue(forKey: "RehideInterval")
        #expect(PrefsCompare.differingKeys(expected: backup, actual: actual, allowedPrefixes: PrefsCompare.runtimeAllowlist) == ["NewKey", "RehideInterval", "SULastCheckTime", "ShowOnClick"])
    }

    @Test("JSON data re-encoded in another key order is equal; changed JSON is not")
    func jsonData() {
        let reordered = Data(#"{"hidden":{"catalog":{"_0":"EllipsisFill"}},"name":"Ellipsis"}"#.utf8)
        let changed = Data(#"{"hidden":{"catalog":{"_0":"DotFill"}},"name":"Dot"}"#.utf8)
        #expect(PrefsCompare.isEqual(backup["IceIcon"], reordered))
        #expect(!PrefsCompare.isEqual(backup["IceIcon"], changed))
        #expect(!PrefsCompare.isEqual(Data([0xFF, 0x00]), Data([0xFF, 0x01])))
        #expect(PrefsCompare.isEqual(Data([0xFF, 0x00]), Data([0xFF, 0x00])))
    }

    @Test("an exact comparison with no allowlist catches every difference")
    func exact() {
        var actual = backup
        #expect(PrefsCompare.differingKeys(expected: backup, actual: actual, allowedPrefixes: []).isEmpty)
        actual["NSStatusItem Preferred Position Ice.ControlItem.Hidden"] = 470
        #expect(PrefsCompare.differingKeys(expected: backup, actual: actual, allowedPrefixes: []) == ["NSStatusItem Preferred Position Ice.ControlItem.Hidden"])
    }
}

@Suite("LogMatcher")
struct LogMatcherTests {
    @Test("only Ice's MenuBarItemManager 'Posting ' lines match")
    func posting() {
        let posting = #"{"subsystem":"com.jordanbaird.Ice","category":"MenuBarItemManager","eventMessage":"Posting leftMouseDown to pid"}"#
        let otherCategory = #"{"subsystem":"com.jordanbaird.Ice","category":"EventTap","eventMessage":"Posting leftMouseDown to pid"}"#
        let otherSubsystem = #"{"subsystem":"org.sparkle-project.Sparkle","category":"MenuBarItemManager","eventMessage":"Posting x"}"#
        let notPrefix = #"{"subsystem":"com.jordanbaird.Ice","category":"MenuBarItemManager","eventMessage":"Not Posting anything"}"#
        #expect(LogMatcher.parse(posting).map(LogMatcher.isPosting) == true)
        #expect(LogMatcher.parse(otherCategory).map(LogMatcher.isPosting) == false)
        #expect(LogMatcher.parse(otherSubsystem).map(LogMatcher.isPosting) == false)
        #expect(LogMatcher.parse(notPrefix).map(LogMatcher.isPosting) == false)
    }

    @Test("malformed lines and the stream's header are ignored")
    func malformed() {
        #expect(LogMatcher.parse("Filtering the log data using \"process == x\"") == nil)
        #expect(LogMatcher.parse(#"{"subsystem":"com.jordanbaird.Ice","#) == nil)
        #expect(LogMatcher.parse("") == nil)
    }

    @Test("the line buffer returns complete lines and keeps a partial one")
    func lineBuffer() {
        var buffer = LineBuffer()
        #expect(buffer.append(Array("one\ntw".utf8)) == ["one"])
        #expect(buffer.append(Array("o\nthree\n".utf8)) == ["two", "three"])
        #expect(buffer.append([]) == [])
    }
}

@Suite("Topology")
struct TopologyTests {
    let bar = BarLine(minX: 0, maxX: 1728, height: 33)

    func read(_ pid: Int32, _ xs: [Double], _ state: ReadState = .ok, y: Double = 4.5) -> ProcessRead {
        ProcessRead(pid: pid, state: state, items: xs.enumerated().map { index, x in
            WatchItem(id: ItemID(pid: pid, child: index), identifier: "", frame: WatchFrame(minX: x, minY: y, width: 24, height: 24), isIce: false)
        })
    }

    func tick(_ processes: [ProcessRead]) -> Tick {
        Tick(duration: 0.03, agentFrames: [], agentState: .ok, processes: processes)
    }

    @Test("the first tick sets the baseline; later joins, misses and parks are recorded")
    func events() {
        var tracker = TopologyTracker(bar: bar)
        #expect(tracker.update(tick([read(10, [1100])])).isEmpty)
        #expect(tracker.update(tick([read(10, [1100]), read(11, [1130])])) == [.joined(ItemID(pid: 11, child: 0))])
        #expect(tracker.update(tick([read(10, [1100]), read(11, [])])) == [.missing(ItemID(pid: 11, child: 0))])
        #expect(tracker.update(tick([read(10, [1100], y: 1105)])) == [.parked(ItemID(pid: 10, child: 0))])
    }

    @Test("a failed read records nothing and forgets nothing")
    func failedRead() {
        var tracker = TopologyTracker(bar: bar)
        #expect(tracker.update(tick([read(10, [1100])])).isEmpty)
        #expect(tracker.update(tick([read(10, [], .failed)])).isEmpty)
        #expect(tracker.update(tick([read(10, [1100])])).isEmpty)
    }

    @Test("a process that is no longer read at all counts as missing")
    func processGone() {
        var tracker = TopologyTracker(bar: bar)
        #expect(tracker.update(tick([read(10, [1100]), read(11, [1130])])).isEmpty)
        #expect(tracker.update(tick([read(10, [1100])])) == [.missing(ItemID(pid: 11, child: 0))])
    }
}
