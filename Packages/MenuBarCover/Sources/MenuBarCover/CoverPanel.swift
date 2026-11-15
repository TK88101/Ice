//  CoverPanel.swift
//  MenuBarCover

import AppKit

/// Draws the part of a bar's below-`Menubar` strip that lies under it.
private final class CoverView: NSView {
    var strip: CGImage?
    /// The part of `strip` to draw, in its pixels.
    var crop = CGRect.zero

    override func draw(_ dirtyRect: NSRect) {
        guard let strip, let part = strip.cropping(to: crop), let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(part, in: bounds)
    }
}

/// One cover (plan D3): above the menu bar, below anything that floats over
/// it; takes mouse events, so nothing reaches the item beneath.
final class CoverPanel: NSPanel {
    private let cover = CoverView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        title = "Ice Cover"
        // Opaque: the strip is always drawn over the whole of it.
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        animationBehavior = .none
        hidesOnDeactivate = false
        canHide = false
        isMovable = false
        ignoresMouseEvents = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        contentView = cover
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func isAccessibilityElement() -> Bool { false }

    func update(block: ClosedRange<Double>, strip: CGImage, bar: CoverBar) {
        // Whole pixels, outward.
        let lower = (block.lowerBound * bar.scale).rounded(.down)
        let upper = (block.upperBound * bar.scale).rounded(.up)
        let x = bar.frame.minX + lower / bar.scale
        let width = (upper - lower) / bar.scale
        // AppKit's space has its origin at the bottom left of the first screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? bar.frame.maxY
        let target = NSRect(x: x, y: primaryHeight - bar.frame.maxY, width: width, height: bar.frame.height)
        let crop = CGRect(x: lower, y: 0, width: upper - lower, height: CGFloat(strip.height))
        let moved = frame != target
        if moved { setFrame(target, display: false) }
        // A pass comes every second: drawn again only when what it draws changed.
        if moved || cover.strip !== strip || cover.crop != crop {
            cover.strip = strip
            cover.crop = crop
            cover.needsDisplay = true
        }
        if !isVisible { orderFrontRegardless() }
    }
}

/// The live panels, one per block, per display. Main thread.
public final class CoverPanelPresenter: CoverPresenting {
    private var panels = [UInt32: [CoverPanel]]()

    public init() {}

    /// The panels' frames in the global display space (top-left origin), per display.
    public var frames: [UInt32: [CGRect]] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return panels.mapValues { list in
            list.map { CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        }
    }

    public func show(blocks: [ClosedRange<Double>], strip: CGImage, bar: CoverBar) {
        var list = panels[bar.displayID] ?? []
        while list.count > blocks.count { list.removeLast().close() }
        while list.count < blocks.count { list.append(CoverPanel()) }
        for (panel, block) in zip(list, blocks) { panel.update(block: block, strip: strip, bar: bar) }
        panels[bar.displayID] = list
    }

    public func remove(displayID: UInt32?) {
        for id in panels.keys where displayID == nil || displayID == id {
            panels[id]?.forEach { $0.close() }
            panels[id] = nil
        }
    }

    public func setIgnoresMouseEvents(_ ignores: Bool, displayID: UInt32) {
        panels[displayID]?.forEach { $0.ignoresMouseEvents = ignores }
    }
}

public extension CoverController.Environment {
    /// The live scheduling: one serial queue for the passes, the main queue
    /// for everything else.
    static func live(
        backgroundKey: @escaping (CoverBar) -> String, canCapture: @escaping () -> Bool
    ) -> CoverController.Environment {
        let queue = DispatchQueue(label: "com.icereverse.MenuBarCover.pass", qos: .userInitiated)
        return CoverController.Environment(
            bars: { CoverBars.current() }, backgroundKey: backgroundKey, canCapture: canCapture,
            now: { ProcessInfo.processInfo.systemUptime },
            background: { body in queue.async(execute: body) },
            main: { body in DispatchQueue.main.async(execute: body) },
            mainSync: { body in DispatchQueue.main.sync(execute: body) },
            after: { delay, body in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body) },
            pause: { seconds in Thread.sleep(forTimeInterval: seconds) }
        )
    }
}
