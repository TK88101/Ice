import Foundation
import IceCore

/// A small lock-protected box, used internally for the cancellation flag a
/// running pass polls between processes and for the rotating cursor. Not `Locked<T>` from the standard
/// library (macOS 14's deployment target predates it).
final class DiscoveryBox<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.withLock { value }
    }

    func set(_ newValue: Value) {
        lock.withLock { value = newValue }
    }
}

/// Runs the whole AX walk (plan section 4.2): every running process
/// including its own, starting each pass at the rotating cursor where the
/// previous pass's deadline stopped, so a truncation never falls on the same
/// processes twice running; cancellation and the deadline are checked between
/// processes and, through the interrupt every read is handed, between the
/// children of one walk; the result has the display's origin already subtracted
/// from every frame and `ItemCatalog.carryOver` already applied.
///
/// It also keeps a `ResponsivenessQuarantine` across passes (2026-09-25
/// responsiveness-quarantine plan, section 3): quarantined processes are left
/// out of the rotation and re-probed after it, only while one timeout still fits
/// the pass's budget, so they can never push an eligible process into the
/// unread tail.
///
/// Everything happens on `queue`, a dedicated serial queue -- never the main
/// thread or the cooperative thread pool (D19) -- reached from `async` via
/// `withCheckedContinuation` inside `withTaskCancellationHandler`, so
/// cancelling the `Task` that owns a `discover()` call sets a lock-protected
/// flag the running pass polls, rather than trying to interrupt a blocking
/// AX call it has no way to interrupt.
public final class MenuBarDiscoverer: @unchecked Sendable {
    private let apps: any RunningAppsProviding
    private let reader: any ExtrasReading
    private let display: any DisplayProviding
    private let isTrusted: @Sendable () -> Bool
    private let ownIdentifiers: OwnIdentifiers
    private let now: @Sendable () -> Double
    /// Seconds on the mach absolute clock, for the quarantine's age gate: each
    /// process's `startUptime` is on that clock (hardening plan H5).
    private let uptime: @Sendable () -> Double
    private let timeout: Double
    private let deadline: Double
    /// Its own, serial, and not injectable (hardening plan H4): two passes must
    /// never read and write the cursor and the quarantine at once, and a queue
    /// handed in could be concurrent.
    private let queue = DispatchQueue(label: "com.icereverse.MenuBarDiscovery.MenuBarDiscoverer")

    /// Where the next pass starts: the process the last one's deadline
    /// stopped at.
    private let cursor = DiscoveryBox(0)

    /// The quarantine the next pass starts from; stored only by a pass that
    /// completes, like the cursor.
    private let quarantine = DiscoveryBox(ResponsivenessQuarantine())

    public init(
        apps: any RunningAppsProviding,
        reader: any ExtrasReading,
        display: any DisplayProviding,
        isTrusted: @escaping @Sendable () -> Bool,
        ownIdentifiers: OwnIdentifiers,
        now: @escaping @Sendable () -> Double,
        uptime: @escaping @Sendable () -> Double = { LiveRunningApps.uptimeNow() },
        timeout: Double = ReadClassifier.defaultTimeout,
        deadline: Double = 2.0
    ) {
        self.apps = apps
        self.reader = reader
        self.display = display
        self.isTrusted = isTrusted
        self.ownIdentifiers = ownIdentifiers
        self.now = now
        self.uptime = uptime
        self.timeout = timeout
        self.deadline = deadline
    }

