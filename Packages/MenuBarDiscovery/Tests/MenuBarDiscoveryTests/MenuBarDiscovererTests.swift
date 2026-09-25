import Foundation
import IceCore
import Testing
@testable import MenuBarDiscovery

/// `MenuBarDiscoverer` orchestrates the AX walk (plan section 4.2, T5): every
/// running process including its own, a rotating cursor so a deadline
/// truncation never falls on the same processes twice running, cancellation
/// checked between processes, and origin subtraction + `carryOver` on the
/// way out. Everything here runs against fakes -- no real Accessibility, no
/// real display.
@Suite("MenuBarDiscoverer")
struct MenuBarDiscovererTests {
    @Test("own process is read, not skipped, and its own-identifier records take their divider/visible roles")
    func ownProcessIsRead() async throws {
        let selfProcess = testProcess(pid: 100, isSelf: true)
        let otherProcess = testProcess(pid: 200)
        let apps = FakeRunningApps(allProcesses: [selfProcess, otherProcess], agent: nil)

        let ownRecords = [
            ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: ok(testOwnIdentifiers.visible), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 900, minY: 4.5, width: 20, height: 24))),
            ExtrasRecord(childIndex: 1, role: ok("AXMenuBarItem"), identifier: ok(testOwnIdentifiers.hidden), title: ok(), description: ok(), help: ok(), frame: okFrame(BarRect(minX: 800, minY: 4.5, width: 5, height: 24))),
        ]
        let otherRecords = [extrasRecord(childIndex: 0, identifier: "vz-a", minX: 100)]

        let reader = FakeExtrasReader { process, _ in
            process.pid == selfProcess.pid ? rawRead(process: process, records: ownRecords) : rawRead(process: process, records: otherRecords)
        }

        let discoverer = MenuBarDiscoverer(
            apps: apps, reader: reader, display: FakeDisplay(result: (testBounds, DiscoveryOrigin(x: 0, y: 0))),
            isTrusted: { true }, ownIdentifiers: testOwnIdentifiers, now: { 0 }
        )

        let result = try #require(await discoverer.discover(previous: nil))

        #expect(reader.recordedProcesses.contains { $0.pid == selfProcess.pid })
        #expect(result.set.visibleControlItem?.key.identifier == testOwnIdentifiers.visible)
        #expect(result.set.hiddenDivider?.frame?.minX == 800)
        #expect(result.set.items.map(\.process.pid) == [200])
    }

    @Test("cancellation mid-walk returns nil and stops the reader within one process")
    func cancellationStopsWithinOneProcess() async throws {
        let processes = (0..<10).map { testProcess(pid: Int32(100 + $0)) }
        let apps = FakeRunningApps(allProcesses: processes, agent: nil)

        let readStarted = Box(0)
        let gate = DispatchSemaphore(value: 0)
        let reader = FakeExtrasReader { process, _ in
            readStarted.mutate { $0 += 1 }
            if readStarted.get() == 1 {
                gate.wait()
            }
            return rawRead(process: process)
        }

        let discoverer = MenuBarDiscoverer(
            apps: apps, reader: reader, display: FakeDisplay(result: (testBounds, DiscoveryOrigin(x: 0, y: 0))),
            isTrusted: { true }, ownIdentifiers: testOwnIdentifiers, now: { 0 }
        )

        let task = Task { await discoverer.discover(previous: nil) }
        while readStarted.get() < 1 { await Task.yield() }
        task.cancel()
        try await Task.sleep(nanoseconds: 50_000_000)
        gate.signal()

        let result = await task.value
        #expect(result == nil)
        #expect(reader.callCount == 1)
    }

    @Test("deadline truncates the pass; the next pass rotates to resume where it stopped")
    func deadlineTruncatesAndRotates() async throws {
        let processes = (0..<5).map { testProcess(pid: Int32(100 + $0)) }
        let apps = FakeRunningApps(allProcesses: processes, agent: nil)
        let clock = ManualClock(0)

        let reader = FakeExtrasReader { process, _ in
            clock.advance(by: 0.5)
            return rawRead(process: process)
        }

        let discoverer = MenuBarDiscoverer(
            apps: apps, reader: reader, display: FakeDisplay(result: (testBounds, DiscoveryOrigin(x: 0, y: 0))),
            isTrusted: { true }, ownIdentifiers: testOwnIdentifiers, now: { clock.now() },
            deadline: 2.0
        )

        let first = try #require(await discoverer.discover(previous: nil))
        let firstRead = Set(reader.recordedProcesses.map(\.pid))
        #expect(firstRead == Set([100, 101, 102, 103]))
        #expect(first.nextCursor == 4)
        if case .incomplete(let failedPIDs) = first.set.completeness {
            #expect(failedPIDs.contains(104))
        } else {
            Issue.record("expected an incomplete pass: pid 104 was never attempted")
        }

        let second = try #require(await discoverer.discover(previous: first.set))
        let secondRead = Set(reader.recordedProcesses.map(\.pid)).subtracting(firstRead)
        #expect(!secondRead.isEmpty)
        #expect(firstRead.union(secondRead) == Set(processes.map(\.pid)), "every process must be read at least once across the two passes")
        _ = second
    }

    @MainActor
    @Test("the walk never runs on the main thread")
    func neverRunsOnMainThread() async throws {
        let processes = [testProcess(pid: 100)]
        let apps = FakeRunningApps(allProcesses: processes, agent: nil)
        let reader = FakeExtrasReader { process, _ in rawRead(process: process) }

        let discoverer = MenuBarDiscoverer(
            apps: apps, reader: reader, display: FakeDisplay(result: (testBounds, DiscoveryOrigin(x: 0, y: 0))),
            isTrusted: { true }, ownIdentifiers: testOwnIdentifiers, now: { 0 }
        )

        _ = try #require(await discoverer.discover(previous: nil))
        #expect(reader.mainThreadCalls.isEmpty)
    }

    @Test("the display's origin is subtracted from every AX frame before IceCore sees it")
    func originIsSubtracted() async throws {
        let process = testProcess(pid: 100)
        let apps = FakeRunningApps(allProcesses: [process], agent: nil)
        let records = [extrasRecord(childIndex: 0, identifier: "vz-a", minX: 1828)]
        let reader = FakeExtrasReader { process, _ in rawRead(process: process, records: records) }

        let origin = DiscoveryOrigin(x: 1728, y: 0)
        let discoverer = MenuBarDiscoverer(
            apps: apps, reader: reader, display: FakeDisplay(result: (testBounds, origin)),
            isTrusted: { true }, ownIdentifiers: testOwnIdentifiers, now: { 0 }
        )

        let result = try #require(await discoverer.discover(previous: nil))
        #expect(result.origin.x == 1728)
        #expect(result.set.items.first?.frame?.minX == 100)
    }

    @Test("returns nil when the display has no bar to report")
    func nilWhenNoDisplay() async {
        let apps = FakeRunningApps(allProcesses: [testProcess(pid: 100)], agent: nil)
        let reader = FakeExtrasReader { process, _ in rawRead(process: process) }
        let discoverer = MenuBarDiscoverer(
            apps: apps, reader: reader, display: FakeDisplay(result: nil),
            isTrusted: { true }, ownIdentifiers: testOwnIdentifiers, now: { 0 }
        )
        let result = await discoverer.discover(previous: nil)
        #expect(result == nil)
        #expect(reader.callCount == 0)
    }

    @Test("zero running processes still produces an empty, complete result")
    func zeroProcesses() async throws {
        let apps = FakeRunningApps(allProcesses: [], agent: nil)
        let reader = FakeExtrasReader { process, _ in rawRead(process: process) }
        let discoverer = MenuBarDiscoverer(
            apps: apps, reader: reader, display: FakeDisplay(result: (testBounds, DiscoveryOrigin(x: 0, y: 0))),
            isTrusted: { true }, ownIdentifiers: testOwnIdentifiers, now: { 0 }
        )
        let result = try #require(await discoverer.discover(previous: nil))
        #expect(result.set.items.isEmpty)
        #expect(result.set.completeness == .complete)
        #expect(result.nextCursor == 0)
        #expect(reader.callCount == 0)
    }

    @Test("carryOver is applied: a failed process keeps its previous item, a successful read without the item drops it")
    func carryOverApplied() async throws {
        let survivor = testProcess(pid: 200)
        let droppedProcess = testProcess(pid: 300)
        let apps = FakeRunningApps(allProcesses: [survivor, droppedProcess], agent: nil)

        let firstReader = FakeExtrasReader { process, _ in
            rawRead(process: process, records: [extrasRecord(childIndex: 0, identifier: "vz-\(process.pid)", minX: Double(process.pid))])
        }
        let discovererOne = MenuBarDiscoverer(
            apps: apps, reader: firstReader, display: FakeDisplay(result: (testBounds, DiscoveryOrigin(x: 0, y: 0))),
            isTrusted: { true }, ownIdentifiers: testOwnIdentifiers, now: { 0 }
        )
        let firstResult = try #require(await discovererOne.discover(previous: nil))
        #expect(firstResult.set.items.count == 2)

        let secondReader = FakeExtrasReader { process, _ in
            if process.pid == survivor.pid {
                return RawRead(process: process, extrasError: "cannotComplete", extrasElapsed: 0.24, childrenError: nil, childrenElapsed: nil, records: [], walkInterrupted: false, childCount: 0)
            }
            return rawRead(process: process, records: [])
        }
        let discovererTwo = MenuBarDiscoverer(
            apps: apps, reader: secondReader, display: FakeDisplay(result: (testBounds, DiscoveryOrigin(x: 0, y: 0))),
            isTrusted: { true }, ownIdentifiers: testOwnIdentifiers, now: { 1 }
        )
        let secondResult = try #require(await discovererTwo.discover(previous: firstResult.set))

        #expect(secondResult.set.items.map(\.key.pid) == [survivor.pid])
    }
}
