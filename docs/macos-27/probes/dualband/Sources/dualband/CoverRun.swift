//  CoverRun.swift
//  dualband
//
//  T5 of plan 2026-11-15-cover: a lab-identity Ice with sacrificial helpers as its
//  members on the two displays, the daily Ice quit for the run and restored after.

import AppKit
import IceCore
import MenuBarCover

final class CoverSitting {
    static let idleToStart = 300.0
    static let startWait = 4.0 * 3600

    let labApp: URL
    let dir: URL
    private var failures = [String]()
    private var ice: DebugIce?
    private var helpers = [Helper]()
    private var preflight: (prefs: URL, store: [String: String])?
    private let results: FileHandle?

    init(labApp: URL, dir: URL) {
        self.labApp = labApp
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("cover-results.txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        results = try? FileHandle(forWritingTo: url)
    }

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

    private func seq(_ event: [String: Any]) -> Int {
        (event["seq"] as? NSNumber)?.intValue ?? 0
    }

    /// The first event after `after` that `accept` takes, waiting up to `timeout`.
    private func wait(after: Int, timeout: Double, _ accept: ([String: Any]) -> Bool) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let found = ice?.events.first(where: { seq($0) > after && accept($0) }) { return found }
            guard Live.idleSeconds() ?? 0 >= 5 else { return nil }
            spin(0.25)
        }
        return nil
    }

    private func isCover(_ event: [String: Any], withBlocks: Bool) -> Bool {
        guard event["event"] as? String == "cover", let bars = event["bars"] as? [[String: Any]] else { return false }
        let has = bars.contains { !(($0["blocks"] as? [[NSNumber]]) ?? []).isEmpty }
        return has == withBlocks
    }

    private func isLength(_ event: [String: Any], applied: Double?) -> Bool {
        guard event["event"] as? String == "length" else { return false }
        return (event["applied"] as? NSNumber)?.doubleValue == applied
    }

    /// I1 and I2 on a `cover` event's own data.
    private func invariants(_ event: [String: Any], _ label: String) {
        for bar in event["bars"] as? [[String: Any]] ?? [] {
            func slots(_ key: String) -> [CoverSlot] {
                ((bar[key] as? [[NSNumber]]) ?? []).map { CoverSlot(owner: $0[0].int32Value, minX: $0[1].doubleValue, maxX: $0[2].doubleValue) }
            }
            let blocks = ((bar["blocks"] as? [[NSNumber]]) ?? []).map { $0[0].doubleValue...$0[1].doubleValue }
            let verified = slots("verified"), others = slots("slots").filter { !verified.contains($0) }
            let display = (bar["display"] as? NSNumber)?.intValue ?? 0
            check(verified.allSatisfy { slot in blocks.contains { $0.lowerBound <= slot.minX && slot.maxX <= $0.upperBound } },
                  "\(label) display \(display): every verified member slot (\(verified.count)) lies inside a block (\(blocks.count)) [I2]")
            check(!others.contains { slot in blocks.contains { $0.lowerBound < slot.maxX && slot.minX < $0.upperBound } },
                  "\(label) display \(display): no block meets another slot [I1]")
        }
    }

    private func blocks(of display: UInt32, in event: [String: Any]) -> [ClosedRange<Double>] {
        let bar = (event["bars"] as? [[String: Any]])?.first { ($0["display"] as? NSNumber)?.uint32Value == display }
        return ((bar?["blocks"] as? [[NSNumber]]) ?? []).map { $0[0].doubleValue...$0[1].doubleValue }
    }

    func run() -> Int32 {
        defer { teardown() }
        let bars = CoverBars.current()
        guard bars.count == 2, let external = bars.first(where: { CGDisplayIsBuiltin($0.displayID) == 0 }) else {
            say("needs the built-in and one more display")
            return 2
        }
        let deadline = Date().addingTimeInterval(Self.startWait)
        while (Live.idleSeconds() ?? 0) < Self.idleToStart {
            guard Date() < deadline else { say("the Mac never went idle"); return 3 }
            spin(10)
        }
        let running = Daily.running()
        guard running.count <= 1, running.allSatisfy({ $0.bundleURL?.path == Daily.appPath }) else {
            say("another process has the daily id")
            return 2
        }
        let prefs = dir.appendingPathComponent("prefs-before.plist")
        guard Daily.exportPrefs(to: prefs), let store = Daily.settledStore() else { say("the daily Ice's settings could not be read"); return 2 }
        preflight = (prefs, store)
        guard Daily.quit() else { say("the daily Ice did not quit"); return 3 }

        let reader = LiveCoverBarReader()
        let capturer = LiveCoverCapturer()
        let vzhelper = URL(fileURLWithPath: "/private/tmp/claude-501/visibility-live/apps/Target.app/Contents/MacOS/vzhelper")
        let second = URL(fileURLWithPath: "/private/tmp/claude-501/visibility-live/apps/Protected.app/Contents/MacOS/vzhelper")
        do {
            ice = try DebugIce(
                app: labApp, log: dir.appendingPathComponent("cover-report.jsonl"),
                arguments: ["-IceLabReport", "YES", "-SUEnableAutomaticChecks", "NO", "-SUAutomaticallyUpdate", "NO"]
            )
        } catch {
            say("the lab copy did not start: \(error)")
            return 3
        }
        spin(3)
        guard let first = Helper(vzhelper: vzhelper, log: dir.appendingPathComponent("helper-a.log"), items: 2, identifiers: "cover-a,cover-b") else {
            say("the helper did not start")
            return 3
        }
        helpers.append(first)

        // --- resting, covered
        guard let rest = wait(after: 0, timeout: 120, { self.isLength($0, applied: 736) }),
              let covered = wait(after: seq(rest), timeout: 10, { self.isCover($0, withBlocks: true) })
        else {
            check(false, "the lab copy rested at 736 and reported a cover with blocks")
            return 1
        }
        check(true, "the lab copy rested at 736 (seq \(seq(rest))) and reported a cover with blocks (seq \(seq(covered)))")
        invariants(covered, "resting")
        var latest = covered
        check(!blocks(of: external.displayID, in: latest).isEmpty, "the cover has blocks on display \(external.displayID)")

        // --- its own tree reads, 2 Hz for 4 s: the helper's slots lie inside the reported blocks
        var outside = 0, reads = 0
        for _ in 0..<8 {
            spin(0.5)
            if let newer = ice?.events.last(where: { self.isCover($0, withBlocks: true) }) { latest = newer }
            guard let slots = reader.slots(of: external) else { continue }
            reads += 1
            let own = Set(slots).filter { $0.owner == first.pid }
            let reported = blocks(of: external.displayID, in: latest)
            outside += own.filter { slot in !reported.contains { $0.lowerBound <= slot.minX && slot.maxX <= $0.upperBound } }.count
        }
        check(reads >= 6 && outside == 0, "display \(external.displayID): in \(reads) tree reads every helper slot lay inside a reported block (\(outside) outside)")

        // --- pixels, two sessions 13 s apart, the first 13 s after the lab copy's own capture
        for session in 1...2 {
            spin(13)
            let reported = blocks(of: external.displayID, in: latest)
            guard let strips = capturer.strips(of: external), let same = CoverPixels.sameColumns(strips.onScreen, strips.below) else {
                check(false, "session \(session): the strips could not be compared")
                continue
            }
            let differing = reported.reduce(0) { count, block in
                count + (Int(block.lowerBound * external.scale)..<min(same.count, Int(block.upperBound * external.scale))).filter { !same[$0] }.count
            }
            check(differing == 0, "session \(session), display \(external.displayID): on-screen equals below-Menubar over the blocks (\(differing) columns differ)")
            if differing != 0 {
                Live.writePNG(strips.onScreen, to: dir.appendingPathComponent("cover-session\(session)-onscreen.png"))
                Live.writePNG(strips.below, to: dir.appendingPathComponent("cover-session\(session)-below.png"))
            }
        }

        // --- the IceBar opening changes nothing
        var mark = ice?.events.last.map(seq) ?? 0
        ice?.send("bar open")
        spin(3)
        check(!(ice?.events ?? []).contains { seq($0) > mark && isCover($0, withBlocks: false) }, "bar open: the cover did not go")
        ice?.send("bar close")
        spin(1)

        // --- a member more: the real retire. The cover goes before the length does, and comes back over three slots.
        mark = ice?.events.last.map(seq) ?? 0
        guard let added = Helper(vzhelper: second, log: dir.appendingPathComponent("helper-b.log"), items: 1, identifiers: "cover-c", glyphs: "reference") else {
            check(false, "the second helper started")
            return 1
        }
        helpers.append(added)
        let off = wait(after: mark, timeout: 30) { self.isCover($0, withBlocks: false) }
        let retired = wait(after: mark, timeout: 30) { self.isLength($0, applied: nil) }
        check(off != nil && retired != nil && seq(off!) < seq(retired!),
              "a member more: the cover went (seq \(off.map(seq) ?? -1)) before the length was retired (seq \(retired.map(seq) ?? -1))")
        if let retired, let again = wait(after: seq(retired), timeout: 30, { self.isLength($0, applied: 736) }),
           let back = wait(after: seq(again), timeout: 10, { self.isCover($0, withBlocks: true) }) {
            check(true, "the length came back (seq \(seq(again))) and the cover after it (seq \(seq(back)))")
            invariants(back, "after the member")
            spin(2)
            let newest = ice?.events.last(where: { self.isCover($0, withBlocks: true) }) ?? back
            let reported = blocks(of: external.displayID, in: newest)
            let own = Set(reader.slots(of: external) ?? []).filter { $0.owner == first.pid || $0.owner == added.pid }
            check(own.count == 3 && own.allSatisfy { slot in reported.contains { $0.lowerBound <= slot.minX && slot.maxX <= $0.upperBound } },
                  "display \(external.displayID): the three helper slots (\(own.count)) lie inside the blocks")
        } else {
            check(false, "the length and the cover came back after the member change")
        }

        // --- the built-in, as found
        if let builtin = bars.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) {
            let own = Set(reader.slots(of: builtin) ?? []).filter { $0.owner == first.pid || $0.owner == added.pid }
            let newest = ice?.events.last(where: { $0["event"] as? String == "cover" }) ?? [:]
            say("note  built-in: \(own.count) helper slots listed; blocks there: \(blocks(of: builtin.displayID, in: newest))")
        }
        say(failures.isEmpty ? "RESULT: PASS" : "RESULT: FAIL (\(failures.count))")
        return failures.isEmpty ? 0 : 1
    }

    private func teardown() {
        helpers.forEach { $0.stop() }
        ice?.stop()
        guard let preflight else { return }
        spin(2)
        let imported = Daily.importPrefs(from: preflight.prefs)
        let pid = Daily.relaunch()
        spin(30)
        let after = dir.appendingPathComponent("prefs-after.plist")
        let differing = Daily.exportPrefs(to: after) ? Daily.semanticDifferences(preflight.prefs, after) : ["unreadable"]
        let diff = Daily.storeDiff(preflight.store, Daily.settledStore() ?? [:])
        say("teardown: imported \(imported), daily Ice pid \(pid.map(String.init) ?? "none"), prefs differing \(differing), "
            + "store keys changed \(diff.keysChanged.count), values changed \(diff.valuesChanged.count)")
    }
}
