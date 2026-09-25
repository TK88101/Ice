// Reads one tick of the bar over Accessibility, read-only, through
// MenuBarDiscovery's reader (0.25 s per element; no labels, no AX writes,
// no actions, no capture). Frames are converted to display-local points.
import AppKit
import IceCore
import IceWatchCore
import MenuBarDiscovery

final class BarReader {
    static let timeout = ReadClassifier.defaultTimeout

    let bar: BarLine
    private let origin: DiscoveryOrigin
    private let reader = LiveExtrasReader(readsLabels: false)
    private let apps = LiveRunningApps()
    /// Processes read every tick: those with an on-bar item at arm time or
    /// in any later enumeration (never shrinks during a run).
    private(set) var watched: [pid_t: ProcessInfoRecord] = [:]
    private var agent: ProcessInfoRecord?
    private var child: ProcessInfoRecord?

    init?() {
        guard let display = LiveDisplay().bar() else { return nil }
        bar = BarLine(minX: display.bounds.minX, maxX: display.bounds.maxX, height: display.bounds.barHeight)
        origin = display.origin
    }

    func setChild(pid: pid_t) {
        child = ProcessInfoRecord(pid: pid, bundleID: nil, localizedName: nil, executableName: nil, launchTime: nil, isSelf: false)
    }

    /// Reads every eligible running app once and adds each that has an
    /// on-bar item to the watched set. Returns the pids added.
    @discardableResult
    func enumerate() -> [pid_t] {
        if agent == nil, let agentPID = apps.agentPID() {
            agent = ProcessInfoRecord(pid: agentPID, bundleID: LiveExtrasReader.menuBarAgentBundleID, localizedName: nil, executableName: nil, launchTime: nil, isSelf: false)
        }
        var added: [pid_t] = []
        for process in apps.processes() where process.pid != agent?.pid && process.pid != child?.pid && watched[process.pid] == nil {
            let (read, _) = readProcess(process, isIce: false)
            if read.items.contains(where: { $0.frame.map(bar.contains) ?? false }) {
                watched[process.pid] = process
                added.append(process.pid)
            }
        }
        return added.sorted()
    }

    /// One tick: MenuBarAgent, the child (Ice) and every watched process.
    func tick() -> (tick: Tick, record: [String: Any]) {
        let clock = ContinuousClock()
        let start = clock.now
        var processes: [ProcessRead] = []
        var records: [[String: Any]] = []

        var agentFrames: [WatchFrame] = []
        var agentState = ReadState.failed
        if let agent {
            let raw = reader.read(agent, timeout: Self.timeout, interrupt: { false })
            switch ReadClassifier.outcome(raw, timeout: Self.timeout) {
            case .items(let children):
                agentState = .ok
                agentFrames = children.compactMap { $0.frame.value.map(convert) }
            case .none:
                agentState = .ok
            case .failed:
                agentState = .failed
            }
        }

        var targets = watched.values.sorted { $0.pid < $1.pid }.map { ($0, false) }
        if let child { targets.append((child, true)) }
        for (process, isIce) in targets {
            let (read, record) = readProcess(process, isIce: isIce)
            processes.append(read)
            records.append(record)
        }

        let elapsed = clock.now - start
        let duration = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let tick = Tick(duration: duration, agentFrames: agentFrames, agentState: agentState, processes: processes)
        let record: [String: Any] = [
            "duration": duration,
            "agentOK": agentState == .ok,
            "agent": agentFrames.map(Self.encode),
            "processes": records,
        ]
        return (tick, record)
    }

    private func readProcess(_ process: ProcessInfoRecord, isIce: Bool) -> (ProcessRead, [String: Any]) {
        let raw = reader.read(process, timeout: Self.timeout, interrupt: { false })
        var record: [String: Any] = ["pid": process.pid, "owner": process.bundleID ?? process.executableName ?? "pid:\(process.pid)"]
        switch ReadClassifier.outcome(raw, timeout: Self.timeout) {
        case .failed:
            record["state"] = "failed"
            return (ProcessRead(pid: process.pid, state: .failed, items: []), record)
        case .none:
            record["state"] = "ok"
            record["items"] = []
            return (ProcessRead(pid: process.pid, state: .ok, items: []), record)
        case .items(let children):
            let items = children.filter { $0.role.value == "AXMenuBarItem" }.map { child in
                WatchItem(
                    id: ItemID(pid: process.pid, child: child.childIndex),
                    identifier: child.identifier.value ?? "",
                    frame: child.frame.value.map(convert),
                    isIce: isIce
                )
            }
            record["state"] = "ok"
            record["items"] = items.map { item -> [String: Any] in
                var entry: [String: Any] = ["child": item.id.child]
                if !item.identifier.isEmpty { entry["identifier"] = item.identifier }
                if let frame = item.frame { entry["frame"] = Self.encode(frame) }
                return entry
            }
            return (ProcessRead(pid: process.pid, state: .ok, items: items), record)
        }
    }

    private func convert(_ rect: BarRect) -> WatchFrame {
        WatchFrame(minX: rect.minX - origin.x, minY: rect.minY - origin.y, width: rect.width, height: rect.height)
    }

    static func encode(_ frame: WatchFrame) -> [Double] {
        [frame.minX, frame.minY, frame.width, frame.height]
    }
}
