// The harness's own raw, read-only Accessibility read of one helper process
// (2026-09-23 plan, T8a: "a raw AX read for CFEqual"; section 6 step 4 and
// steps 9-10). Unlike `LiveExtrasReader` it keeps the child elements, so two
// reads can be compared with `CFEqual`, and it reports every raw `AXError`.
// Never writes an attribute, never performs an action.
import ApplicationServices
import Foundation
import MenuBarDiscovery

struct RawAXChild {
    let element: AXUIElement
    let identifier: String?
    let identifierError: AXError
    let frame: CGRect?
    let frameError: AXError

    func record() -> [String: Any] {
        [
            "identifier": identifier ?? NSNull(),
            "identifierError": AXErrorNames.name(identifierError),
            "frame": frame.map { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] } ?? NSNull(),
            "frameError": AXErrorNames.name(frameError),
        ]
    }
}

struct RawAXRead {
    let extrasError: AXError
    let childrenError: AXError?
    let children: [RawAXChild]
    let elapsedMs: Double

    func record() -> [String: Any] {
        [
            "extrasError": AXErrorNames.name(extrasError),
            "childrenError": childrenError.map { AXErrorNames.name($0) } ?? NSNull(),
            "children": children.map { $0.record() },
            "elapsedMs": elapsedMs,
        ]
    }
}

enum RawAX {
    static let timeout: Float = 0.25

    static func read(pid: pid_t) -> RawAXRead {
        let start = DispatchTime.now()
        func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000 }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        var barValue: CFTypeRef?
        let barError = AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &barValue)
        guard barError == .success, let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID() else {
            return RawAXRead(extrasError: barError, childrenError: nil, children: [], elapsedMs: elapsed())
        }
        let bar = barValue as! AXUIElement
        AXUIElementSetMessagingTimeout(bar, timeout)
        var childrenValue: CFTypeRef?
        let childrenError = AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenValue)
        let elements = (childrenValue as? [AXUIElement]) ?? []
        let children = elements.map { element -> RawAXChild in
            AXUIElementSetMessagingTimeout(element, timeout)
            var identifierValue: CFTypeRef?
            let identifierError = AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &identifierValue)
            var frameValue: CFTypeRef?
            let frameError = AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameValue)
            var frame: CGRect?
            if frameError == .success, let frameValue, CFGetTypeID(frameValue) == AXValueGetTypeID() {
                var rect = CGRect.zero
                AXValueGetValue(frameValue as! AXValue, .cgRect, &rect)
                frame = rect
            }
            return RawAXChild(element: element, identifier: identifierValue as? String, identifierError: identifierError, frame: frame, frameError: frameError)
        }
        return RawAXRead(extrasError: barError, childrenError: childrenError, children: children, elapsedMs: elapsed())
    }
}
