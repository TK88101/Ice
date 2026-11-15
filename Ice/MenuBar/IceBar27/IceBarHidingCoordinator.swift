//
//  IceBarHidingCoordinator.swift
//  Ice
//

import Cocoa
import Combine
import IceCore
import MenuBarCover
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

    /// After the length became standard, or a drag ended, the divider must
    /// stand collapsed this long before a pass may decide the sections
    /// (`DiscoveredCachePlan.settleSeconds`), and a little more.
    private static let rereadDelay: Duration = .milliseconds(Int(DiscoveredCachePlan.settleSeconds * 1000) + 150)

    private weak var appState: AppState?
    /// Hide at once, unverified, unless the lab asks for the checks (plan
    /// 2026-11-12-hide-at-once).
    private var machine = IceBarHidingMachine(parameters: LabReport.verifiesHiding ? .standard : .unverified)
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// The baseline or observation under way.
    private var work: Task<Void, Never>?
    /// The early re-read under way: see `rereadSoon`.
    private var reread: Task<Void, Never>?
    /// The last sample found the owner arranging (`IceBarArrangingRule`).
    private var wasArranging = false
    /// A Command-drag began since the last sample. The machine is sampled
    /// once a second, and a drag can begin and end between two samples: it
    /// would then never retire the length, the dropped item would be pushed
    /// off with the members and listed nowhere (run 20261112-184440-free: an
    /// item of the owner's, gone from the bar and absent from the IceBar).
    /// So a drag that began is reported by the next sample whatever its end.
    private var dragBegan = false
    /// When the owner last stopped arranging: until a pass that began later
    /// has read the bar (`MenuBarItemManager.lastPassBeganAt`), the machine
    /// is told the owner still has it (`IceBarArrangingRule.holdsBarForOwner`).
    private var arrangingEndedAt: Double?
    /// Command pressed or released: the machine hears of it now, not at the next tick.
    private lazy var flagsMonitor = EventMonitor.universal(for: .flagsChanged) { [weak self] event in
        Task { @MainActor in
            self?.tick()
        }
        return event
    }
    private var isSampling = false

    private var observer: (displayID: CGDirectDisplayID, observer: HiddenLengthObserver)?

    /// Covers the members a bar still draws at the applied length: a bar
    /// without a notch draws them at every length (plan 2026-11-15-cover).
    private let cover = CoverController(
        reader: LiveCoverBarReader(), capturer: LiveCoverCapturer(), presenter: CoverPanelPresenter(),
        environment: .live(backgroundKey: IceBarHidingCoordinator.coverBackgroundKey, canCapture: { ScreenCapture.cachedCheckPermissions() })
    )
    /// The display that had the active menu bar at the last tick.
    private var activeDisplayID: CGDirectDisplayID?
    /// The machine's last status line for the owner; the cover's notice is said after it.
    private var statusMessage: OwnerMessage?

    static let coverNoScreenRecording = "Ice needs Screen Recording to hide items on a display that would still show them."
    static let coverBarNotTransparent = "A display's menu bar is not transparent, so Ice cannot hide items on it."

    private let logger = Logger(category: "IceBarHiding")

    /// Whether Ice rests at a length, so the IceBar may be offered.
    var isLengthApplied: Bool {
        machine.lengthApplied
    }

    /// What the lab report reads of the machine (S4 design D1).
    var labFacts: LabReportMachineFacts {
        machine.labFacts
    }

    /// The last sample's `isInteracting`, for the lab report.
    private(set) var isInteracting = false

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
        // A pass changed the roster: the machine hears of it now, not at the next tick.
        appState.itemManager.$iceBarRoster
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tick()
            }
            .store(in: &cancellables)
        // A drag begins: the real divider and the members are given back
        // now. It ends: the owner expects the item hidden now, not at the
        // next pass.
        appState.hidEventManager.$isDraggingMenuBarItem
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak appState] isDragging in
                guard let self, let appState else {
                    return
                }
                if isDragging {
                    dragBegan = true
                    tick()
                } else {
                    keepDividersHidden(appState: appState)
                    tick()
                }
            }
            .store(in: &cancellables)
        cover.onReport = { [logger] reports, generation in
            // Displays and counts, no item names.
            let blocks = reports.map { "\($0.displayID):\($0.blocks.count)/\($0.verified.count)" }.joined(separator: " ")
            logger.info("IceBar cover: generation \(generation, privacy: .public) blocks/verified \(blocks, privacy: .public)")
            LabReport.record(.cover(generation: generation, bars: reports.map { report in
                LabReportCoverBar(
                    display: report.displayID, slots: report.slots, verified: report.verified, blocks: report.blocks,
                    ignoredMilliseconds: report.ignoredMilliseconds
                )
            }))
        }
        // What can change a bar's background with no key saying so (plan D2).
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        Publishers.MergeMany([
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification),
            workspace.publisher(for: NSWorkspace.didWakeNotification),
            workspace.publisher(for: NSWorkspace.screensDidWakeNotification),
            workspace.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification),
            distributed.publisher(for: Notification.Name("com.apple.screensaver.didstop")),
            distributed.publisher(for: Notification.Name("com.apple.screenIsUnlocked")),
        ])
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.cover.invalidateBackgrounds()
        }
        .store(in: &cancellables)
        timer = .scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer?.tolerance = Self.tickTolerance
        flagsMonitor.start()
    }

    // MARK: - Events

    private func send(_ event: IceBarHidingEvent) {
        let (next, commands) = machine.step(event, now: ProcessInfo.processInfo.systemUptime)
        machine = next
        for command in commands {
            execute(command)
        }
        // Work nobody waits for must not capture later, in the owner's
        // interaction: a session can wait some twenty seconds for a clear bar.
        if !machine.awaitsAnswer {
            work?.cancel()
            work = nil
        }
        // At standard length the items are back on the bar: an open IceBar would list them twice.
        if !isLengthApplied, let appState, appState.navigationState.isIceBarPresented {
            appState.menuBarManager.iceBarPanel.close()
        }
        syncCover()
    }

    /// The cover is on exactly while Ice rests with a length applied, over
    /// the roster's members (plan 2026-11-15-cover, D4); its notice follows
    /// the machine's status line.
    private func syncCover() {
        guard let appState else {
            return
        }
        let isActive = isLengthApplied && appState.settings.general.useIceBar
        cover.sync(active: isActive, coverable: isActive ? appState.itemManager.coverableOwners : [])
        let notice: OwnerMessage? = switch isActive ? cover.notice : nil {
        case .noScreenRecording: OwnerMessage(Self.coverNoScreenRecording)
        case .barNotTransparent: OwnerMessage(Self.coverBarNotTransparent)
        case nil: nil
        }
        let message: OwnerMessage? = switch (statusMessage, notice) {
        case (let status?, let notice?): OwnerMessage("%@ %@", .message(status), .message(notice))
        case (let status?, nil): status
        case (nil, let notice): notice
        }
        let status = message.map(HidingCheckStatus.init(message:))
        if appState.hidingCheckStatus != status {
            appState.hidingCheckStatus = status
        }
    }

    /// What a bar's background depends on besides the windows under it: the
    /// display's Space, light or dark, and the wallpaper store's date.
    private static func coverBackgroundKey(_ bar: CoverBar) -> String {
        let space = SpaceInfo.currentSpace(for: bar.displayID)?.spaceID ?? 0
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let store = NSHomeDirectory() + "/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
        let stamp = (try? FileManager.default.attributesOfItem(atPath: store)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(space)|\(isDark)|\(stamp)"
    }

    /// The items are back on the bar at standard length, and stay there until
    /// a pass has read them against the settled divider: the passes come
    /// every five seconds, so one is run as soon as the divider has settled,
    /// and the machine is sampled right after it.
    private func rereadSoon() {
        reread?.cancel()
        reread = Task { [weak self] in
            try? await Task.sleep(for: Self.rereadDelay)
            guard !Task.isCancelled, let self, let appState = self.appState, !appState.isDraggingMenuBarItem else {
                return
            }
            await appState.itemManager.cacheItemsRegardless()
            guard !Task.isCancelled else {
                return
            }
            self.tick()
        }
    }

    private func tick() {
        cover.tick()
        guard machine.phase != .off, !isSampling, let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
            return
        }
        // The other display's bar became the active one: the cover is verified again at once (D5).
        if screen.displayID != activeDisplayID {
            if activeDisplayID != nil { cover.activeDisplayChanged() }
            activeDisplayID = screen.displayID
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
            let isMouseOnBar = appState.hidEventManager.isMouseInsideMenuBar(appState: appState, screen: screen)
            let isArranging = IceBarArrangingRule.isArranging(
                isDragging: appState.isDraggingMenuBarItem || dragBegan,
                isCommandDown: NSEvent.modifierFlags.contains(.command),
                isPointerOnBar: isMouseOnBar
            )
            dragBegan = false
            // Command let go, or a drag over (this sample is the first to see
            // it, whichever it was): read the bar once what was dropped has
            // landed and the divider has settled, and hide nothing before
            // that pass (Codex review; run 20261112-192750-s6).
            if wasArranging, !isArranging {
                arrangingEndedAt = ProcessInfo.processInfo.systemUptime
                rereadSoon()
            }
            wasArranging = isArranging
            let sample = sample(
                appState: appState, screen: screen, menuMaxX: menuMaxX, isMouseOnBar: isMouseOnBar, isArranging: isArranging
            )
            isInteracting = sample.isInteracting
            send(.sample(sample))
        }
    }

    /// The roster (D-a: never `CachePublication.hidden`) and its signature.
    /// The menu edge is read, the notch is not: a long menu changes nothing
    /// but the checks owed (D-e).
    private func sample(
        appState: AppState, screen: NSScreen, menuMaxX: CGFloat?, isMouseOnBar: Bool, isArranging: Bool
    ) -> IceBarHidingSample {
        let roster = appState.itemManager.iceBarRoster.rules
        let signature = roster.signature(
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            menuMaxX: menuMaxX.map(Double.init),
            displayID: screen.displayID,
            spaceID: UInt64(truncatingIfNeeded: appState.activeSpace.spaceID)
        )
        return IceBarHidingSample(
            signature: signature,
            preconditions: roster.preconditions,
            membership: roster.membership,
            isInteracting: isMouseOnBar || appState.navigationState.isIceBarPresented,
            isDragging: IceBarArrangingRule.holdsBarForOwner(
                isArranging: isArranging, arrangingEndedAt: arrangingEndedAt,
                rereadAt: appState.itemManager.lastPassBeganAt, now: ProcessInfo.processInfo.systemUptime
            ),
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
            // Off before the length goes: no panel outlives its layout (D4).
            if length == nil { cover.sync(active: false, coverable: []) }
            appState.menuBarManager.controlItem(withName: .hidden)?.calibratedHiddenLength = LabReport.applied(length).map { CGFloat($0) }
            if length == nil {
                rereadSoon()
            }
        case .takeBaseline(let token, let members, let ready):
            takeBaseline(token: token, members: members, ready: ready)
        case .observe(let token, let length, let closesBurst):
            observe(token: token, length: length, closesBurst: closesBurst)
        case .report(let status):
            logger.info("IceBar hiding: \(status.logSummary, privacy: .public)")
            LabReport.record(.status(status.logSummary))
            statusMessage = status.ownerMessage
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

    private func observe(token: Int, length: Double, closesBurst: Bool) {
        let observer = currentObserver()
        work?.cancel()
        work = Task {
            let reading = await observer?.observe(closesBurst: closesBurst) ?? .nothing
            if !Task.isCancelled {
                let summary = VerificationSummary.make(reading.checks)
                let chevron = reading.chevronListed.map(String.init) ?? "unread"
                logger.info(
                    """
                    IceBar trial: length \(length, privacy: .public) hidden \(summary.hidden, privacy: .public) \
                    drawn \(summary.stillDrawn, privacy: .public) of \(reading.checks.count, privacy: .public) \
                    chevron \(chevron, privacy: .public) waited \(reading.waited, privacy: .public) \
                    stable \(reading.diagnostics.map { String($0.captureStable) } ?? "unread", privacy: .public)
                    """
                )
                LabReport.record(.observation(
                    length: length,
                    diagnostics: reading.diagnostics,
                    waited: reading.waited,
                    burst: reading.burst,
                    // The burst's times are the observer's clock, the system uptime.
                    sinceCapture: reading.burst.map { ProcessInfo.processInfo.systemUptime - $0.capturedAt }
                ))
            }
            send(.observed(
                token: token, checks: reading.checks, chevronListed: reading.chevronListed, burst: reading.burst,
                displaced: reading.displaced
            ))
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
