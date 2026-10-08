//
//  IceBarHidingCoordinator.swift
//  Ice
//

import Cocoa
import Combine
import IceCore
import MenuBarDetectorFeed
import OSLog

/// Runs `IceBarHidingMachine` against the live bar on macOS 27 (plan
/// 2026-10-07-icebar-preference-hiding, S3 and its T3b design): samples the
/// roster, the preconditions and the layout once a second, and carries out
/// the machine's commands. The `«` is read with every observation and only
/// logged (D-b).
@available(macOS 27, *)
@MainActor
final class IceBarHidingCoordinator {
    private static let tickInterval: TimeInterval = 1
    private static let tickTolerance: TimeInterval = 0.2

    private weak var appState: AppState?
    private var machine = IceBarHidingMachine()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// The baseline or observation under way.
    private var work: Task<Void, Never>?
    private var isSampling = false

    private var observer: (displayID: CGDirectDisplayID, observer: HiddenLengthObserver)?

    private let logger = Logger(category: "IceBarHiding")

    /// Whether Ice rests at a length, so the IceBar may be offered.
    var isLengthApplied: Bool {
        machine.lengthApplied
    }

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        guard let appState else {
            return
        }
        appState.settings.general.$useIceBar
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak appState] isIceBar in
                if !isIceBar {
                    appState?.itemManager.resetIceBarRoster()
                }
                self?.send(.mode(isIceBar: isIceBar))
            }
            .store(in: &cancellables)
        timer = .scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer?.tolerance = Self.tickTolerance
    }

    // MARK: - Events

    private func send(_ event: IceBarHidingEvent) {
        let (next, commands) = machine.step(event, now: ProcessInfo.processInfo.systemUptime)
        machine = next
        for command in commands {
            execute(command)
        }
        // At standard length the items are back on the bar: an open IceBar would list them twice.
        if !isLengthApplied, let appState, appState.navigationState.isIceBarPresented {
            appState.menuBarManager.iceBarPanel.close()
        }
    }

    private func tick() {
        guard machine.phase != .off, !isSampling, let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
            return
        }
        isSampling = true
        Task {
            // Accessibility can block on a busy frontmost app: off the main thread.
            let menuMaxX = await Task.detached { screen.getApplicationMenuFrame()?.maxX }.value
            isSampling = false
            guard let appState else {
                return
            }
            keepDividersHidden(appState: appState)
            send(.sample(sample(appState: appState, screen: screen, menuMaxX: menuMaxX)))
        }
    }

    /// The roster (D-a: never `CachePublication.hidden`) and its signature.
    /// The menu edge is read, the notch is not: a long menu changes nothing
    /// but the checks owed (D-e).
    private func sample(appState: AppState, screen: NSScreen, menuMaxX: CGFloat?) -> IceBarHidingSample {
        let roster = appState.itemManager.iceBarRoster.rules
        let signature = roster.signature(
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            menuMaxX: menuMaxX.map(Double.init),
            displayID: screen.displayID,
            spaceID: UInt64(truncatingIfNeeded: appState.activeSpace.spaceID)
        )
        let isMouseOnBar = appState.hidEventManager.isMouseInsideMenuBar(appState: appState, screen: screen)
        return IceBarHidingSample(
            signature: signature,
            preconditions: roster.preconditions,
            membership: roster.membership,
            isInteracting: isMouseOnBar || appState.navigationState.isIceBarPresented,
            isDragging: appState.isDraggingMenuBarItem,
            boundaryUsable: appState.itemManager.hiddenBoundaryUsable
        )
    }

    /// In IceBar mode the dividers stay at `.hideSection` (`MenuBarSection.show`
    /// keeps them there), and the calibrated length applies only then. Some
    /// paths leave them shown: IceBar mode turned on while the section was
    /// shown, or a Command-drag that showed every section and ended. Put them
    /// back, except during a drag (Codex review of plan 9.3 and of the code).
    private func keepDividersHidden(appState: AppState) {
        guard
            appState.settings.general.useIceBar,
            !appState.isDraggingMenuBarItem,
            let hidden = appState.menuBarManager.section(withName: .hidden),
            hidden.controlItem.state == .showSection
        else {
            return
        }
        hidden.hide()
    }

    // MARK: - Commands

    private func execute(_ command: IceBarHidingCommand) {
        guard let appState else {
            return
        }
        switch command {
        case .setLength(let length):
            appState.menuBarManager.controlItem(withName: .hidden)?.calibratedHiddenLength = length.map { CGFloat($0) }
        case .takeBaseline(let token, let members, let ready):
            takeBaseline(token: token, members: members, ready: ready)
        case .observe(let token, let length):
            observe(token: token, length: length)
        case .report(let status):
            logger.info("IceBar hiding: \(status.logSummary, privacy: .public)")
            appState.hidingCheckStatus = status.message.map(HidingCheckStatus.init(message:))
        }
    }

    /// A baseline of the roster the machine sampled (its tags as the section
    /// map), and whether it covers every ready member.
    private func takeBaseline(token: Int, members: [TagKey], ready: [ItemKey]) {
        let sectionMap = Dictionary(members.map { ($0, ItemSection.hidden) }, uniquingKeysWith: { first, _ in first })
        let observer = currentObserver()
        work?.cancel()
        work = Task {
            let coverage = await observer?.takeBaseline(sectionMap: sectionMap)
            let ok = await observer?.covers(ready) ?? false
            // Reasons and counts, no item names.
            if !Task.isCancelled {
                logger.info("IceBar baseline: ok \(ok, privacy: .public) coverage \(coverage?.description ?? "noObserver", privacy: .public)")
            }
            send(.baseline(token: token, ok: ok))
        }
    }

    private func observe(token: Int, length: Double) {
        let observer = currentObserver()
        work?.cancel()
        work = Task {
            let reading = await observer?.observe() ?? .nothing
            if !Task.isCancelled {
                let summary = VerificationSummary.make(reading.checks)
                let chevron = reading.chevronListed.map(String.init) ?? "unread"
                logger.info(
                    """
                    IceBar trial: length \(length, privacy: .public) hidden \(summary.hidden, privacy: .public) \
                    drawn \(summary.stillDrawn, privacy: .public) of \(reading.checks.count, privacy: .public) \
                    chevron \(chevron, privacy: .public)
                    """
                )
            }
            send(.observed(token: token, checks: reading.checks, chevronListed: reading.chevronListed))
        }
    }

    private func currentObserver() -> HiddenLengthObserver? {
        guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
            return nil
        }
        if let observer, observer.displayID == screen.displayID {
            return observer.observer
        }
        guard let fresh = HiddenLengthObserver.live(screen: screen, ownIdentifiers: .ice) else {
            return nil
        }
        observer = (screen.displayID, fresh)
        return fresh
    }
}
