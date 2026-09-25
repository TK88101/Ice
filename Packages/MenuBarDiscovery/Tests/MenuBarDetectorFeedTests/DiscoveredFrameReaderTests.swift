import Darwin
import Testing
import IceCore
import MenuBarCapture
import MenuBarDiscovery
@testable import MenuBarDetectorFeed

/// `DiscoveredFrameReader` turns discovery's own AX seams into a
/// `MenuBarAXReading` the frozen detector can read from (plan section 4.3):
/// decode each requested id, read its pid once, match the trimmed identifier,
/// hand back the AX frame minus the display origin and trimmed by D15.
@Suite("DiscoveredFrameReader")
struct DiscoveredFrameReaderTests {
    static let agentPID: pid_t = 999

    private func makeReader(
        extras: FakeExtrasReader,
        agent: pid_t? = agentPID,
        processes: [ProcessInfoRecord] = [],
        origin: DiscoveryOrigin = DiscoveryOrigin(x: 0, y: 0),
        clock: Box<Double> = Box(0)
    ) -> DiscoveredFrameReader {
        DiscoveredFrameReader(
            extras: extras,
            apps: FakeRunningApps(allProcesses: processes, agent: agent),
            origin: origin,
            now: { clock.get() },
            deadline: 2.0
        )
    }

    /// A working extras reader: the agent pid always answers with one usable
    /// frame (so "agent unreadable" is an opt-in failure per test), and
    /// `itemHandler` answers everything else.
    private func makeExtras(agentFrameMinX: Double = 900, itemHandler: @escaping @Sendable (ProcessInfoRecord, Double) -> RawRead) -> FakeExtrasReader {
        FakeExtrasReader { process, timeout in
            if process.pid == Self.agentPID {
                return readerRawRead(process: process, records: [readerExtrasRecord(childIndex: 0, identifier: "", minX: agentFrameMinX)])
            }
            return itemHandler(process, timeout)
        }
    }

    @Test("a key for the second child of its pid resolves to that child's trimmed, origin-subtracted frame")
    func secondChildResolves() {
        let key = ItemKey(namespace: "com.example.p501", identifier: "beta", pid: 501, childIndex: nil)
        let extras = makeExtras { process, _ in
            readerRawRead(process: process, records: [
                readerExtrasRecord(childIndex: 0, identifier: "alpha", minX: 100),
                readerExtrasRecord(childIndex: 1, identifier: "beta", minX: 200),
            ])
        }
        let reader = makeReader(extras: extras, processes: [readerTestProcess(pid: 501)])

        let snapshot = reader.read(items: [key.encoded: 501])

        #expect(snapshot?.itemFrames[key.encoded] == ItemFrame(id: key.encoded, minX: 201, minY: 4.5, width: 22, height: 24))
    }

    @Test("before the sample's deadline no read is cut short: the agent's and the keyed pid's interrupts both say no")
    func noInterruptBeforeTheDeadline() {
        let key = ItemKey(namespace: "com.example.p501", identifier: "beta", pid: 501, childIndex: nil)
        let extras = makeExtras { process, _ in
            readerRawRead(process: process, records: [readerExtrasRecord(childIndex: 0, identifier: "beta", minX: 200)])
        }
        let reader = makeReader(extras: extras, processes: [readerTestProcess(pid: 501)])

        _ = reader.read(items: [key.encoded: 501])

        #expect(extras.interrupts == [false, false])
    }

    @Test("only AXMenuBarItem records are matched, as ItemCatalog keys them: another empty-identifier child does not hide an .unnamed key")
    func nonItemRolesAreNotMatched() {
        let key = ItemKey(namespace: "com.example.p509", identifier: "", pid: 509, childIndex: nil)
        let extras = makeExtras { process, _ in
            readerRawRead(process: process, records: [
                readerExtrasRecord(childIndex: 0, identifier: "", minX: 300),
                readerExtrasRecord(childIndex: 1, identifier: "", minX: 340, role: "AXGroup"),
            ])
        }
        let reader = makeReader(extras: extras, processes: [readerTestProcess(pid: 509)])

        let snapshot = reader.read(items: [key.encoded: 509])

        #expect(snapshot?.itemFrames[key.encoded]?.minX == 301)
    }

    @Test("a positional key is absent, and the reader is never called for its pid")
    func positionalKeyIsAbsentAndUncalled() {
        let key = ItemKey(namespace: "com.example.p502", identifier: "dup", pid: 502, childIndex: 0)
        let extras = makeExtras { process, _ in
            Issue.record("must not read a positional item's pid: \(process.pid)")
            return readerRawRead(process: process)
        }
        let reader = makeReader(extras: extras, processes: [readerTestProcess(pid: 502)])

        let snapshot = reader.read(items: [key.encoded: 502])

        #expect(snapshot?.itemFrames.isEmpty == true)
        #expect(extras.callCount == 1, "only the agent pid should have been read")
    }

