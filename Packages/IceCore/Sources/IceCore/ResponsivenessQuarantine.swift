/// Keeps processes that stall Accessibility, and have never shown any extras,
/// from costing every discovery pass its time and its completeness
/// (2026-09-25 responsiveness-quarantine plan, section 3).
///
/// MEASURED 2026-09-25: a suspended WebKit content process holds its
/// `AXExtrasMenuBar` read for the full per-call timeout, every pass, and made
/// every pass `incomplete`. The `.prohibited` filter cannot see these processes
/// (they are `.accessory`, which is what real menu bar apps are too), so they are
/// told apart by behaviour instead: one that stalls on its extras bar, has never
/// shown a non-empty extras snapshot, and is old enough for that to mean
/// something, is skipped by later passes and re-probed on a backoff.
///
/// Nothing here hides a failure. The read that first meets a stall is counted as
/// the failure it is; a process is only *skipped* from the next pass on, and it
/// is listed wherever it is skipped.

/// A process as the quarantine knows it: the pid plus the kernel start time, so
/// a verdict about one process can never land on another that later reuses its
/// pid. No start time, no identity -- and no quarantine.
public struct ProcessIdentity: Hashable, Sendable {
    public let pid: Int32
    public let startTime: Double

    public init?(_ process: ProcessInfoRecord) {
        guard let startTime = process.startTime else { return nil }
        self.pid = process.pid
        self.startTime = startTime
    }
}

/// What a pass knows beyond its own reads: the menu bar agent's pid, the
/// identities that owned an item in the caller's previous set, and the wall
/// clock the age gate is measured against (the start time is wall-clock
/// seconds; the backoff runs on the caller's monotonic clock instead).
public struct QuarantineContext: Equatable, Sendable {
    public let agentPID: Int32?
    public let previousOwners: Set<ProcessIdentity>
    public let wallNow: Double

    public init(agentPID: Int32?, previousOwners: Set<ProcessIdentity>, wallNow: Double) {
        self.agentPID = agentPID
        self.previousOwners = previousOwners
        self.wallNow = wallNow
    }

    /// Every process that owned a listed item -- the visible control item
    /// included -- in `previous`, by identity.
    public init(agentPID: Int32?, previous: DiscoveredItemSet?, wallNow: Double) {
        let owners = (previous?.listedItems ?? []).compactMap { ProcessIdentity($0.process) }
        self.init(agentPID: agentPID, previousOwners: Set(owners), wallNow: wallNow)
    }
}

public struct ResponsivenessQuarantine: Equatable, Sendable {
    /// The first re-probe comes this long after a process enters, below Ice's
    /// 5 s tick, so a process caught in a passing stall is re-read at the next
    /// pass anyway.
    public static let initialBackoff: Double = 2
    /// A choice, not a derivation (plan 3.4): it bounds how late a recovered
    /// process's items can appear -- the backoff in force plus one pass -- at
    /// roughly half a minute, for one read of at most the timeout per quarantined
    /// process per 30 s.
    public static let maxBackoff: Double = 30
    /// A process younger than this is never quarantined: an app still launching
    /// stalls exactly like a suspended one, and at login every app is launching.
    /// The WebKit processes measured were 9 to 55 minutes old.
    public static let minimumAge: Double = 60
    /// A witness is an extras-bar answer under this fraction of the timeout
    /// (50 ms at 0.25 s), well clear of the fast band measured (32 ms at most) and
    /// far below the stall line.
    public static let witnessFraction: Double = 0.2

    public struct Entry: Equatable, Sendable {
        public let backoff: Double
        public let nextProbeAt: Double

        public init(backoff: Double, nextProbeAt: Double) {
            self.backoff = backoff
            self.nextProbeAt = nextProbeAt
        }
    }

    /// The quarantined identities.
    public let entries: [ProcessIdentity: Entry]
    /// Identities that have shown a non-empty extras snapshot -- an extras bar
    /// that answered with at least one child, however that read then classified.
    /// Exempt for as long as they are enumerated.
    public let snapshotShown: Set<ProcessIdentity>

    public init(entries: [ProcessIdentity: Entry] = [:], snapshotShown: Set<ProcessIdentity> = []) {
        self.entries = entries
        self.snapshotShown = snapshotShown
    }

    /// What one pass leaves behind.
    public struct Settlement: Equatable, Sendable {
        /// The state the next pass starts from.
        public let quarantine: ResponsivenessQuarantine
        /// The reads `ItemCatalog.build` is to see: every rotation read, the
        /// synthetic tail included, plus every re-probe that did not stall again.
        public let admitted: [RawRead]
        /// Every enumerated process under quarantine once this pass settled,
        /// by pid.
        public let quarantined: [ProcessInfoRecord]
    }

