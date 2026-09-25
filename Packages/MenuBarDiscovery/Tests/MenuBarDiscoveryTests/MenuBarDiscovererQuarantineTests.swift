import Foundation
import IceCore
import Testing
@testable import MenuBarDiscovery

/// `MenuBarDiscoverer` with the responsiveness quarantine and the in-walk
/// deadline (2026-09-25 responsiveness-quarantine plan, T4): quarantined
/// processes are skipped by the rotation and re-probed after it, within the
/// budget left; every read is handed an interrupt that trips on the deadline or
/// on cancellation; a read cut by the deadline moves the cursor so every pass
/// makes progress; the unread tail is built from explicit offsets; and a
/// cancelled pass leaves nothing behind.
@Suite("MenuBarDiscoverer: quarantine and the walk's deadline")
struct MenuBarDiscovererQuarantineTests {
    // MARK: - the quarantine through real passes

    @Test("d1: stalling processes are counted where they are first met, then skipped, listed, and the pass is complete")
    func d1BrowserScenario() async throws {
        let owner = aged(10)
        let stalled = [aged(20), aged(21), aged(22)]
        let fast = (30..<35).map { aged(Int32($0)) }
        let clock = ManualClock(0)
        let reader = FakeExtrasReader { process, _ in
            if stalled.contains(process) { return stall(process) }
            if process == owner { return rawRead(process: process, records: [extrasRecord(childIndex: 0, identifier: "o", minX: 300)]) }
            return quickNo(process)
        }
        let discoverer = makeDiscoverer(processes: [owner] + stalled + fast, reader: reader, clock: clock)

        let first = try #require(await discoverer.discover(previous: nil))

        #expect(first.set.completeness == .incomplete(failedPIDs: [20, 21, 22]))
        #expect(first.quarantined.map(\.pid) == [20, 21, 22])
        #expect(first.set.items.map(\.key.pid) == [10])

        clock.advance(by: 1)
        let callsBefore = reader.callCount
        let second = try #require(await discoverer.discover(previous: first.set))

        #expect(second.set.completeness == .complete)
        #expect(second.quarantined.map(\.pid) == [20, 21, 22])
        #expect(reader.callCount - callsBefore == 6)
        #expect(!reader.recordedProcesses.suffix(6).contains { stalled.contains($0) })
        #expect(second.set.items.map(\.key.pid) == [10])
    }

    @Test("d2: due re-probes run after the rotation; one that stalls again is left out and the pass stays complete")
    func d2ReprobesAfterTheRotation() async throws {
        let stalled = aged(20)
        let fast = (30..<34).map { aged(Int32($0)) }
        let clock = ManualClock(0)
        let reader = FakeExtrasReader { process, _ in process == stalled ? stall(process) : quickNo(process) }
        let discoverer = makeDiscoverer(processes: [stalled] + fast, reader: reader, clock: clock)
        _ = try #require(await discoverer.discover(previous: nil))

        clock.advance(by: 2.5)
        let callsBefore = reader.callCount
        let third = try #require(await discoverer.discover(previous: nil))

        let order = reader.recordedProcesses.dropFirst(callsBefore).map(\.pid)
        #expect(order == [30, 31, 32, 33, 20])
        #expect(third.set.completeness == .complete)
        #expect(third.quarantined.map(\.pid) == [20])
    }

