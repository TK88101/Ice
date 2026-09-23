import Foundation
import IceCore

/// A small lock-protected box, used internally for the cancellation flag a
/// running pass polls between processes. Not `Locked<T>` from the standard
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
/// processes twice running; cancellation and the deadline are both checked
/// between processes; the result has the display's origin already subtracted
/// from every frame and `ItemCatalog.carryOver` already applied.
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
    private let timeout: Double
    private let deadline: Double
    private let queue: DispatchQueue

    private let cursorLock = NSLock()
    private var cursor: Int = 0

    public init(
        apps: any RunningAppsProviding,
        reader: any ExtrasReading,
        display: any DisplayProviding,
        isTrusted: @escaping @Sendable () -> Bool,
        ownIdentifiers: OwnIdentifiers,
        now: @escaping @Sendable () -> Double,
        timeout: Double = 0.25,
        deadline: Double = 2.0,
        queue: DispatchQueue = DispatchQueue(label: "com.icereverse.MenuBarDiscovery.MenuBarDiscoverer")
    ) {
        self.apps = apps
        self.reader = reader
        self.display = display
        self.isTrusted = isTrusted
        self.ownIdentifiers = ownIdentifiers
        self.now = now
        self.timeout = timeout
        self.deadline = deadline
        self.queue = queue
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
        display displaySnapshot: (bounds: BarBounds, origin: (x: Double, y: Double)),
        cancelled: DiscoveryBox<Bool>
    ) -> DiscoveryResult? {
        let passStart = now()
        let processes = apps.processes()
        let agentPID = apps.agentPID()
        let count = processes.count
        let origin = DiscoveryOrigin(x: displaySnapshot.origin.x, y: displaySnapshot.origin.y)

        let startIndex = count > 0 ? currentCursor() % count : 0
        let deadlineAt = passStart + deadline

        var reads = [RawRead]()
        reads.reserveCapacity(count)
        var truncationIndex: Int?

        for offset in 0..<count {
            if cancelled.get() { return nil }
            let index = (startIndex + offset) % count
            if now() >= deadlineAt {
                truncationIndex = index
                break
            }
            reads.append(reader.read(processes[index], timeout: timeout))
        }

        if let truncationIndex {
            var index = truncationIndex
            var remaining = count - reads.count
            while remaining > 0 {
                reads.append(RawRead(process: processes[index], extrasError: "notAttempted", extrasElapsed: 0, childrenError: nil, childrenElapsed: nil, records: []))
                index = (index + 1) % count
                remaining -= 1
            }
        }

        let adjustedReads = reads.map { subtractOrigin($0, origin: displaySnapshot.origin) }

        let buildTime = now()
        let built = ItemCatalog.build(reads: adjustedReads, agentPID: agentPID, bounds: displaySnapshot.bounds, isTrusted: isTrusted(), ownIdentifiers: ownIdentifiers, now: buildTime, timeout: timeout)
        let carried = ItemCatalog.carryOver(previous: previous, current: built, now: buildTime)

        let nextCursor = truncationIndex ?? 0
        setCursor(nextCursor)

        return DiscoveryResult(set: carried, duration: now() - passStart, origin: origin, bounds: displaySnapshot.bounds, nextCursor: nextCursor)
    }

    private func currentCursor() -> Int {
        cursorLock.withLock { cursor }
    }

    private func setCursor(_ value: Int) {
        cursorLock.withLock { cursor = value }
    }

    /// Every AX frame in `raw.records` is in the global Accessibility
    /// coordinate space; IceCore's rules (`PositionRule`, `DividerReading`,
    /// D10's boundaries) are all written against display-local frames, so
    /// this is applied before `ItemCatalog.build` ever sees a read.
    private func subtractOrigin(_ raw: RawRead, origin: (x: Double, y: Double)) -> RawRead {
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
        return RawRead(process: raw.process, extrasError: raw.extrasError, extrasElapsed: raw.extrasElapsed, childrenError: raw.childrenError, childrenElapsed: raw.childrenElapsed, records: adjustedRecords)
    }
}
