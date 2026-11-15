//
//  MenuBarItemPresser.swift
//  Ice
//

import ApplicationServices
import Foundation
import IceCore
import MenuBarDiscovery

/// Opens a menu bar item from the IceBar on macOS 27 by pressing it over
/// Accessibility while it stays pushed off the bar (plan
/// 2026-10-03-icebar-build, D3 and 9.5; T0 spike B: 5/5 on 27.0.1). Where a
/// pushed-off item is not listed (27.2) the press answers `.notListed` and
/// the coordinator shows the section for it (plan 2026-11-15-blind-at-length, D3).
@available(macOS 27, *)
enum MenuBarItemPresser {
    /// For each attribute read, as `LiveMenuBarAXReader` reads them.
    private static let readTimeout: Float = 0.25
    /// The press returns only when a menu it opened closes (T0), so the
    /// timeout is long; `PressOutcome` reads a late timeout as that menu.
    private static let pressTimeout: Float = 60

    /// What asking for a press came to.
    enum Attempt: Equatable {
        /// The item is in no read: its app has no extras bar, or no child
        /// the key names. On macOS 27.2 that is every item pushed off the
        /// bar (plan 2026-11-15-blind-at-length, F3); nothing was pressed.
        case notListed
        case pressed(PressOutcome)
    }

    /// An item's element as found, to be pressed at once.
    struct Target: @unchecked Sendable {
        fileprivate let element: AXUIElement
    }

    /// Finds the item and presses it where it is.
    static func press(_ key: ItemKey) async -> Attempt {
        guard let target = await find(key) else {
            return .notListed
        }
        return .pressed(await press(target))
    }

    /// The item's element now, or `nil` when it is not listed.
    static func find(_ key: ItemKey) async -> Target? {
        await onGlobalQueue { findNow(key) }
    }

    static func press(_ target: Target) async -> PressOutcome {
        await onGlobalQueue { pressNow(target) }
    }

    private static func onGlobalQueue<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            // Not a serial queue: one item's open menu must not hold up the next press.
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: body())
            }
        }
    }

    private static func findNow(_ key: ItemKey) -> Target? {
        let app = AXUIElementCreateApplication(key.pid)
        AXUIElementSetMessagingTimeout(app, readTimeout)
        guard let bar = element(app, "AXExtrasMenuBar") else {
            return nil
        }
        // Type-checked one by one: another process chose these values.
        let children = LiveExtrasReader.childElements(attribute(bar, kAXChildrenAttribute))
        let identifiers = children.map { child -> String? in
            AXUIElementSetMessagingTimeout(child, readTimeout)
            // The rule a discovery pass used to mark this cell pressable.
            return PressTargetRule.identifier(role: string(child, kAXRoleAttribute), identifier: string(child, "AXIdentifier"))
        }
        guard let index = PressTargetRule.index(for: key, identifiers: identifiers) else {
            return nil
        }
        return Target(element: children[index])
    }

    private static func pressNow(_ target: Target) -> PressOutcome {
        AXUIElementSetMessagingTimeout(target.element, pressTimeout)
        let start = ProcessInfo.processInfo.systemUptime
        let error = AXUIElementPerformAction(target.element, kAXPressAction as CFString)
        return PressOutcome.classify(
            succeeded: error == .success,
            timedOut: error == .cannotComplete,
            elapsed: ProcessInfo.processInfo.systemUptime - start
        )
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }
}
