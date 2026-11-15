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
    private func invariants(_ event: [String: Any], _ label: String, own: pid_t) {
        for bar in event["bars"] as? [[String: Any]] ?? [] {
            func slots(_ key: String) -> [CoverSlot] {
                ((bar[key] as? [[NSNumber]]) ?? []).map { CoverSlot(owner: $0[0].int32Value, minX: $0[1].doubleValue, maxX: $0[2].doubleValue) }
            }
            let blocks = ((bar["blocks"] as? [[NSNumber]]) ?? []).map { $0[0].doubleValue...$0[1].doubleValue }
            // Ice's own divider gives its room back at the applied length and is listed inside the last member's slot.
            let verified = slots("verified")
            let owners = Set(verified.map(\.owner))
            let others = slots("slots").filter { !owners.contains($0.owner) && $0.owner != own }
            let display = (bar["display"] as? NSNumber)?.intValue ?? 0
            check(verified.allSatisfy { slot in blocks.contains { $0.lowerBound <= slot.minX && slot.maxX <= $0.upperBound } },
                  "\(label) display \(display): every verified member slot (\(verified.count)) lies inside a block (\(blocks.count)) [I2]")
            check(!others.contains { slot in blocks.contains { $0.lowerBound < slot.maxX && slot.minX < $0.upperBound } },
                  "\(label) display \(display): no block meets a slot of another owner [I1]")
        }
    }

    /// The bar as it is below the lowest window that lies above the lab copy's panel (Alcove's notch):
    /// the panel and everything under it.
    private func belowForeign(_ bar: CoverBar, labPID: pid_t) -> CGImage? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
        var previous: CGWindowID?
        for window in list {
            guard let id = window[kCGWindowNumber as String] as? CGWindowID else { continue }
            if window[kCGWindowOwnerPID as String] as? pid_t == labPID, window[kCGWindowName as String] as? String == "Ice Cover",
               let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
               let bounds = CGRect(dictionaryRepresentation: dictionary), bounds.intersects(bar.frame) {
                guard let previous else { return CGWindowListCreateImage(bar.frame, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) }
                return CGWindowListCreateImage(bar.frame, .optionOnScreenBelowWindow, previous, [.bestResolution])
            }
            previous = id
        }
        return nil
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
        do {
            ice = try DebugIce(
                app: labApp, log: dir.appendingPathComponent("cover-report.jsonl"),
                arguments: ["-IceLabReport", "YES", "-SUEnableAutomaticChecks", "NO", "-SUAutomaticallyUpdate", "NO"]
            )
        } catch {
            say("the lab copy did not start: \(error)")
            return 3
        }
        let labPID = ice?.process.processIdentifier ?? 0
        func latestCover() -> [String: Any] {
            ice?.events.last(where: { $0["event"] as? String == "cover" }) ?? [:]
        }
        func verifiedOwners(_ event: [String: Any]) -> Set<Int32> {
            let bar = (event["bars"] as? [[String: Any]])?.first { ($0["display"] as? NSNumber)?.uint32Value == external.displayID }
            return Set(((bar?["verified"] as? [[NSNumber]]) ?? []).map { $0[0].int32Value })
        }
        /// Every slot of an owner the cover verified, as this process reads the tree, lies inside the reported blocks.
        func outsideBlocks() -> Int? {
            guard let slots = reader.slots(of: external) else { return nil }
            let event = latestCover()
            let owners = verifiedOwners(event), reported = blocks(of: external.displayID, in: event)
            return Set(slots).filter { owners.contains($0.owner) }
                .filter { slot in !reported.contains { $0.lowerBound <= slot.minX && slot.maxX <= $0.upperBound } }.count
        }

        // --- resting, covered (the members are whatever stands left of the lab copy's divider: the owner's own items)
        guard let rest = wait(after: 0, timeout: 120, { self.isLength($0, applied: 736) }),
              wait(after: seq(rest), timeout: 10, { self.isCover($0, withBlocks: true) }) != nil
        else {
            check(false, "the lab copy rested at 736 and reported a cover with blocks")
            return 1
        }
        spin(2)
        let settled = latestCover()
        check(true, "the lab copy rested at 736 (seq \(seq(rest))); settled cover seq \(seq(settled)), "
              + "blocks on display \(external.displayID): \(blocks(of: external.displayID, in: settled))")
        invariants(settled, "resting", own: labPID)
        check(!blocks(of: external.displayID, in: settled).isEmpty, "the cover has blocks on display \(external.displayID)")

        // --- 25 s at rest, two periodic verifications: the cover never goes, and every member slot stays inside it
        var mark = seq(settled)
        var outside = 0, reads = 0
        for _ in 0..<50 {
            spin(0.5)
            if let count = outsideBlocks() {
                reads += 1
                outside += count
            }
        }
        let dropped = (ice?.events ?? []).filter { seq($0) > mark && $0["event"] as? String == "cover" && blocks(of: external.displayID, in: $0).isEmpty }
        check(dropped.isEmpty, "25 s at rest: the cover on display \(external.displayID) never went (\(dropped.count) events without blocks)")
        check(reads >= 40 && outside == 0, "25 s at rest: in \(reads) tree reads every member slot lay inside a reported block (\(outside) outside)")

        // --- pixels, two sessions: below the lowest window above the panel, against below-Menubar
        for session in 1...2 {
            if session == 2 { spin(13) }
            let reported = blocks(of: external.displayID, in: latestCover())
            guard let strips = capturer.strips(of: external), let under = belowForeign(external, labPID: labPID),
                  let same = CoverPixels.sameColumns(under, strips.below)
            else {
                check(false, "session \(session): the strips could not be compared")
                continue
            }
            let differing = reported.reduce(0) { count, block in
                count + (Int(block.lowerBound * external.scale)..<min(same.count, Int(block.upperBound * external.scale))).filter { !same[$0] }.count
            }
            check(differing == 0, "session \(session), display \(external.displayID): with the panel, the bar equals below-Menubar over the blocks (\(differing) columns differ)")
            if differing != 0 {
                Live.writePNG(under, to: dir.appendingPathComponent("cover-session\(session)-under.png"))
                Live.writePNG(strips.below, to: dir.appendingPathComponent("cover-session\(session)-below.png"))
            }
        }

        // --- the IceBar opening changes nothing
        mark = ice?.events.last.map(seq) ?? 0
        ice?.send("bar open")
        spin(3)
        check(!(ice?.events ?? []).contains { seq($0) > mark && $0["event"] as? String == "cover" && blocks(of: external.displayID, in: $0).isEmpty },
              "bar open: the cover did not go")
        ice?.send("bar close")
        spin(1)

        // --- a member more: the real retire. The cover goes before the length does, and comes back over the new member too.
        mark = ice?.events.last.map(seq) ?? 0
        let stamp = Int(Date().timeIntervalSince1970)
        guard let added = Helper(
            vzhelper: vzhelper, log: dir.appendingPathComponent("helper.log"), items: 2, identifiers: "cover-a,cover-b",
            glyphs: "target,reference", autosave: "cover-\(stamp)"
        ) else {
            check(false, "the helper started")
            return 1
        }
        helpers.append(added)
        let retired = wait(after: mark, timeout: 40) { self.isLength($0, applied: nil) }
        let off = (ice?.events ?? []).last { seq($0) > mark && seq($0) < (retired.map(seq) ?? 0) && $0["event"] as? String == "cover" }
        check(retired != nil && off != nil && (off?["bars"] as? [[String: Any]])?.isEmpty == true,
              "a member more: the cover went (seq \(off.map(seq) ?? -1), no bars) before the length was retired (seq \(retired.map(seq) ?? -1))")
        if let retired, let again = wait(after: seq(retired), timeout: 40, { self.isLength($0, applied: 736) }),
           wait(after: seq(again), timeout: 10, { self.isCover($0, withBlocks: true) }) != nil {
            spin(2)
            let back = latestCover()
            check(true, "the length came back (seq \(seq(again))) and the cover after it (seq \(seq(back)))")
            invariants(back, "after the member", own: labPID)
            let own = Set(reader.slots(of: external) ?? []).filter { $0.owner == added.pid }
            let reported = blocks(of: external.displayID, in: back)
            check(own.count == 2 && own.allSatisfy { slot in reported.contains { $0.lowerBound <= slot.minX && slot.maxX <= $0.upperBound } },
                  "display \(external.displayID): the helper's two slots (\(own.count)) lie inside the blocks \(reported)")
            check(outsideBlocks() == 0, "after the member: every member slot lies inside a reported block")
        } else {
            check(false, "the length and the cover came back after the member change")
        }

        // --- the built-in, as found
        if let builtin = bars.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) {
            say("note  built-in: blocks \(blocks(of: builtin.displayID, in: latestCover()))")
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
