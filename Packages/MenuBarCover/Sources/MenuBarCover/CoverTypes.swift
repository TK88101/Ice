//  CoverTypes.swift
//  MenuBarCover

import CoreGraphics
import IceCore

/// One display's menu bar.
public struct CoverBar: Equatable {
    public let displayID: UInt32
    /// The bar's strip in the global display space (top-left origin, points).
    public let frame: CGRect
    public let scale: Double
    /// The notch's extent in display-local points, if the display has one.
    public let notch: ClosedRange<Double>?

    public init(displayID: UInt32, frame: CGRect, scale: Double, notch: ClosedRange<Double>?) {
        self.displayID = displayID
        self.frame = frame
        self.scale = scale
        self.notch = notch
    }
}

/// `MenuBarAgent`'s view of a bar (plan D1). Called on the controller's queue.
public protocol CoverBarReading {
    /// The slots of every agent window with that bar's frame, display-local;
    /// `nil` when the agent cannot be read.
    func slots(of bar: CoverBar) -> [CoverSlot]?
    /// What a hit test answers at each display-local x of the bar's middle
    /// line: the owner of the item hit, nothing (`silent`), or a failed call.
    func owners(at xs: [Double], of bar: CoverBar) -> [CoverHit]
}

public struct CoverStrips {
    /// Everything below the system's `Menubar` window, over the bar's strip.
    public let below: CGImage
    /// The strip as it is on screen.
    public let onScreen: CGImage

    public init(below: CGImage, onScreen: CGImage) {
        self.below = below
        self.onScreen = onScreen
    }
}

/// The bar's background (plan D2). Called on the controller's queue.
public protocol CoverCapturing {
    /// Two image calls.
    func strips(of bar: CoverBar) -> CoverStrips?
    /// The windows below `Menubar` that reach into the strip (ids, bounds,
    /// order), from the window list: no capture.
    func underStripSignature(of bar: CoverBar) -> String
}

/// The panels (plan D3). Called on the main thread.
public protocol CoverPresenting: AnyObject {
    /// One panel per block (display-local points), drawing `strip` there.
    func show(blocks: [ClosedRange<Double>], strip: CGImage, bar: CoverBar)
    /// Removes the panels of a display, or of every display.
    func remove(displayID: UInt32?)
    func setIgnoresMouseEvents(_ ignores: Bool, displayID: UInt32)
}

/// What one verification transaction found on a bar; the lab's `cover` event.
public struct CoverBarReport: Equatable {
    public let displayID: UInt32
    public let slots: [CoverSlot]
    /// Every slot under a panel, left to right.
    public let verified: [CoverSlot]
    /// Those of them that stand without a hit test's answer (Amendment B).
    public let silent: [CoverSlot]
    public let blocks: [ClosedRange<Double>]
    /// How long the bar's panels ignored mouse events for the hit tests.
    public let ignoredMilliseconds: Double
}

public enum CoverNotice: Equatable {
    case noScreenRecording
    case barNotTransparent(displayID: UInt32)
}
