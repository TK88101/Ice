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
/// 2026-10-03-icebar-build, D1 and 9.3): samples the layout once a second,
/// carries out the machine's commands, and while resting watches, by
/// Accessibility alone, for a `«`.
@available(macOS 27, *)
@MainActor
final class IceBarHidingCoordinator {
    private static let tickInterval: TimeInterval = 1

    private weak var appState: AppState?
    private var machine = IceBarHidingMachine()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// The baseline or observation under way.
    private var work: Task<Void, Never>?
    private var isSampling = false
    private var isWatching = false

    private var observer: (displayID: CGDirectDisplayID, observer: HiddenLengthObserver)?
    private var chevron: (displayID: CGDirectDisplayID, reader: ChevronReader)?

    private let logger = Logger(category: "IceBarHiding")

    /// Whether the hidden section is hidden at a calibrated length, so the
    /// IceBar may be offered.
    var isResting: Bool {
        if case .resting = machine.phase { true } else { false }
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
            .sink { [weak self] isIceBar in
                self?.send(.mode(isIceBar: isIceBar))
            }
            .store(in: &cancellables)
        timer = .scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    // MARK: - Events

    private func send(_ event: IceBarHidingEvent) {
        let (next, commands) = machine.step(event, now: ProcessInfo.processInfo.systemUptime)
        machine = next
        for command in commands {
            execute(command)
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
            send(.sample(sample(appState: appState, screen: screen, menuMaxX: menuMaxX)))
            if isResting {
                watchChevron(screen: screen)
            }
        }
    }

    private func sample(appState: AppState, screen: NSScreen, menuMaxX: CGFloat?) -> IceBarHidingSample {
        let cache = appState.itemManager.itemCache
        func ids(_ name: MenuBarSection.Name) -> [String] {
            cache[name].map { String(describing: $0.id) }
        }
        let menuEdge = menuMaxX.map(Double.init)
        let signature = LayoutSignature(
            visible: ids(.visible),
            hidden: ids(.hidden),
            alwaysHidden: ids(.alwaysHidden),
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            menuMaxX: menuEdge,
            displayID: screen.displayID,
            spaceID: UInt64(truncatingIfNeeded: appState.activeSpace.spaceID)
        )
        let isMouseOnBar = appState.hidEventManager.isMouseInsideMenuBar(appState: appState, screen: screen)
        return IceBarHidingSample(
            signature: signature,
            menuVerdict: MenuWidthRule.verdict(menuMaxX: menuEdge, notchMinX: screen.frameOfNotch.map { Double($0.minX) }),
            isInteracting: isMouseOnBar || appState.navigationState.isIceBarPresented,
            isDragging: appState.isDraggingMenuBarItem,
            boundaryUsable: appState.itemManager.hiddenBoundaryUsable,
            memberCount: cache[.hidden].count
        )
    }

    private func watchChevron(screen: NSScreen) {
        guard !isWatching, let reader = chevronReader(for: screen) else {
            return
        }
        isWatching = true
        Task {
            let listed = await reader.chevronListed()
            isWatching = false
            if listed == true, isResting {
                logger.info("A fold appeared at rest; showing the hidden section")
                send(.chevronSeenAtRest)
            }
        }
    }

    // MARK: - Commands

    private func execute(_ command: IceBarHidingCommand) {
        guard let appState else {
            return
        }
        switch command {
        case .setLength(let length):
            appState.menuBarManager.controlItem(withName: .hidden)?.calibratedHiddenLength = length.map { CGFloat($0) }
        case .takeBaseline(let token):
            let sectionMap = appState.itemManager.discoveredSectionMap
            let observer = currentObserver()
            work?.cancel()
            work = Task {
                let ok = await observer?.takeBaseline(sectionMap: sectionMap) ?? false
                send(.baseline(token: token, ok: ok))
            }
        case .observe(let token, _):
            let observer = currentObserver()
            work?.cancel()
            work = Task {
                let outcome = await observer?.observe() ?? .unknown
                send(.observed(token: token, outcome: outcome))
            }
        case .report(let status):
            logger.info("IceBar hiding: \(String(describing: status), privacy: .public)")
            appState.hidingCheckStatus = status.message.map(HidingCheckStatus.init(message:))
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

    private func chevronReader(for screen: NSScreen) -> ChevronReader? {
        if let chevron, chevron.displayID == screen.displayID {
            return chevron.reader
        }
        guard let fresh = ChevronReader.live(screen: screen) else {
            return nil
        }
        chevron = (screen.displayID, fresh)
        return fresh
    }
}