    @Test("d3: a due re-probe that one timeout no longer fits is not started, stays due, and is not failed")
    func d3ReprobesOnlyWithinTheBudget() async throws {
        let stalled = [aged(20), aged(21), aged(22)]
        let fast = (30..<37).map { aged(Int32($0)) }
        let clock = ManualClock(0)
        let reprobing = Box(false)
        let reader = FakeExtrasReader { process, _ in
            guard stalled.contains(process) else { return quickNo(process) }
            if reprobing.get() { clock.advance(by: 0.25) }
            return stall(process)
        }
        let discoverer = makeDiscoverer(processes: stalled + fast, reader: reader, clock: clock, deadline: 0.6)
        _ = try #require(await discoverer.discover(previous: nil))

        reprobing.set(true)
        clock.advance(by: 2.1)
        let callsBefore = reader.callCount
        let second = try #require(await discoverer.discover(previous: nil))

        let reprobed = reader.recordedProcesses.dropFirst(callsBefore).map(\.pid).filter { $0 < 30 }
        #expect(reprobed == [20, 21])
        #expect(second.set.completeness == .complete)
        #expect(second.quarantined.map(\.pid) == [20, 21, 22])

        // 22 was never started, so it is still due: the next pass takes it first.
        clock.advance(by: 0.1)
        let callsThen = reader.callCount
        _ = try #require(await discoverer.discover(previous: nil))
        #expect(reader.recordedProcesses.dropFirst(callsThen).map(\.pid).filter { $0 < 30 }.first == 22)
    }

    @Test("d4: a process that has shown a non-empty snapshot is never quarantined: its stall keeps the pass incomplete and its item is carried")
    func d4SnapshotShownIsExempt() async throws {
        let owner = aged(10)
        let fast = (30..<34).map { aged(Int32($0)) }
        let stalling = Box(false)
        let clock = ManualClock(0)
        let reader = FakeExtrasReader { process, _ in
            guard process == owner else { return quickNo(process) }
            return stalling.get() ? stall(process) : rawRead(process: process, records: [extrasRecord(childIndex: 0, identifier: "o", minX: 300)])
        }
        let discoverer = makeDiscoverer(processes: [owner] + fast, reader: reader, clock: clock)
        let first = try #require(await discoverer.discover(previous: nil))

        stalling.set(true)
        for _ in 0..<3 {
            clock.advance(by: 5)
            let pass = try #require(await discoverer.discover(previous: nil))
            #expect(pass.set.completeness == .incomplete(failedPIDs: [10]))
            #expect(pass.quarantined.isEmpty)
        }
        let carried = try #require(await discoverer.discover(previous: first.set))
        #expect(carried.set.items.map(\.key.pid) == [10])
        #expect(carried.set.items.first?.carriedPasses == 1)
    }

    @Test("d5: a process without a start time is never quarantined: every pass it stalls is incomplete")
    func d5NoStartTimeNoQuarantine() async throws {
        let anonymous = testProcess(pid: 20)
        let fast = (30..<34).map { aged(Int32($0)) }
        let clock = ManualClock(0)
        let reader = FakeExtrasReader { process, _ in process == anonymous ? stall(process) : quickNo(process) }
        let discoverer = makeDiscoverer(processes: [anonymous] + fast, reader: reader, clock: clock)

        for _ in 0..<3 {
            let pass = try #require(await discoverer.discover(previous: nil))
            #expect(pass.set.completeness == .incomplete(failedPIDs: [20]))
            #expect(pass.quarantined.isEmpty)
            clock.advance(by: 5)
        }
        #expect(reader.recordedProcesses.filter { $0 == anonymous }.count == 3)
    }

    @Test("d6: when every read stalls, nothing is quarantined")
    func d6NoWitnessNoQuarantine() async throws {
        let processes = (20..<24).map { aged(Int32($0)) }
        let clock = ManualClock(0)
        let reader = FakeExtrasReader { process, _ in stall(process) }
        let discoverer = makeDiscoverer(processes: processes, reader: reader, clock: clock)

        let first = try #require(await discoverer.discover(previous: nil))
        clock.advance(by: 5)
        let second = try #require(await discoverer.discover(previous: nil))

        #expect(first.quarantined.isEmpty)
        #expect(second.quarantined.isEmpty)
        #expect(second.set.completeness == .incomplete(failedPIDs: [20, 21, 22, 23]))
    }

