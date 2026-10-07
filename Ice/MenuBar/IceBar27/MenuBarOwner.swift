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

    /// Follows the owner. `.initial` delivers the current one synchronously,
    /// inside this call, so a cold launch with no change has a pid at once; the
    /// holder is locked, so a change may arrive on any thread.
    @MainActor
    static func observe() -> AnyCancellable {
        NSWorkspace.shared.publisher(for: \.menuBarOwningApplication, options: [.initial, .new])
            .sink { app in
                pid.update(app?.processIdentifier)
            }
    }
}