    @Test("an identifier present twice in its process is absent")
    func duplicateIdentifierIsAbsent() {
        let key = ItemKey(namespace: "com.example.p503", identifier: "dup", pid: 503, childIndex: nil)
        let extras = makeExtras { process, _ in
            readerRawRead(process: process, records: [
                readerExtrasRecord(childIndex: 0, identifier: "dup", minX: 100),
                readerExtrasRecord(childIndex: 1, identifier: "dup", minX: 200),
            ])
        }
        let reader = makeReader(extras: extras, processes: [readerTestProcess(pid: 503)])

        let snapshot = reader.read(items: [key.encoded: 503])

        #expect(snapshot?.itemFrames[key.encoded] == nil)
    }

    @Test("an identifier with surrounding whitespace matches its trimmed key")
    func whitespaceIdentifierMatchesTrimmed() {
        let key = ItemKey(namespace: "com.example.p504", identifier: "gamma", pid: 504, childIndex: nil)
        let extras = makeExtras { process, _ in
            readerRawRead(process: process, records: [
                readerExtrasRecord(childIndex: 0, identifier: "  gamma \n", minX: 300),
            ])
        }
        let reader = makeReader(extras: extras, processes: [readerTestProcess(pid: 504)])

        let snapshot = reader.read(items: [key.encoded: 504])

        #expect(snapshot?.itemFrames[key.encoded] != nil)
    }

    @Test("a sibling with no frame does not affect the others")
    func siblingWithoutFrameIsHarmless() {
        let x = ItemKey(namespace: "com.example.p505", identifier: "x", pid: 505, childIndex: nil)
        let y = ItemKey(namespace: "com.example.p505", identifier: "y", pid: 505, childIndex: nil)
        let extras = makeExtras { process, _ in
            readerRawRead(process: process, records: [
                readerExtrasRecord(childIndex: 0, identifier: "x", minX: 10),
                readerExtrasRecord(childIndex: 1, identifier: "y", minX: 20, hasFrame: false),
            ])
        }
        let reader = makeReader(extras: extras, processes: [readerTestProcess(pid: 505)])

        let snapshot = reader.read(items: [x.encoded: 505, y.encoded: 505])

        #expect(snapshot?.itemFrames[x.encoded] != nil)
        #expect(snapshot?.itemFrames[y.encoded] == nil)
    }

    @Test("a vanished item -- no matching identifier at all -- is absent")
    func vanishedItemIsAbsent() {
        let key = ItemKey(namespace: "com.example.p506", identifier: "gone", pid: 506, childIndex: nil)
        let extras = makeExtras { process, _ in
            readerRawRead(process: process, records: [
                readerExtrasRecord(childIndex: 0, identifier: "still-here", minX: 10),
            ])
        }
        let reader = makeReader(extras: extras, processes: [readerTestProcess(pid: 506)])

        let snapshot = reader.read(items: [key.encoded: 506])

        #expect(snapshot?.itemFrames[key.encoded] == nil)
    }

    // MARK: - H1: a keyed read that cannot be trusted fails the whole snapshot
    //
    // The frozen contract (`MenuBarAXReading.read`) says an absent id is a
    // *successful* read that found nothing. Before H1 a `.failed` read left its
    // keys absent -- a fabricated disappearance (characterized green on the old
    // code first; hardening plan H1).

    @Test("f1: a keyed pid whose read is .failed makes the whole snapshot nil")
    func failedKeyedReadIsNil() {
        let key = ItemKey(namespace: "com.example.p510", identifier: "item", pid: 510, childIndex: nil)
        let extras = makeExtras { process, _ in readerFailedRawRead(process: process) }
        let reader = makeReader(extras: extras, processes: [readerTestProcess(pid: 510)])

        #expect(reader.read(items: [key.encoded: 510]) == nil)
    }

    @Test("f2: a keyed pid whose read is .none (no extras bar) is an honest absence, not a failure")
    func noneKeyedReadIsAbsent() {
        let key = ItemKey(namespace: "com.example.p511", identifier: "item", pid: 511, childIndex: nil)
        let extras = makeExtras { process, _ in
            RawRead(process: process, extrasError: "noValue", extrasElapsed: 0.01, childrenError: nil, childrenElapsed: nil, records: [], walkInterrupted: false, childCount: 0)
        }
        let reader = makeReader(extras: extras, processes: [readerTestProcess(pid: 511)])

        let snapshot = reader.read(items: [key.encoded: 511])

        #expect(snapshot != nil)
        #expect(snapshot?.itemFrames[key.encoded] == nil)
    }

    @Test("f5: keyed pids are read in ascending pid order, after the agent")
    func keyedPIDsAreReadInSortedOrder() {
        let pids: [Int32] = [530, 521, 527, 523, 529, 522, 526, 524]
        let items = Dictionary(uniqueKeysWithValues: pids.map { pid in
            (ItemKey(namespace: "com.example.p\(pid)", identifier: "item", pid: pid, childIndex: nil).encoded, pid)
        })
        let extras = makeExtras { process, _ in readerRawRead(process: process) }
        let reader = makeReader(extras: extras, processes: pids.map { readerTestProcess(pid: $0) })

        _ = reader.read(items: items)

        #expect(extras.calls.map(\.pid) == [Self.agentPID] + pids.sorted())
    }

