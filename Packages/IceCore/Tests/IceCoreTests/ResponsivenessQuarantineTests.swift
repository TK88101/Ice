import Testing
@testable import IceCore

/// Pins the responsiveness quarantine (2026-09-25 responsiveness-quarantine
/// plan, sections 3.1-3.5, T1): who may enter it, what counts as having shown
/// extras, how a quarantined identity is skipped, re-probed and lifted, and that
/// identity is `(pid, startTime)` -- never the pid alone.
@Suite("ResponsivenessQuarantine")
struct ResponsivenessQuarantineTests {
    // MARK: - identity

    @Test("an identity needs a start time; without one there is none")
    func identityNeedsStartTime() {
        #expect(ProcessIdentity(proc(1, start: nil)) == nil)
        #expect(ProcessIdentity(proc(1, start: 500)) == ProcessIdentity(proc(1, start: 500)))
        #expect(ProcessIdentity(proc(1, start: 500)) != ProcessIdentity(proc(1, start: 501)))
    }

    @Test("the context takes the previous set's owners, the visible control item's included, by identity")
    func contextTakesPreviousOwners() throws {
        let owner = proc(3, start: oldStart)
        let own = proc(4, start: oldStart, isSelf: true)
        let anonymous = proc(5, start: nil)
        let previous = fixtureSet(
            items: [item(owner), item(anonymous)],
            visibleControlItem: item(own)
        )

        let context = QuarantineContext(agentPID: nil, previous: previous, wallNow: wallNow)

        #expect(context.previousOwners == [try identity(owner), try identity(own)])
        #expect(QuarantineContext(agentPID: nil, previous: nil, wallNow: wallNow).previousOwners.isEmpty)
    }

    // MARK: - entry (q1, q2, q3)

    @Test("q1: an old, identified, unexempt process that stalls on its extras bar while fast answers dominate is counted AND enters")
    func q1StallEnters() throws {
        let stalled = proc(7, start: oldStart)
        let alsoStalled = proc(3, start: oldStart)
        let reads = [stall(stalled), stall(alsoStalled)] + fastReads(5)

        let settled = ResponsivenessQuarantine().settle(processes: processes(reads), reads: reads, reprobes: [], context: context(), now: 100)

        #expect(settled.admitted == reads)
        let entry = try #require(settled.quarantine.entries[try identity(stalled)])
        #expect(entry == ResponsivenessQuarantine.Entry(backoff: 2, nextProbeAt: 102))
        #expect(settled.quarantined == [alsoStalled, stalled])
    }

    @Test("q2: each entry condition alone keeps the stalled process out", arguments: EntryBlocker.allCases)
    func q2EachConditionIsNecessary(blocker: EntryBlocker) {
        let scenario = blocker.scenario()

        let settled = scenario.quarantine.settle(
            processes: processes(scenario.reads), reads: scenario.reads, reprobes: [], context: scenario.context, now: 100
        )

        #expect(settled.quarantine.entries.isEmpty)
        #expect(settled.quarantined.isEmpty)
        #expect(settled.admitted == scenario.reads)
    }

    @Test("q3: only an extras-bar timeout is a trigger", arguments: NonTrigger.allCases)
    func q3OnlyTheExtrasBarTimeoutTriggers(shape: NonTrigger) {
        let reads = [shape.read(proc(7, start: oldStart))] + fastReads(3)

        let settled = ResponsivenessQuarantine().settle(processes: processes(reads), reads: reads, reprobes: [], context: context(), now: 100)

        #expect(settled.quarantine.entries.isEmpty)
        #expect(settled.admitted == reads)
    }

    // MARK: - narrowness (q4, q5)

    @Test("q4: a quick no, a decline or an empty children list never counts as having shown extras")
    func q4NarrowDefinition() throws {
        let process = proc(7, start: oldStart)
        var quarantine = ResponsivenessQuarantine()
        for shape in [read(process, extrasError: "noValue"), read(process, extrasError: "cannotComplete", extrasElapsed: 0.02), read(process, childCount: 0)] {
            let reads = [shape] + fastReads(3)
            quarantine = quarantine.settle(processes: processes(reads), reads: reads, reprobes: [], context: context(), now: 100).quarantine
        }
        #expect(quarantine.snapshotShown.isEmpty)

        let reads = [stall(process)] + fastReads(3)
        let settled = quarantine.settle(processes: processes(reads), reads: reads, reprobes: [], context: context(), now: 110)

        #expect(settled.quarantine.entries[try identity(process)] != nil)
    }

