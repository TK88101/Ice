import AppKit
import ApplicationServices
import IceCore

/// Read-only walk of one process's `AXExtrasMenuBar` (plan section 4.2),
/// producing IceCore's typed `RawRead` rather than a caller-keyed snapshot
/// like `LiveMenuBarAXReader`. Sets the messaging timeout on the application
/// element, the bar element, and every child before reading it -- the SDK
/// says the application-element timeout alone does not carry over to
/// children (plan section 0, "existing AX code"), which is exactly the bug
/// this reader is written not to repeat.
///
/// Never writes an AX attribute, never performs an action; no `AXUIElement`
/// this type creates is ever returned from `read` or stored past the call
/// that produced it (plan's HARD RULES).
///
/// Untestable here (live Accessibility) -- exercised only by `mbdiscover`'s
/// smoke run.
public struct LiveExtrasReader: ExtrasReading {
    /// Apple's own bundle id for the process that owns the system's menu bar
    /// extras (matches `LiveMenuBarAXReader.menuBarAgentBundleID`).
    public static let menuBarAgentBundleID = "com.apple.MenuBarAgent"

    /// Whether each child's `AXTitle`, `AXDescription` and `AXHelp` are read.
    /// Discovery needs them for an item's display title; the detector feed
    /// needs only role, identifier and frame, so it skips the three calls per
    /// child per sample. Their values are never classified, but a failed or
    /// slow label call stops its child and so fails the process's read; a
    /// reader that skips them can therefore read a process that one reading
    /// them reports as failed, never the reverse.
    private let readsLabels: Bool

    public init(readsLabels: Bool = true) {
        self.readsLabels = readsLabels
    }

    // Plain `String`s, not `CFString` (which is not `Sendable`): each is cast
    // to `CFString` at the point of use instead of stored as one, matching
    // `LiveMenuBarAXReader`'s own style of inline string-literal casts.
    private static let extrasBarAttribute = "AXExtrasMenuBar"
    private static let childrenAttribute = kAXChildrenAttribute as String
    private static let roleAttribute = "AXRole"
    private static let identifierAttribute = "AXIdentifier"
    private static let titleAttribute = "AXTitle"
    private static let descriptionAttribute = "AXDescription"
    private static let helpAttribute = "AXHelp"
    private static let frameAttribute = "AXFrame"
    /// A placeholder error for an attribute this reader chose not to call at
    /// all: an earlier call in the same child already stopped the walk (plan
    /// section 4.2: "the remaining attributes of that child ... are not
    /// read"), or -- for the three labels only -- `readsLabels` is false.
    /// Never `noValue`/`attributeUnsupported`/`success`, so `ReadClassifier`
    /// treats it as a failure wherever it classifies the attribute; it never
    /// classifies the labels.
    private static let notAttempted = "notAttempted"

    public func read(_ process: ProcessInfoRecord, timeout: Double) -> RawRead {
        let clock = ContinuousClock()
        let slowThreshold = Duration.seconds(timeout * ReadClassifier.slowFraction)

        let app = AXUIElementCreateApplication(process.pid)
        AXUIElementSetMessagingTimeout(app, Float(timeout))

        let barStart = clock.now
        var barValue: CFTypeRef?
        let barResult = AXUIElementCopyAttributeValue(app, Self.extrasBarAttribute as CFString, &barValue)
        let barDuration = clock.now - barStart
        let barElapsed = barDuration.secondsDouble

        guard barResult == .success, barDuration < slowThreshold,
              let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID()
        else {
            let error = (barResult == .success && barDuration >= slowThreshold) ? "cannotComplete" : AXErrorNames.name(barResult)
            return RawRead(process: process, extrasError: error, extrasElapsed: barElapsed, childrenError: nil, childrenElapsed: nil, records: [])
        }
        // swiftlint:disable:next force_cast
        let bar = barValue as! AXUIElement
        AXUIElementSetMessagingTimeout(bar, Float(timeout))

        let childrenStart = clock.now
        var childrenValue: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(bar, Self.childrenAttribute as CFString, &childrenValue)
        let childrenDuration = clock.now - childrenStart
        let childrenElapsed = childrenDuration.secondsDouble

        guard childrenResult == .success, childrenDuration < slowThreshold else {
            let error = (childrenResult == .success) ? "cannotComplete" : AXErrorNames.name(childrenResult)
            return RawRead(process: process, extrasError: "success", extrasElapsed: barElapsed, childrenError: error, childrenElapsed: childrenElapsed, records: [])
        }

        let children = (childrenValue as? [AXUIElement]) ?? []
        var records = [ExtrasRecord]()
        records.reserveCapacity(children.count)
        for (index, child) in children.enumerated() {
            AXUIElementSetMessagingTimeout(child, Float(timeout))
            let (record, shouldStop) = Self.readChild(child, index: index, clock: clock, slowThreshold: slowThreshold, readsLabels: readsLabels)
            records.append(record)
            if shouldStop { break }
        }

        return RawRead(process: process, extrasError: "success", extrasElapsed: barElapsed, childrenError: "success", childrenElapsed: childrenElapsed, records: records)
    }

