import Darwin
import IceCore
import os

/// One child of an app's `AXMenuBar`, as far as the frame needs it.
public struct ApplicationMenuChild: Equatable, Sendable {
    public let isEnabled: Bool
    /// `nil` when the frame could not be read.
    public let frame: BarRect?

    public init(isEnabled: Bool, frame: BarRect?) {
        self.isEnabled = isEnabled
        self.frame = frame
    }
}

/// The Accessibility read behind `ApplicationMenuReader`, so a fake can drive
/// its tests.
public protocol ApplicationMenuAXReading: Sendable {
    /// The children of `pid`'s `AXMenuBar`, every element read with `timeout`;
    /// `nil` when the menu bar itself could not be read.
    func menuBarChildren(pid: pid_t, timeout: Double) -> [ApplicationMenuChild]?
}

/// The application menu's frame on macOS 27 (plan
/// 2026-10-07-icebar-menu-frame-fix, F1): read from the menu bar owner's own
/// `AXMenuBar`. Upstream's hit test at the display origin returns a
/// `MenuBarAgent` window there (E5), so it never reaches the menu bar.
public struct ApplicationMenuReader: Sendable {
    /// Per element, as `vzhelper`'s `selfRead`.
    public static let messagingTimeout = 0.25

    public static let live = ApplicationMenuReader(reader: LiveApplicationMenuAXReader())

    private let reader: any ApplicationMenuAXReading

    public init(reader: any ApplicationMenuAXReading) {
        self.reader = reader
    }

    /// The union of the enabled children's frames; a child without a usable
    /// frame is skipped on its own. `nil` for no owner, no menu bar, no usable
    /// child or no width.
    public func frame(owningPID: pid_t?) -> BarRect? {
        guard let owningPID, let children = reader.menuBarChildren(pid: owningPID, timeout: Self.messagingTimeout) else {
            return nil
        }
        let frames = children.compactMap { child in
            child.isEnabled ? child.frame.flatMap(Self.usable) : nil
        }
        guard let first = frames.first else {
            return nil
        }
        let union = frames.dropFirst().reduce(first, Self.union)
        return union.width > 0 ? union : nil
    }

    private static func usable(_ frame: BarRect) -> BarRect? {
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) ? frame : nil
    }

    private static func union(_ lhs: BarRect, _ rhs: BarRect) -> BarRect {
        let minX = min(lhs.minX, rhs.minX)
        let minY = min(lhs.minY, rhs.minY)
        let maxX = max(lhs.maxX, rhs.maxX)
        let maxY = max(lhs.minY + lhs.height, rhs.minY + rhs.height)
        return BarRect(minX: minX, minY: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// The menu bar owner's pid, readable from any thread (plan F1, threading):
/// the frame is read on the main thread and from detached tasks, so callers
/// never ask `NSWorkspace` at the call. Ice creates it with the current owner
/// and keeps it up to date.
public final class MenuBarOwnerPID: Sendable {
    private let state: OSAllocatedUnfairLock<pid_t?>

    public init(initial: pid_t?) {
        state = OSAllocatedUnfairLock(initialState: initial)
    }

    public var current: pid_t? {
        state.withLock { $0 }
    }

    public func update(_ pid: pid_t?) {
        state.withLock { $0 = pid }
    }
}