    @Test("f3: a first keyed pid slow past the deadline -> nil, and the second pid is never read")
    func slowFirstPIDPastTheDeadlineIsNil() {
        let first = ItemKey(namespace: "com.example.p541", identifier: "item", pid: 541, childIndex: nil)
        let second = ItemKey(namespace: "com.example.p542", identifier: "item", pid: 542, childIndex: nil)
        let clock = Box(0.0)
        let extras = makeExtras { process, _ in
            if process.pid == 542 { Issue.record("the pid after the deadline must not be read") }
            clock.set(clock.get() + 2.5)
            return readerRawRead(process: process, records: [readerExtrasRecord(childIndex: 0, identifier: "item", minX: 100)])
        }
        let reader = makeReader(extras: extras, processes: [readerTestProcess(pid: 541), readerTestProcess(pid: 542)], clock: clock)

        #expect(reader.read(items: [first.encoded: 541, second.encoded: 542]) == nil)
        #expect(extras.calls.map(\.pid) == [Self.agentPID, 541])
    }

    @Test("f4: a keyed read's interrupt says no before the sample's deadline and yes at it")
    func keyedInterruptTripsAtTheDeadline() {
        let key = ItemKey(namespace: "com.example.p551", identifier: "item", pid: 551, childIndex: nil)
        let clock = Box(0.0)
        let extras = PollingExtrasReader { process in
            guard process.pid == 551 else { return readerRawRead(process: process) }
            clock.set(2.0)
            return RawRead(process: process, extrasError: "success", extrasElapsed: 0.01, childrenError: "success", childrenElapsed: 0.01, records: [], walkInterrupted: true, childCount: 1)
        }
        let reader = DiscoveredFrameReader(
            extras: extras,
            apps: FakeRunningApps(allProcesses: [readerTestProcess(pid: 551)], agent: Self.agentPID),
            origin: DiscoveryOrigin(x: 0, y: 0),
            now: { clock.get() },
            deadline: 2.0
        )

        #expect(reader.read(items: [key.encoded: 551]) == nil)
        #expect(extras.polls == [
            PollingExtrasReader.Poll(pid: Self.agentPID, before: false, after: false),
            PollingExtrasReader.Poll(pid: 551, before: false, after: true),
        ])
    }

    @Test("f4b: the agent's read is never cut: with no keys, one that outlasts the deadline still yields a snapshot")
    func agentReadIsNeverCut() {
        let clock = Box(0.0)
        let extras = PollingExtrasReader { process in
            clock.set(3.0)
            return readerRawRead(process: process)
        }
        let reader = DiscoveredFrameReader(
            extras: extras,
            apps: FakeRunningApps(allProcesses: [], agent: Self.agentPID),
            origin: DiscoveryOrigin(x: 0, y: 0),
            now: { clock.get() },
            deadline: 2.0
        )

        #expect(reader.read(items: [:]) != nil)
        #expect(extras.polls == [PollingExtrasReader.Poll(pid: Self.agentPID, before: false, after: false)])
    }

    @Test("no agent pid -> nil")
    func noAgentPIDIsNil() {
        let extras = FakeExtrasReader { process, _ in
            Issue.record("must not be called when there is no agent pid: \(process.pid)")
            return readerRawRead(process: process)
        }
        let reader = makeReader(extras: extras, agent: nil, processes: [])

        #expect(reader.read(items: [:]) == nil)
    }

    @Test("the agent's read failing (.failed) -> nil")
    func agentReadFailingIsNil() {
        let extras = FakeExtrasReader { process, _ in
            readerFailedRawRead(process: process)
        }
        let reader = makeReader(extras: extras, processes: [])

        #expect(reader.read(items: [:]) == nil)
    }

    @Test("the agent's read reporting .none (a real, empty answer) is not a failure -- empty agent frames, not nil")
    func agentReadNoneIsEmptyNotNil() {
        let extras = FakeExtrasReader { process, _ in
            RawRead(process: process, extrasError: "noValue", extrasElapsed: 0.01, childrenError: nil, childrenElapsed: nil, records: [], walkInterrupted: false, childCount: 0)
        }
        let reader = makeReader(extras: extras, processes: [])

        let snapshot = reader.read(items: [:])

        #expect(snapshot?.agentFrames.isEmpty == true)
    }

    @Test("the display origin is subtracted from both item and agent frames")
    func originIsSubtracted() {
        let key = ItemKey(namespace: "com.example.p507", identifier: "item", pid: 507, childIndex: nil)
        let extras = makeExtras(agentFrameMinX: 900) { process, _ in
            readerRawRead(process: process, records: [
                readerExtrasRecord(childIndex: 0, identifier: "item", minX: 200),
            ])
        }
        let reader = makeReader(extras: extras, processes: [readerTestProcess(pid: 507)], origin: DiscoveryOrigin(x: 50, y: 5))

        let snapshot = reader.read(items: [key.encoded: 507])

        #expect(snapshot?.itemFrames[key.encoded] == ItemFrame(id: key.encoded, minX: 151, minY: -0.5, width: 22, height: 24))
        #expect(snapshot?.agentFrames.first?.minX == 850)
    }
}
