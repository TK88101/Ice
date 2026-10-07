//
//  MenuBarOwner.swift
//  Ice
//

import Cocoa
import Combine
import MenuBarDetectorFeed

/// The menu bar owner's pid on macOS 27, for `NSScreen.getApplicationMenuFrame()`
/// (plan 2026-10-07-icebar-menu-frame-fix, F1): the frame is read on the main
/// thread and from detached tasks, so it is never asked of `NSWorkspace` at the
/// call. `AppState` starts and owns the observation.
@available(macOS 27, *)
enum MenuBarOwner {
    static let pid = MenuBarOwnerPID(initial: nil)

    /// Reads the current owner at once (a cold launch has no change to wait
    /// for), then follows every change on the main actor.
    @MainActor
    static func observe() -> AnyCancellable {
        pid.update(NSWorkspace.shared.menuBarOwningApplication?.processIdentifier)
        return NSWorkspace.shared.publisher(for: \.menuBarOwningApplication, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { app in
                pid.update(app?.processIdentifier)
            }
    }
}
