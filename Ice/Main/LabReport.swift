//
//  LabReport.swift
//  Ice
//

import Cocoa
import IceCore

/// Ice's lab report mode (plan 2026-10-07-icebar-preference-hiding, S4 design
/// D1): with `-IceLabReport YES` under a lab identity, a normal launch also
/// writes what Ice holds to standard output, one JSON line per event and per
/// changed snapshot, and takes the lab runner's commands from standard input.
/// Inert otherwise: `record` returns at once while no report is running.
@MainActor
enum LabReport {
    /// Decided once, from the launch arguments only, never a stored default.
    static let launch = LabReportRule.launch(
        report: launchArgument(LabReportRule.reportArgument),
        holdLength: launchArgument(LabReportRule.holdLengthArgument),
        bundleID: Bundle.main.bundleIdentifier
    )

    /// A launch argument's value, from the arguments only, never a stored
    /// default (both lab modes read theirs this way).
    nonisolated static func launchArgument(_ name: String) -> String? {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        return arguments[name].map { $0 as? String ?? String(describing: $0) }
    }

    /// The report launch's settings; `nil` in every other launch.
    static var plan: LabReportPlan? {
        if case .report(let plan) = launch { plan } else { nil }
    }

    private static let snapshotInterval: TimeInterval = 0.5
    /// A snapshot is written this often also when nothing changed, so a
    /// quiet report can be told from a stopped one.
    private static let heartbeatInterval: TimeInterval = 5

    private static var session: Session?

    /// A refused report launch quits before Ice's own setup.
    static func exitIfRefused() {
        guard case .refused(let refusal) = launch else {
            return
        }
        FileHandle.standardError.write(Data("IceLabReport refused: \(refusal)\n".utf8))
        exit(2)
    }

    /// Starts the report; called before Ice's setup, so the first status and
    /// roster are in it. Does nothing in any other launch.
    static func startIfAsked(appState: AppState) {
        guard let plan, session == nil else {
            return
        }
        let session = Session(appState: appState)
        self.session = session
        session.write(.start(pid: getpid(), bundleID: Bundle.main.bundleIdentifier, holdLength: plan.holdLength))
        session.startSnapshots()
        session.startCommands()
    }

    /// A hook at the code path where the event happens; does nothing unless
    /// a report runs.
    static func record(_ event: @autoclosure () -> LabReportEvent) {
        session?.write(event())
    }

    /// What the hidden control item is given for a length the machine
    /// decided: the length itself, except in a report launch that holds
    /// lengths (scenario 11's fault). Records the length event.
    static func applied(_ decided: Double?) -> Double? {
        let outcome = LabReportRule.appliedLength(decided, plan: plan)
        record(.length(outcome, decided: decided))
        return outcome.applied
    }

    /// Records the roster's members when they changed; nothing is computed
    /// unless a report runs.
    @available(macOS 27, *)
    static func recordRoster(from old: IceBarRoster, to new: IceBarRoster) {
        guard session != nil else {
            return
        }
        let members = names(of: new.rules)
        if members != names(of: old.rules) {
            record(.roster(members))
        }
    }

    private static func names(of rules: PreferenceHidingRoster) -> [LabReportItem] {
        rules.membership.members.map { LabReportItem(member: $0, lastKey: rules.lastKeys[$0.tag]) }
    }
}

// MARK: - LabReport.Session

extension LabReport {
    @MainActor
    private final class Session {
        private weak var appState: AppState?
        private var writer = LabReportWriter()
        private let start = ProcessInfo.processInfo.systemUptime
        private var timer: Timer?
        private var lastSnapshot: LabReportSnapshot?
        private var lastSnapshotAt = 0.0
        private var commands: DispatchSourceRead?

        init(appState: AppState) {
            self.appState = appState
        }

        func write(_ event: LabReportEvent) {
            let line = writer.line(event, at: ProcessInfo.processInfo.systemUptime - start)
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
        }

        func startSnapshots() {
            timer = .scheduledTimer(withTimeInterval: LabReport.snapshotInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.writeSnapshotIfChanged()
                }
            }
        }

