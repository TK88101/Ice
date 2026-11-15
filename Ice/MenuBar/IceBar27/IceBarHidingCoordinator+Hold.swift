//
//  IceBarHidingCoordinator+Hold.swift
//  Ice
//

import Cocoa
import IceCore
import OSLog

/// The hold of the bar at standard length on a system that lists no item
/// pushed off the bar (macOS 27.2; plan 2026-11-15-blind-at-length, D3, D4):
/// a hidden item is pressed on the bar, or the bar is read once before the
/// IceBar opens. `IceBarHold` decides; this carries it out. The machine stays
/// the one writer of the length: while a hold is held its samples say so.
@available(macOS 27, *)
extension IceBarHidingCoordinator {
    /// How long a press waits for its item to be listed after the retire
    /// (MEASURED: listed within 0.2 s).
    private static let pressWait = 2.0
    /// How long a re-read waits for a trusted pass (the divider's settle and
    /// one pass), and then for the length.
    private static let rereadWait = 4.0
    private static let reapplyWait = 2.0
    private static let lookupInterval: Duration = .milliseconds(50)
    private static let windowLookInterval: Duration = .milliseconds(250)
    private static let showingLookInterval: Duration = .milliseconds(500)

    private var uptime: Double {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: The one release

    /// Every ending passes through here (`IceBarHold.release`): a token that
    /// is not the current one changes nothing.
    @discardableResult
    private func release(_ token: Int, _ ending: IceBarHold.Ending) -> Bool {
        guard hold.release(token, ending) else {
            return false
        }
        logger.info("IceBar hold \(token, privacy: .public): ended \(String(describing: ending), privacy: .public)")
        if deferredOpening?.token == token, ending != .finished {
            deferredOpening = nil
        }
        return true
    }

    /// Ends whatever hold is current: IceBar mode went off.
    func endHold(_ ending: IceBarHold.Ending) {
        if let token = hold.current?.token {
            release(token, ending)
        }
    }

    /// Once a tick, before the sample: what ends the hold by itself, and the
    /// trusted pass a re-read waits for.
    func advanceHold(isArranging: Bool, appState: AppState) {
        guard let current = hold.current else {
            return
        }
        let manager = appState.itemManager
        let ending = hold.due(
            now: uptime, isDragging: isArranging, isModeOn: appState.settings.general.useIceBar,
            members: manager.iceBarRoster.rules.membership.members.map(\.tag)
        )
        if let ending {
            release(current.token, ending)
            return
        }
        if
            let began = manager.lastTrustedPassBeganAt,
            hold.passed(current.token, beganAt: began, trusted: true, now: uptime, reapply: Self.reapplyWait)
        {
            logger.info("IceBar hold \(current.token, privacy: .public): the bar was read, letting it go")
        }
    }

    // MARK: A press on the bar (D3)

    /// Shows the section, presses the member on the bar, and lets the machine
    /// hide again once what the press opened no longer shows. `nil`: called
    /// off before anything was pressed (a press already under way, a drag,
    /// the mode), which says nothing of the cell.
    func pressOnBar(_ key: ItemKey, tag: TagKey) async -> PressOutcome? {
        guard isModeOn, let token = hold.begin(.press(tag), now: uptime, wait: Self.pressWait) else {
            return nil
        }
        logger.info("IceBar hold \(token, privacy: .public): a press, showing the section")
        tick()
        guard let target = await listedTarget(key, token: token) else {
            if hold.isCurrent(token) {
                release(token, .deadline)
                tick()
            }
            // Not listed in time is the press's failure; any other ending called it off.
            let missedDeadline = hold.lastEnded?.token == token && hold.lastEnded?.ending == .deadline
            return missedDeadline ? .failed : nil
        }
        guard hold.dispatched(token) else {
            return nil
        }
        heldPress = (token, key.pid, Set(OpenedInterfaceWatcher.onScreenWindows().map(\.id)), nil)
        let outcome = await pressWatchingWindows(target, token: token)
        // A popover's press returns before the popover is up: one more look.
        if heldPress?.token == token, heldPress?.opened == nil {
            try? await Task.sleep(for: Self.windowLookInterval)
            lookForOpenedWindow(token)
        }
        let opened = heldPress?.token == token ? heldPress?.opened : nil
        if heldPress?.token == token {
            heldPress = nil
        }
        if let opened, hold.returned(token, showing: OpenedInterfaceWatcher.isShowing(opened)) {
            while hold.isCurrent(token), hold.current?.phase == .showing, OpenedInterfaceWatcher.isShowing(opened) {
                try? await Task.sleep(for: Self.showingLookInterval)
            }
        }
        await finishHold(token)
        return outcome
    }

    /// The item's element once it is listed, asked for until the hold's
    /// deadline; `nil` when the deadline passed or the hold ended otherwise.
    private func listedTarget(_ key: ItemKey, token: Int) async -> MenuBarItemPresser.Target? {
        while hold.isCurrent(token), case .waiting(let deadline)? = hold.current?.phase {
            if let target = await MenuBarItemPresser.find(key) {
                return hold.isCurrent(token) ? target : nil
            }
            guard uptime < deadline else {
                return nil
            }
            try? await Task.sleep(for: Self.lookupInterval)
        }
        return nil
    }

    /// The press, and while it is out a look at the windows every quarter
    /// second: what it opened is found in its own interval.
    private func pressWatchingWindows(_ target: MenuBarItemPresser.Target, token: Int) async -> PressOutcome {
        await withTaskGroup(of: PressOutcome?.self) { group in
            group.addTask {
                await MenuBarItemPresser.press(target)
            }
            group.addTask { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.lookForOpenedWindow(token)
                    try? await Task.sleep(for: Self.windowLookInterval)
                }
                return nil
            }
            var outcome = PressOutcome.failed
            for await result in group {
                if let result {
                    outcome = result
                    group.cancelAll()
                }
            }
            return outcome
        }
    }

