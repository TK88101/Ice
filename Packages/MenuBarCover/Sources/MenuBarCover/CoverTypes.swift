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
    public let covered: [CoverSlot]
    /// Those of them that stand without a hit test's answer (Amendment B).
    public let silent: [CoverSlot]
    public let blocks: [ClosedRange<Double>]
    /// How long the bar's panels ignored mouse events for the hit tests.
    public let ignoredMilliseconds: Double
}

/// Why a bar is covered as it is (plan 2026-11-18-cover-stale-and-lost, D3):
/// counts only, said when they change.
public struct CoverBarDiagnosis: Equatable {
    public let displayID: UInt32
    /// Whether the tree could be read; the other counts are of the last read.
    public let readable: Bool
    /// The pids the cover was told it may cover.
    public let coverable: Int
    public let slots: Int
    /// The distinct owners of the slots: one is a tree that lists `MenuBarAgent`'s own slots only.
    public let owners: Int
    public let candidates: Int
    public let covered: Int
    /// Of the candidates left uncovered: nothing answered the hit test, a call failed, another item answered.
    public let silent: Int
    public let failed: Int
    public let other: Int
    /// A bar with a notch pushes the members off; one without draws them at every length.
    public let hasNotch: Bool

    public init(
        displayID: UInt32, readable: Bool, coverable: Int, slots: Int, owners: Int, candidates: Int, covered: Int, silent: Int, failed: Int,
        other: Int, hasNotch: Bool
    ) {
        self.hasNotch = hasNotch
        self.displayID = displayID
        self.readable = readable
        self.coverable = coverable
        self.slots = slots
        self.owners = owners
        self.candidates = candidates
        self.covered = covered
        self.silent = silent
        self.failed = failed
        self.other = other
    }

    /// What a diagnosis is said again for: whether the tree was read, and how
    /// many slots may be, could be and are covered. The hit answers of an
    /// uncovered slot can change every second without any of this changing.
    var coverage: [Int] {
        [readable ? 1 : 0, coverable, candidates, covered]
    }

    /// Members could be drawn here with no panel over them: an unread
    /// tree, a candidate left uncovered, or no candidate at all on a bar that
    /// draws the members at every length.
    public var isUncovered: Bool {
        !readable || covered < candidates || (candidates == 0 && !hasNotch)
    }
}

/// What one capture of a bar's background was (D2).
public struct CoverCaptureFact: Equatable {
    public let displayID: UInt32
    /// The strip's mean brightness, 0 to 1.
    public let luma: Double?
    /// Whether it equals the strip held before it; `nil` for the first.
    public let equal: Bool?
    public let transparent: Bool
    /// The image calls returned nothing.
    public let failed: Bool
    /// Why it was taken, and where the confirmation stands after it (`CoverBackgroundTrust`).
    public let reason: CoverBackgroundTrust.Reason
    public let step: Int
    public let unequalRun: Int
    /// It did not show the bar transparent while a transparent image was
    /// held, for the first time: the image held stays (a passing moment).
    public let ignored: Bool

    public init(
        displayID: UInt32, luma: Double?, equal: Bool?, transparent: Bool, failed: Bool, reason: CoverBackgroundTrust.Reason, step: Int,
        unequalRun: Int, ignored: Bool = false
    ) {
        self.ignored = ignored
        self.displayID = displayID
        self.luma = luma
        self.equal = equal
        self.transparent = transparent
        self.failed = failed
        self.reason = reason
        self.step = step
        self.unequalRun = unequalRun
    }
}

public enum CoverNotice: Equatable {
    case noScreenRecording
    case barNotTransparent(displayID: UInt32)
}
