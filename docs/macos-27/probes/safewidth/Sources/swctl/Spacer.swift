// S — the spacer, driven the way Ice drives its hidden control item in the
// chevron style (ControlItem.swift 329–430):
//   rest:   image = chevron-sized image, length = variableLength
//   expand: image = nil, then length = w
// Two thin two-colour markers are pinned to the button's left and right edges.
// They are instrumentation only: they let a capture say where S's edges are
// drawn, because S's AX frame has been seen to lag.
import AppKit

final class Spacer {
    static let identifier = "IceSpike4-spacer"
    static let markerWidth: CGFloat = 4
    static let markerHeight: CGFloat = 8

    private(set) var item: NSStatusItem
    /// nil = Ice's own rest (variableLength plus a chevron image). A fixed length
    /// is the fallback when the bar has no room for Ice's rest width; results taken
    /// with it are labelled and not compared with Ice-rest results.
    var fixedRest: Double? {
        didSet { setRest() }
    }
    private let leftColours: (NSColor, NSColor)
    private let rightColours: (NSColor, NSColor)

    init(leftColours: (NSColor, NSColor), rightColours: (NSColor, NSColor)) {
        self.leftColours = leftColours
        self.rightColours = rightColours
        item = Self.makeItem(leftColours: leftColours, rightColours: rightColours)
        setRest()
    }

    /// nil = rest.
    func set(_ length: Double?) {
        guard let length else {
            setRest()
            return
        }
        item.button?.image = nil
        item.length = CGFloat(length)
    }

    /// Removes the item and creates a fresh one at rest (a full reset of S).
    func recreate() {
        NSStatusBar.system.removeStatusItem(item)
        Self.forgetPreferredPositions()
        item = Self.makeItem(leftColours: leftColours, rightColours: rightColours)
        setRest()
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    var appKitFrame: CGRect? {
        item.button?.window?.frame
    }

    private func setRest() {
        if let fixedRest {
            item.button?.image = nil
            item.length = CGFloat(fixedRest)
        } else {
            item.button?.image = Self.restImage
            item.length = NSStatusItem.variableLength
        }
    }

    /// Removing a status item leaves its stored preferred position behind in this
    /// process's defaults; drop every such key so no position leaks into the next
    /// item.
    static func forgetPreferredPositions() {
        let defaults = UserDefaults.standard
        guard let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName as String?,
              let own = defaults.persistentDomain(forName: domain) else {
            return
        }
        var trimmed = own
        for key in own.keys where key.hasPrefix("NSStatusItem Preferred Position") {
            trimmed.removeValue(forKey: key)
        }
        defaults.setPersistentDomain(trimmed, forName: domain)
    }

    /// A chevron glyph about the width of Ice's; a template image, so it is drawn
    /// in the bar's own tint and never matches a marker colour.
    private static let restImage: NSImage? = {
        let image = NSImage(systemSymbolName: "chevron.left.2", accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }()

    private static func makeItem(leftColours: (NSColor, NSColor), rightColours: (NSColor, NSColor)) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.setAccessibilityIdentifier(identifier)
        if let button = item.button {
            button.addSubview(marker(leftColours, pinnedLeft: true, in: button))
            button.addSubview(marker(rightColours, pinnedLeft: false, in: button))
        }
        return item
    }

    private static func marker(_ colours: (NSColor, NSColor), pinnedLeft: Bool, in button: NSView) -> NSView {
        let y = (button.bounds.height - markerHeight) / 2
        let x = pinnedLeft ? 0 : button.bounds.width - markerWidth
        let view = MarkerView(frame: NSRect(x: x, y: max(0, y), width: markerWidth, height: markerHeight))
        view.colours = colours
        view.autoresizingMask = pinnedLeft ? [.maxXMargin, .minYMargin, .maxYMargin] : [.minXMargin, .minYMargin, .maxYMargin]
        return view
    }
}

/// Left half one colour, right half the other, like the helpers' markers.
final class MarkerView: NSView {
    var colours: (NSColor, NSColor) = (.clear, .clear)

    override func draw(_ dirtyRect: NSRect) {
        colours.0.setFill()
        NSRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height).fill()
        colours.1.setFill()
        NSRect(x: bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height).fill()
    }
}
