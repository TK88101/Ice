//  Rig.swift
//  dualband
//
//  What the run drives: the Debug Ice over its lab report, its own front app
//  (menus and a window on a chosen display), the helper, and the masks.

import AppKit
import DualbandCore

/// The Debug Ice under the daily identity, reporting (G1).
final class DebugIce: @unchecked Sendable {
    let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var latest: [String: Any]?
    private var all = [[String: Any]]()
    private let log: FileHandle?

    /// Every event read so far, in the report's order.
    var events: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return all
    }

    init(
        app: URL, log url: URL,
        arguments: [String] = ["-IceLabReport", "YES", "-IceOwnerT0", "YES", "-SUEnableAutomaticChecks", "NO", "-SUAutomaticallyUpdate", "NO"]
    ) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        log = try? FileHandle(forWritingTo: url)
        process.executableURL = app.appendingPathComponent("Contents/MacOS/Ice")
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.take(handle.availableData)
        }
        try process.run()
    }

    private func take(_ data: Data) {
        guard !data.isEmpty else { return }
        log?.write(data)
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                if object["event"] as? String == "snapshot" { latest = object } else { all.append(object) }
            }
        }
    }

    var snapshot: [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    var isAlive: Bool { process.isRunning }

    func send(_ line: String) {
        input.fileHandleForWriting.write(Data((line + "\n").utf8))
    }

    func waitSnapshot(timeout: TimeInterval, _ accept: ([String: Any]) -> Bool) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let snapshot, accept(snapshot) { return snapshot }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    /// Frames of members in the snapshot's roster; `namespace` narrows to one bundle.
    static func memberFrames(_ snapshot: [String: Any], namespace: String? = nil) -> [[Double]] {
        let roster = snapshot["roster"] as? [[String: Any]] ?? []
        return roster.compactMap { member in
            if let namespace, member["namespace"] as? String != namespace { return nil }
            return (member["frame"] as? [NSNumber])?.map(\.doubleValue)
        }
    }

    static func dividerFrame(_ snapshot: [String: Any]) -> [Double]? {
        ((snapshot["hiddenDivider"] as? [String: Any])?["frame"] as? [NSNumber])?.map(\.doubleValue)
    }

    static func dividerWidth(_ snapshot: [String: Any]) -> Double? {
        ((snapshot["hiddenDivider"] as? [String: Any])?["frame"] as? [NSNumber])?[2].doubleValue
    }
}

/// The run's own front app: its menus are the active bar's app menu.
enum Front {
    private nonisolated(unsafe) static var window: NSWindow?

    /// Shows `menus` menus and a window on `bar`, activates, and returns the
    /// display that then has the active menu bar.
    static func present(menus: Int, on bar: Bar) -> UInt32? {
        DispatchQueue.main.sync {
            let main = NSMenu()
            let appItem = NSMenuItem()
            appItem.submenu = NSMenu(title: "dualband")
            main.addItem(appItem)
            for index in 0..<menus {
                let item = NSMenuItem()
                item.submenu = NSMenu(title: "Measure Menu \(index + 1)")
                main.addItem(item)
            }
            NSApp.mainMenu = main
            let screen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == bar.displayID
            }
            let frame = screen.map { NSRect(x: $0.frame.midX - 160, y: $0.frame.midY - 60, width: 320, height: 120) } ?? .zero
            let shown = window ?? NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
            shown.title = "dualband measuring"
            shown.setFrame(frame, display: true)
            shown.makeKeyAndOrderFront(nil)
            window = shown
            NSApp.activate(ignoringOtherApps: true)
        }
        for _ in 0..<12 {
            Thread.sleep(forTimeInterval: 0.25)
            if Live.activeMenuBarDisplayID() == bar.displayID { break }
        }
        return Live.activeMenuBarDisplayID()
    }
}

/// The helper of step 4 (`vzhelper`, com.icespike4.target).
final class Helper {
    private let process = Process()
    private let input = Pipe()

    var pid: pid_t { process.processIdentifier }

    init?(
        vzhelper: URL, log: URL, items: Int = 1, identifiers: String = "dualband-helper", glyphs: String = "target", autosave: String? = nil
    ) {
        FileManager.default.createFile(atPath: log.path, contents: nil)
        process.executableURL = vzhelper
        process.arguments = ["--controller", "\(getpid())", "--items", "\(items)", "--identifiers", identifiers, "--glyphs", glyphs, "--lifetime", "1800"]
            + (autosave.map { ["--autosave", $0] } ?? [])
        process.standardInput = input
        process.standardOutput = try? FileHandle(forWritingTo: log)
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
    }

    func stop() {
        try? input.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        if process.isRunning { process.terminate() }
    }
}

enum Masks {
    /// Columns (pixels) of the notch and of other processes' small windows over the bar.
    static func excluded(on bar: Bar, ownPID: pid_t) -> [Range<Int>] {
        var spans: [(Double, Double)] = []
        if bar.hasNotch, let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == bar.displayID
        }), let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            spans.append((left.maxX, right.minX))
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let barRect = CGRect(x: bar.x, y: bar.y, width: bar.width, height: bar.barHeight)
        for window in windows {
            guard
                let layer = window[kCGWindowLayer as String] as? Int, layer > 0,
                let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                let owner = window[kCGWindowOwnerName as String] as? String, owner != "Window Server",
                let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict),
                bounds.intersects(barRect), bounds.width < bar.width * 0.9,
                // A tall, mostly transparent container (a notch app's) is not masked
                // whole: what it draws on the bar is found in the strip (`darkBlobs`).
                bounds.height <= bar.barHeight * 2
            else {
                continue
            }
            spans.append((bounds.minX - bar.x, bounds.maxX - bar.x))
        }
        return spans.map { Int((max(0, $0.0) * bar.scale).rounded(.down))..<Int((min(bar.width, $0.1) * bar.scale).rounded(.up)) }
            .filter { !$0.isEmpty }
    }
}

enum Template {
    /// Best normalized cross-correlation of `template` over the strip, columns `limit` excluded beyond.
    static func bestScore(of template: GrayStrip, in strip: GrayStrip, before limit: Int) -> Double {
        guard template.width > 0, template.height <= strip.height else { return 0 }
        let t = template.pixels.map(Double.init)
        let tMean = t.reduce(0, +) / Double(t.count)
        let tDev = t.map { $0 - tMean }
        let tNorm = sqrt(tDev.map { $0 * $0 }.reduce(0, +))
        guard tNorm > 0 else { return 0 }
        let y0 = (strip.height - template.height) / 2
        var best = 0.0
        for x0 in stride(from: 0, through: max(0, min(limit, strip.width) - template.width), by: 1) {
            var values = [Double]()
            values.reserveCapacity(t.count)
            for y in 0..<template.height { for x in 0..<template.width { values.append(Double(strip[x0 + x, y0 + y])) } }
            let mean = values.reduce(0, +) / Double(values.count)
            var dot = 0.0, norm = 0.0
            for i in values.indices { let d = values[i] - mean; dot += d * tDev[i]; norm += d * d }
            if norm > 0 { best = max(best, dot / (sqrt(norm) * tNorm)) }
        }
        return best
    }

    static func crop(_ strip: GrayStrip, columns: Range<Int>) -> GrayStrip {
        var pixels = [UInt8]()
        for y in 0..<strip.height { for x in columns { pixels.append(strip[x, y]) } }
        return GrayStrip(width: columns.count, height: strip.height, pixels: pixels)
    }
}
