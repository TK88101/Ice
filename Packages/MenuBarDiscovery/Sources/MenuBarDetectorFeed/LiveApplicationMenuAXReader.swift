import ApplicationServices
import Darwin
import IceCore
import MenuBarDiscovery

/// The live read: the app element's `AXMenuBar`, its children, and each
/// child's enabled flag and frame, with the messaging timeout set on every
/// element (it does not carry over from one element to the next).
struct LiveApplicationMenuAXReader: ApplicationMenuAXReading {
    func menuBarChildren(pid: pid_t, timeout: Double) -> [ApplicationMenuChild]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Float(timeout))
        var barValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &barValue) == .success,
            let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let bar = unsafeDowncast(barValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(bar, Float(timeout))
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenValue) == .success else {
            return nil
        }
        return LiveExtrasReader.childElements(childrenValue).prefix(LiveExtrasReader.maxChildren).map { child in
            AXUIElementSetMessagingTimeout(child, Float(timeout))
            return ApplicationMenuChild(isEnabled: Self.isEnabled(child), frame: Self.frame(child))
        }
    }

    private static func isEnabled(_ child: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) == true
    }

    private static func frame(_ child: AXUIElement) -> BarRect? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(child, "AXFrame" as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgRect, &rect) else {
            return nil
        }
        return BarRect(rect)
    }
}
