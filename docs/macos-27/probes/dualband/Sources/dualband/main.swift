//  main.swift
//  dualband
//
//  dualband selftest <evidence dir>   read-only: displays, active bar, idle, one strip per bar
//  dualband run <Debug Ice.app> <evidence dir> [--resume]   the T0 sitting (plan 2026-11-15-secondary-display)

import AppKit
import DualbandCore
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("dualband: \(message)\n".utf8))
    exit(2)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fail("usage: dualband selftest <dir> | run <Debug Ice.app> <dir> [--resume]") }

switch arguments[1] {
case "selftest":
    let dir = URL(fileURLWithPath: arguments[2], isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let bars = Live.bars()
    print("fingerprint", Live.fingerprint(bars))
    print("active", Live.activeMenuBarDisplayID().map(String.init) ?? "nil", "idle", Live.idleSeconds().map { String(format: "%.1f", $0) } ?? "nil")
    for bar in bars {
        guard let (strip, image) = Live.capture(bar) else { print("bar", bar.displayID, "capture failed"); continue }
        Live.writePNG(image, to: dir.appendingPathComponent("selftest-\(bar.displayID).png"))
        print("bar", bar.displayID, bar.name, "builtin", bar.isBuiltin, "notch", bar.hasNotch, "barHeight", bar.barHeight,
              "strip", strip.width, "x", strip.height, "masks", Masks.excluded(on: bar, ownPID: getpid()).map { "\($0.lowerBound)-\($0.upperBound)" })
    }
case "check":
    // dualband check <png> <displayID> <dividerMinX> <membersWidth>: does the judge see the members in a standard strip (offline).
    guard arguments.count >= 6, let bar = Live.bars().first(where: { "\($0.displayID)" == arguments[3] }),
          let divider = Double(arguments[4]), let total = Double(arguments[5]),
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[2]) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("usage: dualband check <png> <displayID> <dividerMinX> <membersWidth>") }
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height)
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    let strip = GrayStrip(width: width, height: height, pixels: pixels)
    let reference = Live.bars().first(where: \.isBuiltin)!
    let frames = [[divider - total - 4, 0, total + 8, 24]]
    let spot = Spot.columns(frames: frames, reference: reference, on: bar)!
    let masks = Masks.excluded(on: bar, ownPID: getpid()) + Judge.darkBlobs(in: strip)
    let reading = try Judge.read(sample: strip, standard: strip, spot: spot, excluded: masks)
    // A standard strip against itself: only whether the judge sees the members (spotForeground), not a hide verdict.
    print("standard self-check: spot", spot, "masks", masks, "spotForeground", reading.spotForeground,
          reading.spotForeground > Judge.maxSpotForeground ? "members seen" : "blind")
case "run":
    guard arguments.count >= 4 else { fail("usage: dualband run <Debug Ice.app> <dir> [--resume]") }
    Run.main(debugApp: URL(fileURLWithPath: arguments[2]), dir: URL(fileURLWithPath: arguments[3], isDirectory: true),
             resume: arguments.contains("--resume"))
default:
    fail("unknown command \(arguments[1])")
}