    @Test("q5: a non-empty snapshot exempts the identity even when that read then failed")
    func q5FailedReadWithChildrenStillExempts() throws {
        let interrupted = proc(7, start: oldStart)
        let partial = proc(8, start: oldStart)
        let first = [
            read(interrupted, childCount: 2, walkInterrupted: true),
            read(partial, childCount: 2, records: [record(0)]),
        ] + fastReads(3)
        #expect(ReadClassifier.outcome(first[0]) == .failed(.walkInterrupted))
        #expect(ReadClassifier.outcome(first[1]) == .failed(.partialWalk(childCount: 2, records: 1)))

        let shown = ResponsivenessQuarantine().settle(processes: processes(first), reads: first, reprobes: [], context: context(), now: 100).quarantine
        #expect(shown.snapshotShown == [try identity(interrupted), try identity(partial)])

        let second = [stall(interrupted), stall(partial)] + fastReads(5)
        let settled = shown.settle(processes: processes(second), reads: second, reprobes: [], context: context(), now: 105)

        #expect(settled.quarantine.entries.isEmpty)
        #expect(settled.admitted == second)
    }

    // MARK: - identity is (pid, startTime) (q6, q12)

    @Test("q6: a new process at a reused pid is neither skipped nor exempted by the old one's history")
    func q6MatchingIsByIdentity() throws {
        let old = proc(7, start: oldStart)
        let reused = proc(7, start: oldStart + 5)
        let quarantine = ResponsivenessQuarantine(
            entries: [try identity(old): .init(backoff: 2, nextProbeAt: 500)],
            snapshotShown: [try identity(old)]
        )

        #expect(!quarantine.isSkipped(reused, context: context()))

        let reads = [stall(reused)] + fastReads(3)
        let settled = quarantine.settle(processes: processes(reads), reads: reads, reprobes: [], context: context(), now: 100)

        #expect(settled.quarantine.entries.keys.map(\.startTime) == [oldStart + 5])
        #expect(settled.quarantine.snapshotShown.isEmpty)
    }

    @Test("q12: identities no longer enumerated are pruned from both the entries and the snapshot memory")
    func q12Pruning() throws {
        let gone = try #require(ProcessIdentity(proc(9, start: oldStart)))
        let quarantine = ResponsivenessQuarantine(entries: [gone: .init(backoff: 4, nextProbeAt: 500)], snapshotShown: [gone])
        let reads = fastReads(3)

        let settled = quarantine.settle(processes: processes(reads), reads: reads, reprobes: [], context: context(), now: 100)

        #expect(settled.quarantine == ResponsivenessQuarantine())
        #expect(settled.quarantined.isEmpty)
    }

    // MARK: - lifecycle (q7 - q11, q13, q14)

    @Test("q7: a quarantined identity that is not due is skipped, listed, untouched and never failed")
    func q7SkippedWhileNotDue() throws {
        let process = proc(7, start: oldStart)
        let entry = ResponsivenessQuarantine.Entry(backoff: 4, nextProbeAt: 104)
        let quarantine = ResponsivenessQuarantine(entries: [try identity(process): entry])
        let reads = fastReads(3)

        #expect(quarantine.isSkipped(process, context: context()))
        #expect(quarantine.dueReprobes(among: [process], context: context(), now: 103.9).isEmpty)

        let settled = quarantine.settle(processes: [process] + processes(reads), reads: reads, reprobes: [], context: context(), now: 103.9)

        #expect(settled.quarantine.entries[try identity(process)] == entry)
        #expect(settled.quarantined == [process])
        #expect(settled.admitted == reads)
    }

