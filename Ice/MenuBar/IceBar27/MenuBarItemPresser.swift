//
//  MenuBarItemPresser.swift
//  Ice
//

import ApplicationServices
import Foundation
import IceCore

/// Opens a menu bar item from the IceBar on macOS 27 by pressing it over
/// Accessibility while it stays pushed off the bar (plan
/// 2026-10-03-icebar-build, D3 and 9.5; T0 spike B: 5/5). No fallback.
@available(macOS 27, *)
enum MenuBarItemPresser {
    /// For each attribute read, as `LiveMenuBarAXReader` reads them.
    private static let readTimeout: Float = 0.25
    /// The press returns only when a menu it opened closes (T0), so the
    /// timeout is long; `PressOutcome` reads a late timeout as that menu.
    private static let pressTimeout: Float = 60

    static func press(_ key: ItemKey) async -> PressOutcome {
        await withCheckedContinuation { continuation in
            // Not a serial queue: one item's open menu must not hold up the next press.
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: pressNow(key))
            }
        }
    }

    private static func pressNow(_ key: ItemKey) -> PressOutcome {
        let app = AXUIElementCreateApplication(key.pid)
        AXUIElementSetMessagingTimeout(app, readTimeout)
        guard
            let bar = element(app, "AXExtrasMenuBar"),
            let children = elements(bar, kAXChildrenAttribute)
        else {
            return .failed
        }
        let identifiers = children.map { child -> String? in
            AXUIElementSetMessagingTimeout(child, readTimeout)
            guard string(child, kAXRoleAttribute) == "AXMenuBarItem" else {
                return nil
            }
            return string(child, "AXIdentifier") ?? ""
        }
        guard let index = PressTargetRule.index(for: key, identifiers: identifiers) else {
            return .failed
        }
        let target = children[index]
        AXUIElementSetMessagingTimeout(target, pressTimeout)
        let start = ProcessInfo.processInfo.systemUptime
        let error = AXUIElementPerformAction(target, kAXPressAction as CFString)
        return PressOutcome.classify(
            succeeded: error == .success,
            timedOut: error == .cannotComplete,
            elapsed: ProcessInfo.processInfo.systemUptime - start
        )
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        // swiftlint:disable:next force_cast
        return (value as! AXUIElement)
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