    /// `nil` when the display has nothing to report, or when the pass was
    /// cancelled -- in both cases the caller's `previous` set is simply not
    /// replaced.
    public func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? {
        guard let displaySnapshot = display.bar() else { return nil }

        let cancelled = DiscoveryBox(false)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<DiscoveryResult?, Never>) in
                queue.async {
                    let result = self.runPass(previous: previous, display: displaySnapshot, cancelled: cancelled)
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            cancelled.set(true)
        }
    }

    // MARK: - The pass itself (runs on `queue`)

    private func runPass(
        previous: DiscoveredItemSet?,
        display displaySnapshot: (bounds: BarBounds, origin: DiscoveryOrigin),
        cancelled: DiscoveryBox<Bool>
    ) -> DiscoveryResult? {
        let passStart = now()
        let processes = apps.processes()
        let agentPID = apps.agentPID()
        let count = processes.count
        let origin = displaySnapshot.origin

        let startIndex = count > 0 ? cursor.get() % count : 0
        let deadlineAt = passStart + deadline
        let state = quarantine.get()
        let context = QuarantineContext(agentPID: agentPID, previous: previous, uptimeNow: uptime())
        // Handed to every read, the first of the pass included: the walk polls it
        // before each child.
        let interrupt = { cancelled.get() || self.now() >= deadlineAt }

        // The quarantine judges the whole pass at one instant, its start: who is
        // skipped, who is due, who has lapsed, and when the next probes fall. With
        // several instants a process could be skipped by the rotation and then,
        // having lapsed by settlement, be neither read nor listed (security
        // re-check LOW-N1; test d15).
        guard let rotation = rotate(processes, from: startIndex, state: state, context: context, judgedAt: passStart, deadlineAt: deadlineAt, interrupt: interrupt, cancelled: cancelled) else {
            return nil
        }

        // Re-probes only after a rotation that was not cut short, and only while
        // one timeout still fits: they never take budget from an eligible process.
        var reprobes = [RawRead]()
        if !rotation.truncated {
            for process in state.dueReprobes(among: processes, context: context, now: passStart) {
                if cancelled.get() { return nil }
                guard now() + timeout <= deadlineAt else { break }
                reprobes.append(reader.read(process, timeout: timeout, interrupt: interrupt))
            }
        }
        if cancelled.get() { return nil }

        let buildTime = now()
        let settlement = state.settle(processes: processes, reads: rotation.reads, reprobes: reprobes, context: context, now: passStart, timeout: timeout)
        let adjustedReads = settlement.admitted.map { subtractOrigin($0, origin: origin) }
        let built = ItemCatalog.build(reads: adjustedReads, agentPID: agentPID, bounds: displaySnapshot.bounds, isTrusted: isTrusted(), ownIdentifiers: ownIdentifiers, now: buildTime, timeout: timeout)
        let carried = ItemCatalog.carryOver(previous: previous, current: built, now: buildTime)

        cursor.set(rotation.nextCursor)
        quarantine.set(settlement.quarantine)

        return DiscoveryResult(set: carried, duration: now() - passStart, origin: origin, bounds: displaySnapshot.bounds, nextCursor: rotation.nextCursor, quarantined: settlement.quarantined)
    }

    /// One pass's rotation, from `startIndex`: every process not skipped by the
    /// quarantine, read in turn until the deadline, then a synthetic
    /// `notAttempted` read for every later offset that is not skipped either --
    /// the tail is built from offsets, so a skipped process can never make it
    /// read one process twice or another not at all. `nil` when cancelled.
    ///
    /// The cursor: where the deadline stopped the pass before a read, that
    /// process is next (as before). Where a read itself came back cut past the
    /// deadline, it is kept as the failure it is and the cursor goes **on** it if
    /// it was not the pass's first -- so next pass it has the whole budget -- and
    /// **past** it if it was, since it already had the whole budget. Either way
    /// the cursor never stays where the pass started, so every pass makes
    /// progress (plan 3.7).
    private func rotate(
        _ processes: [ProcessInfoRecord],
        from startIndex: Int,
        state: ResponsivenessQuarantine,
        context: QuarantineContext,
        judgedAt: Double,
        deadlineAt: Double,
        interrupt: () -> Bool,
        cancelled: DiscoveryBox<Bool>
    ) -> (reads: [RawRead], nextCursor: Int, truncated: Bool)? {
        let count = processes.count
        var reads = [RawRead]()
        reads.reserveCapacity(count)
        var tailStart: Int?
        var nextCursor = 0

        for offset in 0..<count {
            if cancelled.get() { return nil }
            let index = (startIndex + offset) % count
            let process = processes[index]
            if state.isSkipped(process, context: context, now: judgedAt) { continue }
            if offset > 0, now() >= deadlineAt {
                tailStart = offset
                nextCursor = index
                break
            }
            let raw = reader.read(process, timeout: timeout, interrupt: interrupt)
            reads.append(raw)
            if raw.walkInterrupted, now() >= deadlineAt {
                tailStart = offset + 1
                nextCursor = offset == 0 ? (index + 1) % count : index
                break
            }
        }
        if cancelled.get() { return nil }

        guard let tailStart else { return (reads, nextCursor, false) }
        for offset in tailStart..<count {
            let process = processes[(startIndex + offset) % count]
            if state.isSkipped(process, context: context, now: judgedAt) { continue }
            reads.append(RawRead(process: process, extrasError: "notAttempted", extrasElapsed: 0, childrenError: nil, childrenElapsed: nil, records: [], walkInterrupted: false, childCount: 0))
        }
        return (reads, nextCursor, true)
    }

    /// Every AX frame in `raw.records` is in the global Accessibility
    /// coordinate space; IceCore's rules (`PositionRule`, `DividerReading`,
    /// D10's boundaries) are all written against display-local frames, so
    /// this is applied before `ItemCatalog.build` ever sees a read.
    private func subtractOrigin(_ raw: RawRead, origin: DiscoveryOrigin) -> RawRead {
        guard !raw.records.isEmpty else { return raw }
        let adjustedRecords = raw.records.map { record -> ExtrasRecord in
            guard let frame = record.frame.value else { return record }
            let adjusted = BarRect(minX: frame.minX - origin.x, minY: frame.minY - origin.y, width: frame.width, height: frame.height)
            return ExtrasRecord(
                childIndex: record.childIndex,
                role: record.role,
                identifier: record.identifier,
                title: record.title,
                description: record.description,
                help: record.help,
                frame: AttributeRead(value: adjusted, error: record.frame.error)
            )
        }
        return RawRead(process: raw.process, extrasError: raw.extrasError, extrasElapsed: raw.extrasElapsed, childrenError: raw.childrenError, childrenElapsed: raw.childrenElapsed, records: adjustedRecords, walkInterrupted: raw.walkInterrupted, childCount: raw.childCount)
    }
}