    @Test("q8: a re-probe that stalls again stays out of the pass, its backoff doubling to the cap")
    func q8BackoffDoublesToTheCap() throws {
        let process = proc(7, start: oldStart)
        let identity = try identity(process)
        var quarantine = ResponsivenessQuarantine(entries: [identity: .init(backoff: 2, nextProbeAt: 2)])
        var now = 2.0
        var backoffs = [Double]()
        for _ in 0..<5 {
            let fast = fastReads(3)
            let settled = quarantine.settle(processes: [process] + processes(fast), reads: fast, reprobes: [stall(process)], context: context(), now: now)
            #expect(settled.admitted == fast)
            #expect(settled.quarantined == [process])
            let entry = try #require(settled.quarantine.entries[identity])
            #expect(entry.nextProbeAt == now + entry.backoff)
            backoffs.append(entry.backoff)
            quarantine = settled.quarantine
            now = entry.nextProbeAt
        }
        #expect(backoffs == [4, 8, 16, 30, 30])
    }

    @Test("q9: a re-probe that answers lifts the quarantine and is admitted; a later stall re-enters afresh")
    func q9AnswerLiftsAndReentryStartsOver() throws {
        let process = proc(7, start: oldStart)
        let identity = try identity(process)
        let quarantine = ResponsivenessQuarantine(entries: [identity: .init(backoff: 16, nextProbeAt: 50)])
        let answer = read(process, extrasError: "noValue")
        let fast = fastReads(3)

        let lifted = quarantine.settle(processes: [process] + processes(fast), reads: fast, reprobes: [answer], context: context(), now: 50)

        #expect(lifted.quarantine.entries.isEmpty)
        #expect(lifted.admitted == fast + [answer])
        #expect(lifted.quarantined.isEmpty)

        let reads = [stall(process)] + fastReads(3)
        let reentered = lifted.quarantine.settle(processes: processes(reads), reads: reads, reprobes: [], context: context(), now: 60)

        #expect(reentered.quarantine.entries[identity] == .init(backoff: 2, nextProbeAt: 62))
    }

    @Test("q10: a re-probe that answers its extras bar and then fails is lifted and counted as the failure it is")
    func q10OtherFailureLiftsAndCounts() throws {
        let process = proc(7, start: oldStart)
        let identity = try identity(process)
        let quarantine = ResponsivenessQuarantine(entries: [identity: .init(backoff: 2, nextProbeAt: 50)])
        let childrenTimeout = read(process, childrenError: "cannotComplete", childrenElapsed: 0.21)
        #expect(ReadClassifier.outcome(childrenTimeout) == .failed(.timedOut(call: "children")))
        let fast = fastReads(3)

        let settled = quarantine.settle(processes: [process] + processes(fast), reads: fast, reprobes: [childrenTimeout], context: context(), now: 50)

        #expect(settled.quarantine.entries.isEmpty)
        #expect(settled.admitted.contains(childrenTimeout))
    }

    @Test("q11: a re-probe that hands over children makes the identity exempt from then on")
    func q11ReprobeWithChildrenExempts() throws {
        let process = proc(7, start: oldStart)
        let identity = try identity(process)
        let quarantine = ResponsivenessQuarantine(entries: [identity: .init(backoff: 2, nextProbeAt: 50)])
        let items = read(process, records: [record(0)])
        let fast = fastReads(3)

        let settled = quarantine.settle(processes: [process] + processes(fast), reads: fast, reprobes: [items], context: context(), now: 50)

        #expect(settled.quarantine.snapshotShown == [identity])
        #expect(settled.admitted.contains(items))

        let reads = [stall(process)] + fastReads(3)
        #expect(settled.quarantine.settle(processes: processes(reads), reads: reads, reprobes: [], context: context(), now: 60).quarantine.entries.isEmpty)
    }

    @Test("q13: an identity that becomes exempt while quarantined is read in that very pass and its entry is dropped")
    func q13ExemptWhileQuarantined() throws {
        let process = proc(7, start: oldStart)
        let identity = try identity(process)
        let quarantine = ResponsivenessQuarantine(entries: [identity: .init(backoff: 8, nextProbeAt: 500)])
        let exempting = QuarantineContext(agentPID: nil, previousOwners: [identity], wallNow: wallNow)

        #expect(!quarantine.isSkipped(process, context: exempting))
        #expect(quarantine.dueReprobes(among: [process], context: exempting, now: 600).isEmpty)

        let reads = [stall(process)] + fastReads(3)
        let settled = quarantine.settle(processes: processes(reads), reads: reads, reprobes: [], context: exempting, now: 100)

        #expect(settled.quarantine.entries.isEmpty)
        #expect(settled.admitted == reads)
        #expect(settled.quarantined.isEmpty)
    }