        private func writeSnapshotIfChanged() {
            guard #available(macOS 27, *), let appState else {
                return
            }
            let snapshot = Self.snapshot(appState: appState)
            let now = ProcessInfo.processInfo.systemUptime
            guard snapshot != lastSnapshot || now - lastSnapshotAt >= LabReport.heartbeatInterval else {
                return
            }
            lastSnapshot = snapshot
            lastSnapshotAt = now
            write(.snapshot(snapshot))
        }

        /// One command per line of standard input, read off the main thread;
        /// the end of input ends the reading and nothing else.
        func startCommands() {
            let source = DispatchSource.makeReadSource(fileDescriptor: FileHandle.standardInput.fileDescriptor, queue: .global(qos: .userInitiated))
            let buffer = LineBuffer()
            source.setEventHandler { [weak self] in
                let chunk = FileHandle.standardInput.availableData
                guard !chunk.isEmpty else {
                    source.cancel()
                    return
                }
                for line in buffer.lines(adding: chunk) {
                    Task { @MainActor in
                        self?.handle(line)
                    }
                }
            }
            source.resume()
            commands = source
        }

        private func handle(_ line: String) {
            guard #available(macOS 27, *), let appState, let command = LabReportCommand.parse(line) else {
                write(.unknownCommand)
                return
            }
            let manager = appState.itemManager
            switch command {
            case .barOpen:
                // The icon's click shows the IceBar only while it is offered (`MenuBarSection.show`).
                guard manager.isIceBarOffered else {
                    write(.bar(action: "open", answer: "refused:notOffered"))
                    return
                }
                // What a click on Ice's icon does (`ControlItem.performAction`).
                appState.menuBarManager.section(withName: .hidden)?.show()
                write(.bar(action: "open", answer: "sent"))
            case .barClose:
                appState.menuBarManager.section(withName: .hidden)?.hide()
                write(.bar(action: "close", answer: "sent"))
            case .press(let namespace, let identifier):
                let cells = Self.cells(of: manager)
                let target = LabReportRule.pressTarget(
                    namespace: namespace, identifier: identifier, cells: cells.map(\.cell), isIceBarOffered: manager.isIceBarOffered
                )
                switch target {
                case .cell(let index):
                    // What a click on the cell does (`IceBarAccessibilityCell`).
                    manager.pressFromIceBar(cells[index].item)
                    write(.press(namespace: namespace, identifier: identifier, answer: "sent"))
                case .refused(let refusal):
                    write(.press(namespace: namespace, identifier: identifier, answer: "refused:\(refusal.rawValue)"))
                }
            }
        }

        // MARK: Snapshot

        private static func key(of item: MenuBarItem) -> ItemKey? {
            guard case .accessibility(let encoded) = item.id else {
                return nil
            }
            return ItemKey.decode(encoded)
        }

        /// The IceBar's cells that have a key, each with its item.
        @available(macOS 27, *)
        private static func cells(of manager: MenuBarItemManager) -> [(cell: LabReportCell, item: MenuBarItem)] {
            manager.iceBarRoster.items.compactMap { item in
                key(of: item).map { key in
                    (LabReportCell(namespace: key.namespace, identifier: key.identifier, disabled: manager.isIceBarCellDisabled(item)), item)
                }
            }
        }

        @available(macOS 27, *)
        private static func snapshot(appState: AppState) -> LabReportSnapshot {
            let manager = appState.itemManager
            let coordinator = manager.iceBarHidingStorage as? IceBarHidingCoordinator
            let facts = coordinator?.labFacts ?? IceBarHidingMachine().labFacts
            let discovery = manager.labDiscovery
            let set = discovery.set
            let frames = Dictionary((set?.items ?? []).map { ($0.key, $0.frame) }, uniquingKeysWith: { first, _ in first })
            let rules = manager.iceBarRoster.rules
            let membership = rules.membership

            func items(_ section: MenuBarSection.Name) -> [LabReportItem] {
                manager.itemCache[section].compactMap { key(of: $0).map(LabReportItem.init) }
            }
            func controlItem(_ reading: DividerReading?) -> LabReportControlItem? {
                reading.map { LabReportControlItem(frame: $0.frame, usable: $0.isUsable) }
            }

            return LabReportSnapshot(
                phase: facts.phase,
                status: facts.status,
                lengthSet: facts.lengthSet,
                lengthApplied: facts.lengthApplied,
                calibratedHiddenLength: appState.menuBarManager.controlItem(withName: .hidden)?.calibratedHiddenLength.map { Double($0) },
                isIceBarOffered: manager.isIceBarOffered,
                isIceBarPresented: appState.navigationState.isIceBarPresented,
                isInteracting: coordinator?.isInteracting ?? false,
                roster: membership.members.map { member in
                    let item = LabReportItem(member: member, lastKey: rules.lastKeys[member.tag])
                    return LabReportMember(
                        namespace: item.namespace,
                        identifier: item.identifier,
                        pid: member.key?.pid,
                        condition: LabReportNames.condition(member.condition),
                        pressable: member.isPressable,
                        frame: member.key.flatMap { frames[$0] ?? nil }
                    )
                },
                blockers: membership.blockers.map { LabReportItem($0.key) },
                cells: cells(of: manager).map(\.cell),
                cacheVisible: items(.visible),
                cacheHidden: items(.hidden),
                cacheAlwaysHidden: items(.alwaysHidden),
                iconPlacement: manager.iconPlacement.map { String(describing: $0) },
                hiddenBoundaryUsable: manager.hiddenBoundaryUsable,
                icon: set?.visibleControlItem.map { LabReportControlItem(frame: $0.frame, usable: $0.position == .onBar) },
                hiddenDivider: controlItem(set?.hiddenDivider),
                alwaysHiddenDivider: controlItem(set?.alwaysHiddenDivider),
                completeness: LabReportNames.completeness(set?.completeness),
                pass: discovery.passes,
                checks: facts.checks
                    .map { LabReportCheck(namespace: $0.key.namespace, identifier: $0.key.identifier, outcome: VerificationSummary.name(of: $0.value)) }
                    .sorted { ($0.namespace, $0.identifier) < ($1.namespace, $1.identifier) },
                chevronListed: facts.chevronListed
            )
        }
    }

    /// Standard input's bytes cut into lines; used from the read source's
    /// queue only.
    private final class LineBuffer: @unchecked Sendable {
        private var pending = Data()

        func lines(adding chunk: Data) -> [String] {
            pending.append(chunk)
            var lines = [String]()
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                lines.append(String(decoding: line, as: UTF8.self))
            }
            return lines
        }
    }
}