    @Test("d12: a quarantined process that owns an item in the caller's previous set is read in that very pass")
    func d12PreviousOwnerIsReadAtOnce() async throws {
        let stalled = aged(20)
        let fast = (30..<34).map { aged(Int32($0)) }
        let clock = ManualClock(0)
        let reader = FakeExtrasReader { process, _ in process == stalled ? stall(process) : quickNo(process) }
        let discoverer = makeDiscoverer(processes: [stalled] + fast, reader: reader, clock: clock)
        let first = try #require(await discoverer.discover(previous: nil))
        #expect(first.quarantined.map(\.pid) == [20])

        let previous = ownedSet(by: stalled)
        clock.advance(by: 0.5)
        let callsBefore = reader.callCount
        let second = try #require(await discoverer.discover(previous: previous))

        #expect(reader.recordedProcesses.dropFirst(callsBefore).contains(stalled))
        #expect(second.quarantined.isEmpty)
        #expect(second.set.completeness == .incomplete(failedPIDs: [20]))
    }

    @Test("d14: when every rotation leaves no room for a re-probe, the quarantine lapses at the cap and the process is read, and counted, in the rotation")
    func d14StarvedReprobeLapses() async throws {
        let stalled = aged(20)
        let hog = aged(21)
        let fast = (30..<34).map { aged(Int32($0)) }
        let clock = ManualClock(0)
        let reader = FakeExtrasReader { process, _ in
            // Every pass, one slow-but-answering process eats all but 0.2 s of
            // the 2 s budget, so no re-probe ever fits after the rotation.
            if process == hog { clock.advance(by: 1.8) }
            return process == stalled ? stall(process) : quickNo(process)
        }
        let discoverer = makeDiscoverer(processes: [stalled, hog] + fast, reader: reader, clock: clock)

        let entering = try #require(await discoverer.discover(previous: nil))
        #expect(entering.quarantined.map(\.pid) == [20])
        let entryReadCount = reader.recordedProcesses.filter { $0 == stalled }.count

        // Entered at t = 1.8, due at 3.8, lapses at 33.8: passes at 5 ... 30 skip
        // it and have no room to re-probe it; the pass at 35 reads it again.
        var readAt = [Double]()
        var lapsePass: DiscoveryResult?
        var readsSoFar = entryReadCount
        for start in stride(from: 5.0, through: 40.0, by: 5.0) {
            clock.advance(by: start - clock.now())
            let pass = try #require(await discoverer.discover(previous: nil))
            let reads = reader.recordedProcesses.filter { $0 == stalled }.count
            if reads > readsSoFar {
                readAt.append(start)
                if lapsePass == nil { lapsePass = pass }
            }
            readsSoFar = reads
        }

        #expect(entryReadCount == 1)
        // Read once at 35 and, having re-entered there, skipped again at 40.
        #expect(readAt == [35])
        let lapsed = try #require(lapsePass)
        #expect(lapsed.set.completeness == .incomplete(failedPIDs: [20]))
        #expect(lapsed.quarantined.map(\.pid) == [20])
    }

    @Test("d15: the quarantine judges a whole pass at one instant -- a process is never skipped in the rotation and then left unlisted because it lapsed mid-pass")
    func d15OneInstantPerPass() async throws {
        let stalled = aged(20)
        let hog = aged(21)
        let fast = (30..<34).map { aged(Int32($0)) }
        let clock = ManualClock(0)
        let reader = FakeExtrasReader { process, _ in
            if process == hog { clock.advance(by: 1.8) }
            return process == stalled ? stall(process) : quickNo(process)
        }
        let discoverer = makeDiscoverer(processes: [stalled, hog] + fast, reader: reader, clock: clock)
        _ = try #require(await discoverer.discover(previous: nil))

        // Passes 2.5 s apart, so one of them straddles the moment the
        // quarantine lapses: every pass must still account for the process --
        // read, listed as quarantined, or failed.
        for start in stride(from: 5.0, through: 40.0, by: 2.5) {
            clock.advance(by: start - clock.now())
            let before = reader.recordedProcesses.filter { $0 == stalled }.count
            let pass = try #require(await discoverer.discover(previous: nil))
            let read = reader.recordedProcesses.filter { $0 == stalled }.count > before
            let listed = pass.quarantined.contains(stalled)
            let failed: Bool = { if case .incomplete(let pids) = pass.set.completeness { return pids.contains(20) }; return false }()
            #expect(read || listed || failed, "pass at \(start): the stalled process went unaccounted for")
        }
    }

