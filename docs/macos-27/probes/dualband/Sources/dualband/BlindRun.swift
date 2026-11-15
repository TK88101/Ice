//  BlindRun.swift
//  dualband
//
//  T10 of plan 2026-11-15-blind-at-length: a lab-identity Ice on a system that
//  lists no item pushed off the bar (macOS 27.2), with sacrificial helpers as
//  its members: the rest, a press on the bar under a hold, the re-read before
//  the IceBar opens. Only helpers are pressed; the owner's items are hidden
//  and shown as the daily Ice does it, never pressed.

import AppKit
import ApplicationServices

/// A sacrificial helper: its stdin, and its stdout line by line.
final class BlindHelper: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var received = [String]()
    private let log: FileHandle?

    var pid: pid_t { process.processIdentifier }

    init?(executable: URL, arguments: [String], log url: URL) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        log = try? FileHandle(forWritingTo: url)
        process.executableURL = executable
        process.arguments = ["--controller", "\(getpid())"] + arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.take(handle.availableData)
        }
        guard (try? process.run()) != nil else { return nil }
    }

    private func take(_ data: Data) {
        guard !data.isEmpty else { return }
        log?.write(data)
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            received.append(String(data: buffer[buffer.startIndex..<newline], encoding: .utf8) ?? "")
            buffer.removeSubrange(buffer.startIndex...newline)
        }
    }

    /// How many lines so far contain every one of `words`.
    func count(_ words: String...) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return received.filter { line in words.allSatisfy(line.contains) }.count
    }

    func send(_ line: String) {
        input.fileHandleForWriting.write(Data((line + "\n").utf8))
    }

    func stop() {
        try? input.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        if process.isRunning { process.terminate() }
    }
}

final class BlindSitting {
    static let idleToStart = 300.0
    static let startWait = 8.0 * 3600
    static let inputQuiet = 5.0
    static let restLength = 736.0
    static let hiddenDivider = "Ice.ControlItem.Hidden"
    static let helperApps = URL(fileURLWithPath: "/private/tmp/claude-501/visibility-live/apps", isDirectory: true)

    let labApp: URL
    let popoverApp: URL
    let dir: URL
    private let stamp = Int(Date().timeIntervalSince1970)
    private var failures = [String]()
    private var ice: DebugIce?
    private var helpers = [BlindHelper]()
    private var seeded = [(domain: String, key: String)]()
    private var dailyWasRunning = false
    private var prefsBefore: URL?
    private var interrupted = false
    private let results: FileHandle?

