//  Live.swift
//  dualband
//
//  Read-only screen facts: displays, bar captures, the active menu bar, idle time.

import AppKit
import DualbandCore
import IOKit

@_silgen_name("CGSMainConnectionID")
private func cgsMainConnectionID() -> Int32

@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
private func cgsCopyActiveMenuBarDisplayIdentifier(_ cid: Int32) -> Unmanaged<CFString>?

/// One display as the run sees it.
struct Bar: Codable, Equatable {
    let displayID: UInt32
    let name: String
    /// CG global bounds (top-left origin, points).
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let scale: Double
    let barHeight: Double
    let hasNotch: Bool
    let isBuiltin: Bool

    var maxX: Double { x + width }
}

enum Live {
    static func bars() -> [Bar] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = number.uint32Value
            let bounds = CGDisplayBounds(id)
            let menuHeight = screen.frame.maxY - screen.visibleFrame.maxY
            let barHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : (menuHeight > 0 ? menuHeight : 24)
            return Bar(
                displayID: id, name: screen.localizedName,
                x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height,
                scale: screen.backingScaleFactor, barHeight: barHeight, hasNotch: screen.safeAreaInsets.top > 0,
                isBuiltin: CGDisplayIsBuiltin(id) != 0
            )
        }
    }

    /// Display ids, frames, scale and mirroring, as one comparable string.
    static func fingerprint(_ bars: [Bar]) -> String {
        bars.sorted { $0.displayID < $1.displayID }.map {
            "\($0.displayID):\($0.x),\($0.y),\($0.width)x\($0.height)@\($0.scale):m\(CGDisplayMirrorsDisplay($0.displayID))"
        }.joined(separator: "|")
    }

    /// The bar's strip as luminance, and the image for evidence.
    static func capture(_ bar: Bar) -> (GrayStrip, CGImage)? {
        let rect = CGRect(x: bar.x, y: bar.y, width: bar.width, height: bar.barHeight)
        guard let image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else {
            return nil
        }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (GrayStrip(width: width, height: height, pixels: pixels), image) : nil
    }

    static func activeMenuBarDisplayID() -> UInt32? {
        guard let string = cgsCopyActiveMenuBarDisplayIdentifier(cgsMainConnectionID())?.takeRetainedValue(),
              let uuid = CFUUIDCreateFromString(nil, string)
        else {
            return nil
        }
        let id = CGDisplayGetDisplayIDFromUUID(uuid)
        return id == 0 ? nil : id
    }

    /// Seconds since the last hardware input.
    static func idleSeconds() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber
        else {
            return nil
        }
        return value.doubleValue / 1_000_000_000
    }

    static func writePNG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

/// A member's columns on a bar: AX frames (global, on the bar AX reports)
/// carried to another bar by their distance from the right edge, which is
/// where the status area is anchored.
enum Spot {
    static func columns(frames: [[Double]], reference: Bar, on bar: Bar) -> Range<Int>? {
        let spans: [(Double, Double)] = frames.compactMap { frame in
            guard frame.count == 4, frame[2] > 0 else { return nil }
            let fromRight = reference.maxX - (frame[0] + frame[2])
            let maxX = bar.width - fromRight
            return (maxX - frame[2], maxX)
        }
        guard let low = spans.map(\.0).min(), let high = spans.map(\.1).max(), low >= 0, high <= bar.width else {
            return nil
        }
        return Int((low * bar.scale).rounded(.down))..<Int((high * bar.scale).rounded(.up))
    }
}