    // MARK: - the interrupt every read is handed

    @Test("d7: the interrupt trips past the deadline for every read, the first of the pass included")
    func d7InterruptTripsOnTheDeadline() async throws {
        let first = aged(10)
        let clock = ManualClock(0)
        let reader = FakeExtrasReader { process, _ in
            if process == first { clock.advance(by: 2.1) }
            return quickNo(process)
        }
        let discoverer = makeDiscoverer(processes: [first, aged(11)], reader: reader, clock: clock)

        _ = try #require(await discoverer.discover(previous: nil))

        #expect(reader.recordedInterrupts == [true])
    }

    @Test("d7: a re-probe is handed the same interrupt, and it trips past the deadline too")
    func d7ReprobeInterrupt() async throws {
        let stalled = aged(20)
        let fast = (30..<34).map { aged(Int32($0)) }
        let clock = ManualClock(0)
        let reprobing = Box(false)
        let reader = FakeExtrasReader { process, _ in
            guard process == stalled else { return quickNo(process) }
            if reprobing.get() { clock.advance(by: 2.1) }
            return stall(process)
        }
        let discoverer = makeDiscoverer(processes: fast + [stalled], reader: reader, clock: clock)
        _ = try #require(await discoverer.discover(previous: nil))
        #expect(reader.recordedInterrupts.allSatisfy { $0 == false })

        reprobing.set(true)
        clock.advance(by: 2.5)
        _ = try #require(await discoverer.discover(previous: nil))

        #expect(reader.recordedInterrupts.suffix(5) == [false, false, false, false, true])
    }

    @Test("d11: cancelled during the last read -- the interrupt trips, the pass returns nil, and neither the cursor nor the quarantine moves")
    func d11CancelledDuringTheLastRead() async throws {
        let stalled = aged(20)
        let last = aged(40)
        let fast = (30..<34).map { aged(Int32($0)) }
        let clock = ManualClock(0)
        let task = Box<Task<DiscoveryResult?, Never>?>(nil)
        let cancelling = Box(false)
        let reader = FakeExtrasReader { process, _ in
            if process == last, cancelling.get() { cancelOnceKnown(task) }
            return process == stalled ? stall(process) : quickNo(process)
        }
        let discoverer = makeDiscoverer(processes: [stalled] + fast + [last], reader: reader, clock: clock)

        cancelling.set(true)
        let cancelled = Task { await discoverer.discover(previous: nil) }
        task.set(cancelled)
        let cancelledResult = await cancelled.value
        #expect(cancelledResult == nil)
        #expect(reader.recordedInterrupts.last == true)

        // Nothing was stored: 20 was never quarantined, so the next pass reads it
        // in its rotation and it enters only now.
        cancelling.set(false)
        let callsBefore = reader.callCount
        let next = try #require(await discoverer.discover(previous: nil))
        #expect(reader.recordedProcesses.dropFirst(callsBefore).first == stalled)
        #expect(next.set.completeness == .incomplete(failedPIDs: [20]))
    }

    @Test("d11: cancelled during a re-probe -- nil, and the re-probe is still due next pass")
    func d11CancelledDuringAReprobe() async throws {
        let stalled = aged(20)
        let fast = (30..<34).map { aged(Int32($0)) }
        let clock = ManualClock(0)
        let task = Box<Task<DiscoveryResult?, Never>?>(nil)
        let cancelling = Box(false)
        let reader = FakeExtrasReader { process, _ in
            guard process == stalled else { return quickNo(process) }
            if cancelling.get() { cancelOnceKnown(task) }
            return stall(process)
        }
        let discoverer = makeDiscoverer(processes: [stalled] + fast, reader: reader, clock: clock)
        _ = try #require(await discoverer.discover(previous: nil))

        clock.advance(by: 2.5)
        cancelling.set(true)
        let cancelled = Task { await discoverer.discover(previous: nil) }
        task.set(cancelled)
        #expect(await cancelled.value == nil)

        cancelling.set(false)
        clock.advance(by: 0.1)
        let callsBefore = reader.callCount
        let next = try #require(await discoverer.discover(previous: nil))
        // Had the cancelled pass stored its settlement, the re-probe's stall
        // would have pushed the next probe 4 s out, and none would run now.
        #expect(reader.recordedProcesses.dropFirst(callsBefore).last == stalled)
        #expect(next.quarantined.map(\.pid) == [20])
    }

