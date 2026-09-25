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
            return RawRead(process: process, extrasError: error, extrasElapsed: barElapsed, childrenError: nil, childrenElapsed: nil, records: [], walkInterrupted: false, childCount: 0)
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
            return RawRead(process: process, extrasError: "success", extrasElapsed: barElapsed, childrenError: error, childrenElapsed: childrenElapsed, records: [], walkInterrupted: false, childCount: 0)
        }

        let children = (childrenValue as? [AXUIElement]) ?? []
        var records = [ExtrasRecord]()
        records.reserveCapacity(children.count)
        var interrupted = false
        for (index, child) in children.enumerated() {
            AXUIElementSetMessagingTimeout(child, Float(timeout))
            let (record, shouldStop) = Self.readChild(
                index: index,
                readsLabels: readsLabels,
                timeout: timeout,
                readString: { _, axAttribute in Self.timedString(child, axAttribute, clock: clock) },
                readFrame: { _ in Self.timedFrame(child, clock: clock) }
            )
            records.append(record)
            if shouldStop {
                interrupted = true
                break
            }
        }

        return RawRead(process: process, extrasError: "success", extrasElapsed: barElapsed, childrenError: "success", childrenElapsed: childrenElapsed, records: records, walkInterrupted: interrupted, childCount: children.count)
    }

    /// One attribute read exactly as the adapter performed it: what came
    /// back, the `AXError` name, and how long the call took.
    /// `AttributeWalkPolicy` needs that duration and `AttributeRead` does not
    /// carry one, so the two stay separate types.
    struct TimedRead<Value> {
        let value: Value?
        let rawError: String
        let elapsed: Double
    }

    /// Reads one child's attributes in the fixed order role, identifier, title,
    /// description, help, frame, asking `AttributeWalkPolicy` after each
    /// whether the walk may go on, and returns the record plus whether the
    /// *process's* walk should stop here.
    ///
    /// The reads are injected, which is the whole point: a policy function can
    /// only prove what the rule says, never that the walk obeys it, so a test
    /// scripts `readString`/`readFrame`, records which AX attributes were asked
    /// in which order, and checks that a tolerated identifier failure really
    /// does go on to ask for the frame and the next child while a slow one does
    /// not (2026-09-25 plan, seam S2).
    ///
    /// The order is unchanged. It is no longer the frame's *lastness* that makes
    /// a stopped walk fail -- `RawRead.walkInterrupted` carries that now -- but
    /// reordering would change which failure a process reports first, which is
    /// behaviour nothing here is trying to change.
    static func readChild(
        index: Int,
        readsLabels: Bool,
        timeout: Double,
        readString: (Int, String) -> TimedRead<String>,
        readFrame: (Int) -> TimedRead<BarRect>
    ) -> (record: ExtrasRecord, stop: Bool) {
        var stopped = false

        func read(_ attribute: String, _ axAttribute: String, skipped: Bool = false) -> AttributeRead<String> {
            guard !stopped, !skipped else { return AttributeRead(value: nil, error: notAttempted) }
            let timed = readString(index, axAttribute)
            let verdict = AttributeWalkPolicy.classify(attribute: attribute, rawError: timed.rawError, elapsed: timed.elapsed, timeout: timeout)
            if verdict.decision == .stopWalk { stopped = true }
            return AttributeRead(value: verdict.value == .keep ? timed.value : nil, error: verdict.recordedError)
        }

        // The names handed to the policy are the ones `ReadClassifier` uses for
        // the same attributes, so one vocabulary spans the rule and the verdict.
        let role = read("role", roleAttribute)
        let identifier = read("identifier", identifierAttribute)
        let title = read("title", titleAttribute, skipped: !readsLabels)
        let description = read("description", descriptionAttribute, skipped: !readsLabels)
        let help = read("help", helpAttribute, skipped: !readsLabels)

        var frame = AttributeRead<BarRect>(value: nil, error: notAttempted)
        if !stopped {
            let timed = readFrame(index)
            let verdict = AttributeWalkPolicy.classify(attribute: "frame", rawError: timed.rawError, elapsed: timed.elapsed, timeout: timeout)
            if verdict.decision == .stopWalk { stopped = true }
            frame = AttributeRead(value: verdict.value == .keep ? timed.value : nil, error: verdict.recordedError)
        }

        let record = ExtrasRecord(childIndex: index, role: role, identifier: identifier, title: title, description: description, help: help, frame: frame)
        return (record, stopped)
    }

    /// The live `readString` operation: one timed `AXUIElementCopyAttributeValue`
    /// against this child, with no judgement of its own.
    private static func timedString(_ child: AXUIElement, _ axAttribute: String, clock: ContinuousClock) -> TimedRead<String> {
        let start = clock.now
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(child, axAttribute as CFString, &value)
        let elapsed = (clock.now - start).secondsDouble
        return TimedRead(value: value as? String, rawError: AXErrorNames.name(result), elapsed: elapsed)
    }

    /// The live `readFrame` operation. A success whose value is not an
    /// `AXValue` is reported as a success with no value, exactly as before: the
    /// call did work, it just did not hand back a rect this reader can use.
    private static func timedFrame(_ child: AXUIElement, clock: ContinuousClock) -> TimedRead<BarRect> {
        let start = clock.now
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(child, frameAttribute as CFString, &value)
        let elapsed = (clock.now - start).secondsDouble
        guard result == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return TimedRead(value: nil, rawError: AXErrorNames.name(result), elapsed: elapsed)
        }
        var rect = CGRect.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(value as! AXValue, .cgRect, &rect)
        let barRect = BarRect(minX: Double(rect.minX), minY: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
        return TimedRead(value: barRect, rawError: "success", elapsed: elapsed)
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