    @Test("q14: due re-probes come oldest due first, then by pid; the not-yet-due are left out")
    func q14DueOrder() throws {
        let a = proc(9, start: oldStart)
        let b = proc(7, start: oldStart)
        let c = proc(4, start: oldStart)
        let later = proc(2, start: oldStart)
        let quarantine = ResponsivenessQuarantine(entries: [
            try identity(a): .init(backoff: 4, nextProbeAt: 5),
            try identity(b): .init(backoff: 2, nextProbeAt: 3),
            try identity(c): .init(backoff: 2, nextProbeAt: 3),
            try identity(later): .init(backoff: 2, nextProbeAt: 6),
        ])

        let due = quarantine.dueReprobes(among: [a, b, c, later, proc(1, start: oldStart)], context: context(), now: 5)

        #expect(due.map(\.pid) == [4, 7, 9])
    }

    // MARK: - startTime in the record's conformances (q15)

    @Test("q15: startTime takes part in the record's equality, and carry-over's identity check ignores it")
    func q15StartTimeConformances() {
        let before = ProcessInfoRecord(pid: 7, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 10, isSelf: false, startTime: 1)
        let after = ProcessInfoRecord(pid: 7, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 10, isSelf: false, startTime: 2)
        #expect(before != after)
        #expect(Set([before, after]).count == 2)
        #expect(ProcessInfoRecord(pid: 7, bundleID: nil, localizedName: nil, executableName: nil, launchTime: nil, isSelf: false).startTime == nil)

        let previousItem = item(before)
        let current = fixtureSet(items: [], staleProcesses: [7: after], completeness: .incomplete(failedPIDs: [7]))

        let carried = ItemCatalog.carryOver(previous: fixtureSet(items: [previousItem]), current: current, now: 5)

        #expect(carried.items.map(\.key) == [previousItem.key])
    }
}

// MARK: - q2 / q3 scenarios

/// One entry condition missing at a time, so each is shown to be necessary.
enum EntryBlocker: CaseIterable, CustomTestStringConvertible {
    case noStartTime, tooYoung, isSelf, agent, snapshotShown, previousOwner, witnessesNotAMajority, witnessTooSlow, onlyNotAttempted

    var testDescription: String { "\(self)" }

    func scenario() -> (quarantine: ResponsivenessQuarantine, reads: [RawRead], context: QuarantineContext) {
        let old = proc(7, start: oldStart)
        let oldIdentity = ProcessIdentity(old)!
        switch self {
        case .noStartTime:
            return (.init(), [stall(proc(7, start: nil))] + fastReads(3), context())
        case .tooYoung:
            return (.init(), [stall(proc(7, start: wallNow - 59))] + fastReads(3), context())
        case .isSelf:
            return (.init(), [stall(proc(7, start: oldStart, isSelf: true))] + fastReads(3), context())
        case .agent:
            return (.init(), [stall(old)] + fastReads(3), QuarantineContext(agentPID: 7, previousOwners: [], wallNow: wallNow))
        case .snapshotShown:
            return (.init(snapshotShown: [oldIdentity]), [stall(old)] + fastReads(3), context())
        case .previousOwner:
            return (.init(), [stall(old)] + fastReads(3), QuarantineContext(agentPID: nil, previousOwners: [oldIdentity], wallNow: wallNow))
        case .witnessesNotAMajority:
            return (.init(), [stall(old), stall(proc(8, start: oldStart))] + fastReads(2), context())
        case .witnessTooSlow:
            return (.init(), [stall(old)] + fastReads(3, elapsed: 0.06), context())
        case .onlyNotAttempted:
            let unread = (0..<3).map { read(proc(Int32(50 + $0), start: oldStart), extrasError: "notAttempted", extrasElapsed: 0, childrenError: nil, childrenElapsed: nil) }
            return (.init(), [stall(old)] + unread, context())
        }
    }
}

/// Reads that fail, or decline, without stalling on the extras bar.
enum NonTrigger: CaseIterable, CustomTestStringConvertible {
    case childrenTimeout, extrasUnexpectedError, walkInterrupted, partialWalk, fastDecline

    var testDescription: String { "\(self)" }