    /// Whether the pass's ordinary rotation leaves `process` out.
    public func isSkipped(_ process: ProcessInfoRecord, context: QuarantineContext) -> Bool {
        guard let identity = ProcessIdentity(process), entries[identity] != nil else { return false }
        return !isExempt(process, identity: identity, context: context, shown: snapshotShown)
    }

    /// The skipped processes whose re-probe is due at `now`: oldest due first,
    /// then by pid, so none of them can be starved by the others.
    public func dueReprobes(among processes: [ProcessInfoRecord], context: QuarantineContext, now: Double) -> [ProcessInfoRecord] {
        let due = processes.compactMap { process -> (process: ProcessInfoRecord, at: Double)? in
            guard isSkipped(process, context: context),
                  let identity = ProcessIdentity(process),
                  let entry = entries[identity],
                  now >= entry.nextProbeAt
            else { return nil }
            return (process, entry.nextProbeAt)
        }
        return due.sorted { ($0.at, $0.process.pid) < ($1.at, $1.process.pid) }.map(\.process)
    }

    /// Settles one pass. `reads` are the rotation's reads, the synthetic tail
    /// included; `reprobes` are the reads of due quarantined processes -- kept
    /// apart so this never has to guess which read was which.
    public func settle(
        processes: [ProcessInfoRecord],
        reads: [RawRead],
        reprobes: [RawRead],
        context: QuarantineContext,
        now: Double,
        timeout: Double = ReadClassifier.defaultTimeout
    ) -> Settlement {
        let live = Set(processes.compactMap(ProcessIdentity.init))
        let attempted = reads + reprobes
        let shown = snapshotShown.intersection(live).union(
            attempted.filter(Self.showsSnapshot).compactMap { ProcessIdentity($0.process) }
        )
        let witnessed = Self.isWitnessed(attempted, timeout: timeout)

        var next = entries.filter { live.contains($0.key) }
        var admitted = [RawRead]()

        for raw in reads {
            admitted.append(raw)
            guard let identity = ProcessIdentity(raw.process) else { continue }
            if isExempt(raw.process, identity: identity, context: context, shown: shown) {
                next[identity] = nil
                continue
            }
            if witnessed, Self.isStall(raw, timeout: timeout), context.wallNow - identity.startTime >= Self.minimumAge {
                next[identity] = Entry(backoff: Self.initialBackoff, nextProbeAt: now + Self.initialBackoff)
            }
        }

        for raw in reprobes {
            guard let identity = ProcessIdentity(raw.process), let entry = next[identity],
                  !isExempt(raw.process, identity: identity, context: context, shown: shown),
                  Self.isStall(raw, timeout: timeout)
            else {
                // It answered: lifted, and settled like any other read.
                if let identity = ProcessIdentity(raw.process) { next[identity] = nil }
                admitted.append(raw)
                continue
            }
            let backoff = min(entry.backoff * 2, Self.maxBackoff)
            next[identity] = Entry(backoff: backoff, nextProbeAt: now + backoff)
        }

        let quarantined = processes
            .filter { ProcessIdentity($0).map { next[$0] != nil } ?? false }
            .sorted { $0.pid < $1.pid }
        return Settlement(quarantine: ResponsivenessQuarantine(entries: next, snapshotShown: shown), admitted: admitted, quarantined: quarantined)
    }

    // MARK: - rules

    private func isExempt(_ process: ProcessInfoRecord, identity: ProcessIdentity, context: QuarantineContext, shown: Set<ProcessIdentity>) -> Bool {
        process.isSelf
            || process.pid == context.agentPID
            || shown.contains(identity)
            || context.previousOwners.contains(identity)
    }

    /// The only trigger: the process did not even hand over its extras bar.
    private static func isStall(_ raw: RawRead, timeout: Double) -> Bool {
        ReadClassifier.outcome(raw, timeout: timeout) == .failed(.timedOut(call: "extrasBar"))
    }

    private static func showsSnapshot(_ raw: RawRead) -> Bool {
        raw.extrasError == "success" && raw.childCount >= 1
    }

    /// Fast extras-bar answers outnumber stalls in this pass: the AX system as a
    /// whole was answering, so a stall is the process's own. A `notAttempted`
    /// read asked nothing and counts as neither.
    private static func isWitnessed(_ reads: [RawRead], timeout: Double) -> Bool {
        let asked = reads.filter { $0.extrasError != "notAttempted" }
        let fast = asked.filter { $0.extrasElapsed < timeout * witnessFraction }.count
        let stalled = asked.filter { $0.extrasElapsed >= timeout * ReadClassifier.slowFraction }.count
        return fast > stalled
    }
}