    init(labApp: URL, popoverApp: URL, dir: URL) {
        self.labApp = labApp
        self.popoverApp = popoverApp
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("blind-results.txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        results = try? FileHandle(forWritingTo: url)
    }

    // MARK: Small tools

    private func say(_ line: String) {
        print(line)
        results?.write(Data((line + "\n").utf8))
    }

    private func check(_ ok: Bool, _ what: String) {
        say((ok ? "ok    " : "FAIL  ") + what)
        if !ok { failures.append(what) }
    }

    private func spin(_ seconds: Double) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// False from the first hardware input on: the sitting stops there.
    private func quiet() -> Bool {
        if (Live.idleSeconds() ?? 0) < Self.inputQuiet { interrupted = true }
        return !interrupted
    }

    private func seq(_ event: [String: Any]) -> Int {
        (event["seq"] as? NSNumber)?.intValue ?? 0
    }

    private func time(_ event: [String: Any]?) -> Double {
        (event?["t"] as? NSNumber)?.doubleValue ?? 0
    }

    private var lastSeq: Int {
        ice?.events.last.map(seq) ?? 0
    }

    /// The first event after `after` that `accept` takes, waiting up to `timeout`.
    private func wait(after: Int, timeout: Double, _ accept: ([String: Any]) -> Bool) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let found = ice?.events.first(where: { seq($0) > after && accept($0) }) { return found }
            guard quiet() else { return nil }
            spin(0.1)
        }
        return nil
    }

    private func until(_ timeout: Double, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            guard quiet() else { return false }
            spin(0.1)
        }
        return condition()
    }

    private func isLength(_ event: [String: Any], applied: Double?) -> Bool {
        guard event["event"] as? String == "length" else { return false }
        return (event["applied"] as? NSNumber)?.doubleValue == applied
    }

    private func lengths(after mark: Int, applied: Double?) -> Int {
        (ice?.events ?? []).filter { seq($0) > mark && isLength($0, applied: applied) }.count
    }

    /// The IceBar's cell for an identifier in the copy's last snapshot.
    private func cell(_ identifier: String) -> (namespace: String, disabled: Bool)? {
        let cells = ice?.snapshot?["cells"] as? [[String: Any]] ?? []
        guard let found = cells.first(where: { $0["identifier"] as? String == identifier }), let namespace = found["namespace"] as? String else {
            return nil
        }
        return (namespace, found["disabled"] as? Bool ?? false)
    }

    private func flag(_ key: String) -> Bool {
        ice?.snapshot?[key] as? Bool ?? false
    }

    /// A process's extras as this runner reads them: each child's identifier
    /// and x, or `nil` when it has no extras bar (what a pushed-off item's app answers on 27.2).
    private func extras(of pid: pid_t) -> [(identifier: String, x: Double)]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar,
              CFGetTypeID(bar) == AXUIElementGetTypeID()
        else {
            return nil
        }
        var children: CFTypeRef?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success else { return nil }
        return ((children as? [AXUIElement]) ?? []).map { child in
            var identifier: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXIdentifier" as CFString, &identifier)
            var position: CFTypeRef?
            var point = CGPoint.zero
            if AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &position) == .success, let position,
               CFGetTypeID(position) == AXValueGetTypeID() {
                // swiftlint:disable:next force_cast
                AXValueGetValue(position as! AXValue, .cgPoint, &point)
            }
            return (identifier as? String ?? "", Double(point.x))
        }
    }

    private func isListed(_ identifier: String, of pid: pid_t) -> Bool {
        extras(of: pid)?.contains { $0.identifier == identifier } ?? false
    }

    /// The leftmost x among the extras of every app but `excluding`.
    private func leftmostOther(excluding: Set<pid_t>) -> Double? {
        NSWorkspace.shared.runningApplications.map(\.processIdentifier)
            .filter { !excluding.contains($0) && $0 != getpid() }
            .flatMap { extras(of: $0) ?? [] }.map(\.x).filter { $0 > 0 }.min()
    }

    private func vzhelper(_ app: String) -> URL {
        Self.helperApps.appendingPathComponent("\(app).app/Contents/MacOS/vzhelper")
    }

    /// A helper whose item is placed by its own preferred position (C1 protocol, amendment v8): the larger, the further left.
    private func launch(
        _ name: String, executable: URL, domain: String, autosave: String, position: Double?, arguments: [String]
    ) -> BlindHelper? {
        if let position {
            let key = "NSStatusItem Preferred Position \(autosave)"
            Daily.shell("/usr/bin/defaults", ["write", domain, key, "-float", "\(position)"])
            seeded.append((domain, key))
        }
        let helper = BlindHelper(executable: executable, arguments: arguments + ["--autosave", autosave], log: dir.appendingPathComponent("helper-\(name).log"))
        if let helper { helpers.append(helper) }
        return helper
    }

    private func stopped(_ step: String) -> Int32 {
        say("STOPPED  hardware input during \(step); what was not reached is not measured")
        return 4
    }

    /// Asks for the IceBar and waits until it is presented.
    private func openBar(timeout: Double = 12) -> Bool {
        ice?.send("bar open")
        return until(timeout) { self.flag("isIceBarPresented") }
    }

    private func closeBar() {
        ice?.send("bar close")
        _ = until(3) { !self.flag("isIceBarPresented") }
    }

    /// Presses a helper's cell through the lab command; the event that answered.
    private func press(_ identifier: String) -> (mark: Int, sent: Bool) {
        let mark = lastSeq
        guard let target = cell(identifier) else { return (mark, false) }
        ice?.send("press \(target.namespace) \(identifier)")
        let answer = wait(after: mark, timeout: 3) { $0["event"] as? String == "press" }
        return (mark, answer?["answer"] as? String == "sent")
    }

    // MARK: The sitting

    func run() -> Int32 {
        defer { teardown() }
        // The sitting is of the built-in bar. With the active menu bar on another display every item reads on
        // that bar (run 20261116-blind-3: the helpers at x -760 with the Sidecar's bar active), so it waits for that too.
        func builtinIsActive() -> Bool {
            Live.activeMenuBarDisplayID().map { CGDisplayIsBuiltin($0) != 0 } ?? false
        }
        let deadline = Date().addingTimeInterval(Self.startWait)
        while (Live.idleSeconds() ?? 0) < Self.idleToStart || !builtinIsActive() {
            guard Date() < deadline else { say("the Mac never went idle with the built-in bar active"); return 3 }
            spin(10)
        }
        let running = Daily.running()
        guard running.allSatisfy({ $0.bundleURL?.path == Daily.appPath }) else { say("another process has the daily id"); return 2 }
        dailyWasRunning = !running.isEmpty
        let prefs = dir.appendingPathComponent("prefs-before.plist")
        if Daily.exportPrefs(to: prefs) { prefsBefore = prefs }
        if dailyWasRunning, !Daily.quit() { say("the daily Ice did not quit"); return 3 }
        say("note  the daily Ice was \(dailyWasRunning ? "running: quit for the sitting" : "not running: left so")")

        // --- one helper at a time: beside the copy's own two items the owner's bar has room for one more (run
        // 20261116-blind-4: of three helpers the system folded two away, and on 27.2 a folded item is in no read).
        func helper(_ name: String, app: String, identifier: String, suffix: String, extra: [String] = []) -> BlindHelper? {
            launch(name, executable: vzhelper(app), domain: app == "Protected" ? "com.icespike4.protected" : "com.icespike4.target",
                   autosave: "blind-\(stamp)-\(suffix)", position: 30000,
                   arguments: ["--items", "1", "--identifiers", identifier, "--glyphs", "target", "--lifetime", "900"] + extra)
        }
        guard let menu = helper("menu", app: "Target", identifier: "blind-menu", suffix: "m", extra: ["--menu"]) else {
            say("the menu helper did not start")
            return 2
        }
        spin(3)
        let menuX = extras(of: menu.pid)?.first { $0.identifier == "blind-menu" }?.x
        let others = leftmostOther(excluding: [menu.pid])
        say("note  the menu helper at x \(menuX.map { String(Int($0)) } ?? "unlisted"), leftmost other item at \(others.map { String(Int($0)) } ?? "none")")
        guard let menuX, let others, menuX > 0, menuX < others else {
            check(false, "the menu helper is on the bar, left of every other item")
            return 1
        }

        // --- the copy: it rests with the helper among its members
        do {
            ice = try DebugIce(
                app: labApp, log: dir.appendingPathComponent("blind-report.jsonl"),
                arguments: ["-IceLabReport", "YES", "-SUEnableAutomaticChecks", "NO", "-SUAutomaticallyUpdate", "NO"]
            )
        } catch {
            say("the lab copy did not start: \(error)")
            return 3
        }
        let labPID = ice?.process.processIdentifier ?? 0
        guard let rest = wait(after: 0, timeout: 120, { self.isLength($0, applied: Self.restLength) }) else {
            guard !interrupted else { return stopped("the wait for the first rest") }
            check(false, "the lab copy rested at \(Self.restLength)")
            return 1
        }
        let members = until(8) { self.cell("blind-menu") != nil }
        check(members, "the copy rested at 736 (seq \(seq(rest))) with the menu helper among its cells")
        guard members else { return 1 }

        // --- R1: a minute at rest
        var mark = seq(rest)
        var samples = 0, dividerListed = 0, helperListed = 0
        for _ in 0..<120 {
            spin(0.5)
            guard quiet() else { return stopped("R1, the minute at rest") }
            samples += 1
            if isListed(Self.hiddenDivider, of: labPID) { dividerListed += 1 }
            if isListed("blind-menu", of: menu.pid) { helperListed += 1 }
        }
        let blocked = (ice?.events ?? []).filter { seq($0) > mark && ($0["status"] as? String)?.hasPrefix("blocked") == true }.count
        check(lengths(after: mark, applied: nil) == 0 && blocked == 0,
              "R1: 60 s at rest: the length was never retired (\(lengths(after: mark, applied: nil)) retires) and nothing blocked (\(blocked))")
        say("note  R1: in \(samples) reads the copy's hidden divider was listed \(dividerListed) times, the menu helper's item \(helperListed) times")
        check(flag("lengthApplied"), "R1: the copy still rests with the length applied")

        // --- R2: a press on the bar, a menu
        guard openBar() else { check(false, "R2: the IceBar opened"); return 1 }
        var pressed = press("blind-menu")
        check(pressed.sent, "R2: the press of the menu helper's cell was sent")
        var retire = wait(after: pressed.mark, timeout: 3) { self.isLength($0, applied: nil) }
        let opened = until(4) { menu.count("menu", "open") >= 1 }
        check(retire != nil && opened, "R2: the length was retired (\(retire != nil)) and the helper's menu opened (\(opened))")
        spin(3)
        guard quiet() else { return stopped("R2") }
        check(lengths(after: pressed.mark, applied: Self.restLength) == 0, "R2: with the menu open 3 s the length was not applied again")
        menu.send("closemenu")
        var closedAt = Date()
        var again = wait(after: retire.map(seq) ?? pressed.mark, timeout: 6) { self.isLength($0, applied: Self.restLength) }
        check(menu.count("menu", "close") >= 1 && again != nil,
              String(format: "R2: the menu closed and the length was applied again %.1f s after", Date().timeIntervalSince(closedAt)))
        check(until(3) { !self.isListed("blind-menu", of: menu.pid) }, "R2: the helper's item is unlisted again")

        // --- R4: a menu left open past the presser's 60 s
        guard openBar() else { check(false, "R4: the IceBar opened"); return 1 }
        pressed = press("blind-menu")
        retire = wait(after: pressed.mark, timeout: 3) { self.isLength($0, applied: nil) }
        let openedAgain = until(4) { menu.count("menu", "open") >= 2 }
        check(pressed.sent && retire != nil && openedAgain, "R4: pressed again, retired, the menu open")
        for _ in 0..<130 {
            spin(0.5)
            guard quiet() else { return stopped("R4, the menu left open") }
        }
        check(lengths(after: pressed.mark, applied: Self.restLength) == 0, "R4: with the menu open 65 s the length was not applied again")
        menu.send("closemenu")
        closedAt = Date()
        again = wait(after: retire.map(seq) ?? pressed.mark, timeout: 6) { self.isLength($0, applied: Self.restLength) }
        check(again != nil, String(format: "R4: after the menu closed the length was applied again in %.1f s", Date().timeIntervalSince(closedAt)))

        /// The helper before is gone and the next one arrives while the section is hidden; 5 s later the IceBar
        /// is asked for: the bar is read first, then the IceBar lists the arrival.
        func arrive(_ label: String, identifier: String, start: () -> BlindHelper?) -> BlindHelper? {
            closeBar()
            spin(2)
            guard let arrival = start() else { check(false, "\(label): the helper started"); return nil }
            spin(5)
            guard quiet() else { return nil }
            let mark = lastSeq
            let opened = openBar()
            check(opened && lengths(after: mark, applied: nil) == 1 && lengths(after: mark, applied: Self.restLength) == 1,
                  "\(label): the opening read the bar first (retires \(lengths(after: mark, applied: nil)), applied \(lengths(after: mark, applied: Self.restLength))) and the IceBar opened (\(opened))")
            check(until(3) { self.cell(identifier)?.disabled == false }, "\(label): \(identifier) is among the cells, enabled")
            return arrival
        }

        // --- R6 with the popover helper as the arrival, then R4's popover
        menu.stop()
        let popoverStart = {
            self.launch("popover", executable: self.popoverApp.appendingPathComponent("Contents/MacOS/dualband"), domain: "com.icespike4.protected",
                        autosave: "blind-\(self.stamp)-p", position: 30000, arguments: ["blind-popover", "--identifier", "blind-popover"])
        }
        guard let popover = arrive("R6", identifier: "blind-popover", start: popoverStart) else { return interrupted ? stopped("R6") : 1 }
        pressed = press("blind-popover")
        retire = wait(after: pressed.mark, timeout: 3) { self.isLength($0, applied: nil) }
        let shown = until(4) { popover.count("popover open") >= 1 }
        check(pressed.sent && retire != nil && shown, "R4: the popover helper pressed (\(pressed.sent)), retired (\(retire != nil)), its popover open (\(shown))")
        spin(5)
        guard quiet() else { return stopped("R4, the popover") }
        check(lengths(after: pressed.mark, applied: Self.restLength) == 0, "R4: with the popover up 5 s the length was not applied again")
        popover.send("close")
        closedAt = Date()
        again = wait(after: retire.map(seq) ?? pressed.mark, timeout: 6) { self.isLength($0, applied: Self.restLength) }
        check(popover.count("popover close") >= 1 && again != nil,
              String(format: "R4: the popover closed and the length was applied again %.1f s after", Date().timeIntervalSince(closedAt)))

        // --- R3: an item that is not listed in time
        popover.stop()
        guard let second = arrive("R6 again", identifier: "blind-second",
                                  start: { helper("second", app: "Protected", identifier: "blind-second", suffix: "s") })
        else { return interrupted ? stopped("R6 again") : 1 }
        closeBar()
        second.send("hide")
        spin(1)
        guard openBar() else { check(false, "R3: the IceBar opened"); return 1 }
        pressed = press("blind-second")
        retire = wait(after: pressed.mark, timeout: 3) { self.isLength($0, applied: nil) }
        again = wait(after: retire.map(seq) ?? pressed.mark, timeout: 9) { self.isLength($0, applied: Self.restLength) }
        check(pressed.sent && retire != nil && again != nil,
              String(format: "R3: pressed a helper whose item is gone: retired, and the length applied again %.1f s after the retire", time(again) - time(retire)))
        check(until(5) { self.cell("blind-second")?.disabled == true }, "R3: its cell is disabled")

        // --- R7: a member's app that started again
        second.stop()
        guard let restarted = arrive("R7", identifier: "blind-second",
                                     start: { helper("second-again", app: "Protected", identifier: "blind-second", suffix: "s") })
        else { return interrupted ? stopped("R7") : 1 }

        // --- R6, at once: asked within the grace, the debt stays and the next asking reads again
        closeBar()
        restarted.stop()
        spin(2)
        guard let last = helper("arrival2", app: "Hidden3", identifier: "blind-arrival2", suffix: "b") else {
            check(false, "R6 at once: the helper started")
            return 1
        }
        spin(0.5)
        mark = lastSeq
        let atOnce = openBar()
        say("note  R6 at once: opened \(atOnce), retires \(lengths(after: mark, applied: nil)), the arrival listed \(cell("blind-arrival2") != nil)")
        closeBar()
        spin(4)
        guard quiet() else { return stopped("R6, at once") }
        mark = lastSeq
        let later = openBar()
        check(later && until(3) { self.cell("blind-arrival2") != nil },
              "R6 at once: a later opening lists the arrival (retires then: \(lengths(after: mark, applied: nil)))")
        closeBar()

        // --- R8: other lengths, as a limit
        for length in [408.0, 1000.0] {
            ice?.send("length \(Int(length))")
            spin(3)
            guard quiet() else { return stopped("R8") }
            say("note  R8: at \(Int(length)) pt the copy's hidden divider is listed: \(isListed(Self.hiddenDivider, of: labPID)); "
                + "the last helper's item is listed: \(isListed("blind-arrival2", of: last.pid))")
        }
        ice?.send("length release")
        spin(2)
        say("note  R5 (a drag during a hold): not run live; unit-tested (IceBarHoldTests)")
        say(failures.isEmpty ? "RESULT: PASS" : "RESULT: FAIL (\(failures.count))")
        return failures.isEmpty ? 0 : 1
    }

    private func teardown() {
        ice?.send("bar close")
        helpers.forEach { $0.stop() }
        ice?.stop()
        for (domain, key) in seeded {
            Daily.shell("/usr/bin/defaults", ["delete", domain, key])
        }
        spin(2)
        var line = "teardown: helpers stopped, \(seeded.count) placement keys deleted"
        if dailyWasRunning {
            let pid = Daily.relaunch()
            line += ", daily Ice relaunched (pid \(pid.map(String.init) ?? "none"))"
        } else {
            line += ", daily Ice left not running (\(Daily.running().count) running)"
        }
        if let prefsBefore {
            let after = dir.appendingPathComponent("prefs-after.plist")
            let differing = Daily.exportPrefs(to: after) ? Daily.semanticDifferences(prefsBefore, after) : ["unreadable"]
            line += ", daily prefs differing \(differing)"
        }
        say(line)
    }
}