    private func lookForOpenedWindow(_ token: Int) {
        guard var press = heldPress, press.token == token, press.opened == nil else {
            return
        }
        press.opened = OpenedInterfaceRule.opened(by: press.pid, in: OpenedInterfaceWatcher.onScreenWindows(), before: press.before)
        heldPress = press
    }

    /// A hold that ran its course: one pass of the bar as it is now, the
    /// token checked again after it, the release, then the machine.
    private func finishHold(_ token: Int) async {
        guard hold.isCurrent(token) else {
            return
        }
        await appState?.itemManager.cacheItemsRegardless()
        if release(token, .finished) {
            tick()
        }
    }

    // MARK: A re-read before the IceBar opens (D4)

    /// `MenuBarSection.show()` asks before it opens the IceBar. `true`: a
    /// re-read is owed (`ArrivalRule`), so the bar is read once at standard
    /// length first and the coordinator opens the IceBar after it.
    func defersOpening(of section: MenuBarSection.Name) -> Bool {
        guard
            !isOpeningDeferred, isLengthApplied, let manager = appState?.itemManager, manager.sawBlindPass,
            ArrivalRule.isRereadOwed(lastLaunchAt: lastLaunchAt, trustedPassBeganAt: manager.lastTrustedPassBeganAt),
            let token = hold.begin(.reread, now: uptime, wait: Self.rereadWait)
        else {
            return false
        }
        deferredOpening = (token, section)
        logger.info("IceBar hold \(token, privacy: .public): a re-read before the IceBar opens")
        tick()
        return true
    }

    /// After a sample: the re-read's hold has let the bar go and the length
    /// is applied again, so the IceBar opens. Its token is spent by the
    /// release, so it opens once.
    func openDeferredIfApplied() {
        guard
            let opening = deferredOpening, case .reapplying? = hold.current?.phase, isLengthApplied,
            release(opening.token, .finished)
        else {
            return
        }
        deferredOpening = nil
        isOpeningDeferred = true
        defer {
            isOpeningDeferred = false
        }
        appState?.menuBarManager.section(withName: opening.section)?.show()
    }
}