    func read(_ process: ProcessInfoRecord) -> RawRead {
        switch self {
        case .childrenTimeout:
            return quarantineRead(process, childrenError: "cannotComplete", childrenElapsed: 0.21)
        case .extrasUnexpectedError:
            return quarantineRead(process, extrasError: "failure", extrasElapsed: 0.21, childrenError: nil, childrenElapsed: nil)
        case .walkInterrupted:
            return quarantineRead(process, childCount: 0, walkInterrupted: true)
        case .partialWalk:
            return quarantineRead(process, childCount: 1)
        case .fastDecline:
            return quarantineRead(process, extrasError: "cannotComplete", extrasElapsed: 0.02, childrenError: nil, childrenElapsed: nil)
        }
    }
}

// MARK: - fixtures

private let wallNow = 10_000.0
private let oldStart = 1_000.0

private func identity(_ process: ProcessInfoRecord) throws -> ProcessIdentity {
    try #require(ProcessIdentity(process))
}

private func context() -> QuarantineContext {
    QuarantineContext(agentPID: nil, previousOwners: [], wallNow: wallNow)
}

private func proc(_ pid: Int32, start: Double?, isSelf: Bool = false) -> ProcessInfoRecord {
    ProcessInfoRecord(pid: pid, bundleID: "com.example.p\(pid)", localizedName: nil, executableName: nil, launchTime: nil, isSelf: isSelf, startTime: start)
}

private func processes(_ reads: [RawRead]) -> [ProcessInfoRecord] {
    reads.map(\.process)
}

private func record(_ index: Int) -> ExtrasRecord {
    let clean = AttributeRead<String>(value: "", error: "success")
    return ExtrasRecord(
        childIndex: index, role: AttributeRead(value: "AXMenuBarItem", error: "success"), identifier: clean,
        title: clean, description: clean, help: clean, frame: AttributeRead(value: barFrame(minX: 100, width: 24), error: "success")
    )
}

private func read(
    _ process: ProcessInfoRecord,
    extrasError: String = "success",
    extrasElapsed: Double = 0.01,
    childrenError: String? = "success",
    childrenElapsed: Double? = 0.01,
    childCount: Int? = nil,
    records: [ExtrasRecord] = [],
    walkInterrupted: Bool = false
) -> RawRead {
    quarantineRead(
        process, extrasError: extrasError, extrasElapsed: extrasElapsed, childrenError: childrenError,
        childrenElapsed: childrenElapsed, childCount: childCount, records: records, walkInterrupted: walkInterrupted
    )
}

/// Shared with the scenario enums above, which cannot see this file's
/// `private` helpers from their own scope.
func quarantineRead(
    _ process: ProcessInfoRecord,
    extrasError: String = "success",
    extrasElapsed: Double = 0.01,
    childrenError: String? = "success",
    childrenElapsed: Double? = 0.01,
    childCount: Int? = nil,
    records: [ExtrasRecord] = [],
    walkInterrupted: Bool = false
) -> RawRead {
    RawRead(
        process: process, extrasError: extrasError, extrasElapsed: extrasElapsed,
        childrenError: childrenError, childrenElapsed: childrenElapsed,
        records: records, walkInterrupted: walkInterrupted, childCount: childCount ?? records.count
    )
}

/// A process holding its extras-bar read for the full 0.25 s timeout.
private func stall(_ process: ProcessInfoRecord) -> RawRead {
    let raw = read(process, extrasError: "cannotComplete", extrasElapsed: 0.25, childrenError: nil, childrenElapsed: nil)
    precondition(ReadClassifier.outcome(raw) == .failed(.timedOut(call: "extrasBar")))
    return raw
}

/// Unrelated processes answering their extras bar quickly (M5: 13 ms p50).
private func fastReads(_ count: Int, elapsed: Double = 0.013) -> [RawRead] {
    (0..<count).map { read(proc(Int32(100 + $0), start: oldStart), extrasError: "noValue", extrasElapsed: elapsed, childrenError: nil, childrenElapsed: nil) }
}

private func item(_ process: ProcessInfoRecord) -> DiscoveredItem {
    DiscoveredItem(
        key: ItemKey(namespace: process.bundleID ?? "", identifier: "i\(process.pid)", pid: process.pid, childIndex: nil), basis: .declared,
        process: process, frame: barFrame(minX: 100, width: 24), position: .onBar,
        title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
    )
}