    // MARK: - truncation and progress

    @Test("d8: a first read cut by the deadline moves the cursor past it, so every other process is read")
    func d8ProgressPastACutFirstRead() async throws {
        let slow = aged(10)
        let others = [aged(11), aged(12)]
        let clock = ManualClock(0)
        let reader = FakeExtrasReader { process, _ in
            guard process == slow else { return quickNo(process) }
            clock.advance(by: 2.5)
            return cut(process)
        }
        let discoverer = makeDiscoverer(processes: [slow] + others, reader: reader, clock: clock)

        let first = try #require(await discoverer.discover(previous: nil))
        #expect(first.nextCursor == 1)
        #expect(first.set.completeness == .incomplete(failedPIDs: [10, 11, 12]))

        let second = try #require(await discoverer.discover(previous: first.set))
        // 11 and 12 are read; 10, at offset 2 now, is cut again and becomes the
        // next pass's first, with the whole budget.
        #expect(Set(reader.recordedProcesses.map(\.pid)) == [10, 11, 12])
        #expect(second.nextCursor == 0)
        #expect(second.set.completeness == .incomplete(failedPIDs: [10]))

        let third = try #require(await discoverer.discover(previous: second.set))
        #expect(third.nextCursor == 1)
    }

    @Test("d9: a read cut past the deadline at offset > 0 keeps its failure, the cursor lands on it, and every pid is read once")
    func d9CutLaterKeepsTheCursorOnIt() async throws {
        let first = aged(10)
        let slow = aged(11)
        let rest = [aged(12), aged(13)]
        let clock = ManualClock(0)
        let reader = FakeExtrasReader { process, _ in
            if process == first { return rawRead(process: process, records: [extrasRecord(childIndex: 0, identifier: "a", minX: 300)]) }
            guard process == slow else { return quickNo(process) }
            clock.advance(by: 2.5)
            return cut(process)
        }
        let discoverer = makeDiscoverer(processes: [first, slow] + rest, reader: reader, clock: clock)

        let pass = try #require(await discoverer.discover(previous: nil))

        #expect(pass.nextCursor == 1)
        #expect(pass.set.completeness == .incomplete(failedPIDs: [11, 12, 13]))
        #expect(pass.set.items.map(\.key.pid) == [10])
        #expect(reader.recordedProcesses.map(\.pid) == [10, 11])
    }

    @Test("d10: a skipped process before the truncation point: the tail is built from offsets, and no pid is read twice")
    func d10TailFromOffsets() async throws {
        let a = aged(10)
        let quarantinedProcess = aged(20)
        let b = aged(11)
        let tail = [aged(12), aged(13)]
        let fast = (30..<34).map { aged(Int32($0)) }
        let clock = ManualClock(0)
        let slowing = Box(false)
        let reader = FakeExtrasReader { process, _ in
            if process == quarantinedProcess { return stall(process) }
            if slowing.get(), process == a || process == b { clock.advance(by: 1.0) }
            if process == a { return rawRead(process: process, records: [extrasRecord(childIndex: 0, identifier: "a", minX: 300)]) }
            return quickNo(process)
        }
        let discoverer = makeDiscoverer(processes: [a, quarantinedProcess, b] + tail + fast, reader: reader, clock: clock)
        let first = try #require(await discoverer.discover(previous: nil))
        #expect(first.quarantined.map(\.pid) == [20])

        slowing.set(true)
        clock.advance(by: 0.5)
        let second = try #require(await discoverer.discover(previous: nil))

        #expect(second.set.completeness == .incomplete(failedPIDs: [12, 13] + fast.map(\.pid)))
        #expect(second.set.items.map(\.key.pid) == [10])
        #expect(second.nextCursor == 3)
        #expect(second.quarantined.map(\.pid) == [20])
    }

