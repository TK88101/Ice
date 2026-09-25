import Darwin
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDiscovery

/// Turns discovery's own AX seams (`ExtrasReading`, `RunningAppsProviding`)
/// into a `MenuBarAXReading` the frozen detector can read from (plan section
/// 4.3): decodes each requested id back into an `ItemKey`, reads that key's
/// pid once (shared across every key of that pid), matches the child whose
/// trimmed `AXIdentifier` equals the key's identifier, and hands back the AX
/// frame minus the display origin, trimmed by `CheckFrames.trim` (D15) --
/// never a raw AX frame, so no caller of this reader can feed the detector
/// something D15 has not already corrected.
///
/// A keyed pid's read that cannot be trusted fails the whole snapshot
/// (hardening plan H1): `.failed`, cut by the sample's deadline, or never
/// reached before it. The contract (`MenuBarAXReading.read`) makes an absent id
/// a *successful* read that found nothing, so reporting such a pid's keys as
/// absent would fabricate a disappearance; `nil` makes the sampler take no
/// sample instead. A `.none` read -- no extras bar, the process gone -- is an
/// honest absence and still leaves its keys out.
public struct DiscoveredFrameReader: MenuBarAXReading {
    private let extras: any ExtrasReading
    private let apps: any RunningAppsProviding
    private let origin: DiscoveryOrigin
    private let timeout: Double
    private let now: @Sendable () -> Double
    private let deadline: Double

    /// `deadline` bounds one sample, measured on `now` from the start of `read`.
    public init(
        extras: any ExtrasReading,
        apps: any RunningAppsProviding,
        origin: DiscoveryOrigin,
        timeout: Double = ReadClassifier.defaultTimeout,
        now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
        deadline: Double = 2.0
    ) {
        self.extras = extras
        self.apps = apps
        self.origin = origin
        self.timeout = timeout
        self.now = now
        self.deadline = deadline
    }

    public func read(items: [String: pid_t]) -> MenuBarAXSnapshot? {
        let deadlineAt = now() + deadline
        let processesByPID = Dictionary(apps.processes().map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

        guard let agentPID = apps.agentPID() else { return nil }
        guard let agentFrames = agentFrames(pid: agentPID, processesByPID: processesByPID) else { return nil }

        // Decode every requested id up front, dropping anything that fails
        // to decode or is positional -- both cases read as "absent", and a
        // positional key is never even sent to `ExtrasReading` (plan's HARD
        // RULES: "positional → absent, with NO read for positional").
        var keysByPID = [pid_t: [(id: String, key: ItemKey)]]()
        for (id, pid) in items {
            guard let key = ItemKey.decode(id), key.childIndex == nil else { continue }
            keysByPID[pid, default: []].append((id, key))
        }

        var itemFrames = [String: ItemFrame]()
        // Sorted, so which pid a deadline leaves unread never depends on hashing.
        for (pid, entries) in keysByPID.sorted(by: { $0.key < $1.key }) {
            guard now() < deadlineAt else { return nil }
            let process = processesByPID[pid] ?? minimalProcess(pid: pid)
            let raw = extras.read(process, timeout: timeout, interrupt: { now() >= deadlineAt })
            let records: [ExtrasRecord]
            switch ReadClassifier.outcome(raw, timeout: timeout) {
            case .items(let read): records = read
            case .none: continue
            case .failed: return nil
            }

            // Only the records `ItemCatalog.build` keys (role `AXMenuBarItem`),
            // so a key is matched against exactly the records it was made from.
            let listed = records.filter { $0.role.value == "AXMenuBarItem" }
            for (id, key) in entries {
                let matches = listed.filter { IdentifierText.trimmed($0.identifier.value ?? "") == key.identifier }
                guard matches.count == 1, let frame = matches[0].frame.value else { continue }
                let adjusted = BarRect(minX: frame.minX - origin.x, minY: frame.minY - origin.y, width: frame.width, height: frame.height)
                let trimmed = CheckFrames.trim(adjusted)
                itemFrames[id] = ItemFrame(id: id, minX: trimmed.minX, minY: trimmed.minY, width: trimmed.width, height: trimmed.height)
            }
        }

        return MenuBarAXSnapshot(itemFrames: itemFrames, agentFrames: agentFrames)
    }

    /// `nil` exactly when the agent cannot be read (`.failed`) -- a `.none`
    /// outcome (the agent's extras bar genuinely reports nothing) is not a
    /// failure of the *whole* read, so it produces an empty array instead.
    private func agentFrames(pid: pid_t, processesByPID: [pid_t: ProcessInfoRecord]) -> [AgentFrame]? {
        let process = processesByPID[pid] ?? minimalProcess(pid: pid)
        let raw = extras.read(process, timeout: timeout, interrupt: { false })
        switch ReadClassifier.outcome(raw, timeout: timeout) {
        case .items(let records):
            return records.compactMap { record -> AgentFrame? in
                guard let frame = record.frame.value else { return nil }
                return AgentFrame(minX: frame.minX - origin.x, minY: frame.minY - origin.y, width: frame.width)
            }
        case .none:
            return []
        case .failed:
            return nil
        }
    }

    private func minimalProcess(pid: pid_t) -> ProcessInfoRecord {
        ProcessInfoRecord(pid: pid, bundleID: nil, localizedName: nil, executableName: nil, launchTime: nil, isSelf: false)
    }
}