    /// Reads one child's attributes in order (role, identifier, title,
    /// description, help, frame -- frame deliberately last, so any early
    /// stop always leaves at least one of role/identifier/frame unread,
    /// which is what makes `ReadClassifier.outcome` fail this record
    /// regardless of which attribute actually triggered the stop). Returns
    /// whether the *process's* walk should stop here.
    private static func readChild(_ child: AXUIElement, index: Int, clock: ContinuousClock, slowThreshold: Duration, readsLabels: Bool) -> (ExtrasRecord, Bool) {
        var stopped = false

        func readString(_ attribute: String) -> AttributeRead<String> {
            guard !stopped else { return AttributeRead(value: nil, error: notAttempted) }
            let start = clock.now
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(child, attribute as CFString, &value)
            let duration = clock.now - start
            if result == .success, duration >= slowThreshold {
                stopped = true
                return AttributeRead(value: nil, error: "cannotComplete")
            }
            if result != .success, result != .noValue, result != .attributeUnsupported {
                stopped = true
            }
            return AttributeRead(value: value as? String, error: AXErrorNames.name(result))
        }

        func readFrame() -> AttributeRead<BarRect> {
            guard !stopped else { return AttributeRead(value: nil, error: notAttempted) }
            let start = clock.now
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(child, frameAttribute as CFString, &value)
            let duration = clock.now - start
            if result == .success, duration >= slowThreshold {
                stopped = true
                return AttributeRead(value: nil, error: "cannotComplete")
            }
            if result != .success, result != .noValue, result != .attributeUnsupported {
                stopped = true
            }
            guard result == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
                return AttributeRead(value: nil, error: AXErrorNames.name(result))
            }
            var rect = CGRect.zero
            // swiftlint:disable:next force_cast
            AXValueGetValue(value as! AXValue, .cgRect, &rect)
            let barRect = BarRect(minX: Double(rect.minX), minY: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
            return AttributeRead(value: barRect, error: "success")
        }

        let role = readString(roleAttribute)
        let identifier = readString(identifierAttribute)
        let skipped = AttributeRead<String>(value: nil, error: notAttempted)
        let title = readsLabels ? readString(titleAttribute) : skipped
        let description = readsLabels ? readString(descriptionAttribute) : skipped
        let help = readsLabels ? readString(helpAttribute) : skipped
        let frame = readFrame()

        let record = ExtrasRecord(childIndex: index, role: role, identifier: identifier, title: title, description: description, help: help, frame: frame)
        return (record, stopped)
    }
}

extension Duration {
    /// `Duration`'s own components as a plain `Double` of seconds, so it can
    /// be stored in `RawRead.extrasElapsed`/`childrenElapsed` (`Double`,
    /// matching `IceCore`'s standard-library-only contract -- this
    /// extension lives in the adapter, not in IceCore).
    fileprivate var secondsDouble: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
