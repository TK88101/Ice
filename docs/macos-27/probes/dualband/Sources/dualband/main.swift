//  main.swift
//  dualband
//
//  dualband selftest <evidence dir>   read-only: displays, active bar, idle, one strip per bar
//  dualband run <Debug Ice.app> <evidence dir> [--resume]   the T0 sitting (plan 2026-11-15-secondary-display)

import AppKit
import DualbandCore

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
              "strip", strip.width, "x", strip.height)
    }
case "run":
    guard arguments.count >= 4 else { fail("usage: dualband run <Debug Ice.app> <dir> [--resume]") }
    Run.main(debugApp: URL(fileURLWithPath: arguments[2]), dir: URL(fileURLWithPath: arguments[3], isDirectory: true),
             resume: arguments.contains("--resume"))
default:
    fail("unknown command \(arguments[1])")
}