    @Test("d13: a policy stop before the deadline fails that process and leaves the pass running")
    func d13PolicyStopDoesNotTruncate() async throws {
        let stopped = aged(10)
        let others = [aged(11), aged(12)]
        let clock = ManualClock(0)
        let reader = FakeExtrasReader { process, _ in process == stopped ? cut(process) : quickNo(process) }
        let discoverer = makeDiscoverer(processes: [stopped] + others, reader: reader, clock: clock)

        let pass = try #require(await discoverer.discover(previous: nil))

        #expect(reader.recordedProcesses.map(\.pid) == [10, 11, 12])
        #expect(pass.nextCursor == 0)
        #expect(pass.set.completeness == .incomplete(failedPIDs: [10]))
    }
}

// MARK: - fixtures

/// The monotonic now the discoverer's age gate is judged at (hardening plan H5).
private let uptimeNow = 10_000.0

/// Cancels the task a pass is running in, from inside a fake read. The read runs
/// on the discoverer's own serial queue, never the cooperative pool, so waiting
/// there for the test to have stored the handle blocks nothing it depends on.
private func cancelOnceKnown(_ task: Box<Task<DiscoveryResult?, Never>?>) {
    while task.get() == nil { usleep(1_000) }
    task.get()?.cancel()
}

/// A process old enough for the age gate, with a kernel start time on both clocks.
private func aged(_ pid: Int32) -> ProcessInfoRecord {
    testProcess(pid: pid, startTime: 1_000, startUptime: 1_000)
}

private func makeDiscoverer(processes: [ProcessInfoRecord], reader: FakeExtrasReader, clock: ManualClock, deadline: Double = 2.0) -> MenuBarDiscoverer {
    MenuBarDiscoverer(
        apps: FakeRunningApps(allProcesses: processes, agent: nil), reader: reader,
        display: FakeDisplay(result: (testBounds, DiscoveryOrigin(x: 0, y: 0))),
        isTrusted: { true }, ownIdentifiers: testOwnIdentifiers,
        now: { clock.now() }, uptime: { uptimeNow }, deadline: deadline
    )
}

/// The extras bar held for the full timeout.
private func stall(_ process: ProcessInfoRecord) -> RawRead {
    RawRead(process: process, extrasError: "cannotComplete", extrasElapsed: 0.25, childrenError: nil, childrenElapsed: nil, records: [], walkInterrupted: false, childCount: 0)
}

/// A quick "no extras here", as most processes answer (M5).
private func quickNo(_ process: ProcessInfoRecord) -> RawRead {
    RawRead(process: process, extrasError: "noValue", extrasElapsed: 0.013, childrenError: nil, childrenElapsed: nil, records: [], walkInterrupted: false, childCount: 0)
}

/// A walk stopped part-way, as the live reader returns it when its interrupt
/// trips or the policy says stop: one child read of two.
private func cut(_ process: ProcessInfoRecord) -> RawRead {
    RawRead(process: process, extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: [extrasRecord(childIndex: 0, identifier: "s", minX: 500)], walkInterrupted: true, childCount: 2)
}

/// A previous set in which `process` owns one item.
private func ownedSet(by process: ProcessInfoRecord) -> DiscoveredItemSet {
    let item = DiscoveredItem(
        key: ItemKey(namespace: process.bundleID ?? "", identifier: "x", pid: process.pid, childIndex: nil), basis: .declared,
        process: process, frame: BarRect(minX: 300, minY: 4.5, width: 24, height: 24), position: .onBar,
        title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
    )
    return DiscoveredItemSet(items: [item], visibleControlItem: nil, hiddenDivider: nil, alwaysHiddenDivider: nil, ownRead: .ok, systemElements: [], dropped: [], completeness: .complete)
}
