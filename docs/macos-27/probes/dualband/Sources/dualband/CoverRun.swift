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
    static let inputQuiet = 5.0

    let labApp: URL
    let dir: URL
    private var failures = [String]()
    private var ice: DebugIce?
    private var helpers = [Helper]()
    private var preflight: (prefs: URL, store: [String: String])?
    private var storeBefore: NSDictionary?
    private var interrupted = false
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
            guard quiet() else { return nil }
            spin(0.25)
        }
        return nil
    }

    /// False from the first hardware input on: the sitting stops there and the daily Ice comes back.
    private func quiet() -> Bool {
        if (Live.idleSeconds() ?? 0) < Self.inputQuiet { interrupted = true }
        return !interrupted
    }

    /// A stop on input is no result of the step it fell in.
    private func stopped(_ step: String) -> Int32 {
        say("STOPPED  hardware input during \(step); what was not reached is not measured")
        return 4
    }

    /// What `MenuBarAgent` and the whole system answer at a point of a bar, with the error when there is no element.
    private func rawHit(x: Double, bar: CoverBar, helper: pid_t, lab: pid_t) -> String {
        guard let agent = LiveCoverBarReader.agentPID() else { return "no agent" }
        func name(_ pid: pid_t) -> String {
            pid == agent ? "the agent" : pid == helper ? "the helper" : pid == lab ? "the lab copy" : "pid \(pid)"
        }
        func hit(_ root: AXUIElement) -> String {
            AXUIElementSetMessagingTimeout(root, 1)
            var element: AXUIElement?
            let error = AXUIElementCopyElementAtPosition(root, Float(bar.frame.minX) + Float(x), Float(bar.frame.midY), &element)
            guard error == .success, let element else { return "AXError \(error.rawValue)" }
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            var role: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            return "\(name(pid)) \(role as? String ?? "no role")"
        }
        return "agent -> \(hit(AXUIElementCreateApplication(agent))), system-wide -> \(hit(AXUIElementCreateSystemWide()))"
    }

    /// Where the lab copy's last snapshot lists the helpers' items.
    private func helperSections() -> String {
        guard let snapshot = ice?.snapshot else { return "no snapshot" }
        func count(_ key: String) -> Int {
            (snapshot[key] as? [[String: Any]] ?? []).filter { ($0["namespace"] as? String)?.hasPrefix("com.icespike4.") == true }.count
        }
        return "hidden \(count("cacheHidden")), visible \(count("cacheVisible"))"
    }

    /// One bar of a `cover` event.
    private struct ReportedBar {
        let display: UInt32
        let slots: [CoverSlot]
        let verified: [CoverSlot]
        let blocks: [ClosedRange<Double>]
    }

    /// The bars of a `cover` event; `nil` for another event and for one not shaped as
    /// `LabReportCoverBar.json` writes it, so no check passes on a list that only failed to decode.
    private func coverBars(_ event: [String: Any]) -> [ReportedBar]? {
        guard event["event"] as? String == "cover", let raw = event["bars"] as? [[String: Any]] else { return nil }
        func slots(_ value: Any?) -> [CoverSlot]? {
            guard let rows = value as? [[NSNumber]], rows.allSatisfy({ $0.count == 3 }) else { return nil }
            return rows.map { CoverSlot(owner: $0[0].int32Value, minX: $0[1].doubleValue, maxX: $0[2].doubleValue) }
        }
        var bars = [ReportedBar]()
        for bar in raw {
            guard let display = (bar["display"] as? NSNumber)?.uint32Value, let all = slots(bar["slots"]), let verified = slots(bar["verified"]),
                  let rows = bar["blocks"] as? [[NSNumber]], rows.allSatisfy({ $0.count == 2 && $0[0].doubleValue <= $0[1].doubleValue })
            else {
                return nil
            }
            bars.append(ReportedBar(display: display, slots: all, verified: verified, blocks: rows.map { $0[0].doubleValue...$0[1].doubleValue }))
        }
        return bars
    }

    private func inside(_ slot: CoverSlot, _ blocks: [ClosedRange<Double>]) -> Bool {
        blocks.contains { $0.lowerBound <= slot.minX && slot.maxX <= $0.upperBound }
    }

    private func isCover(_ event: [String: Any], withBlocks: Bool) -> Bool {
        guard let bars = coverBars(event) else { return false }
        return bars.contains { !$0.blocks.isEmpty } == withBlocks
    }

    private func isLength(_ event: [String: Any], applied: Double?) -> Bool {
        guard event["event"] as? String == "length" else { return false }
        return (event["applied"] as? NSNumber)?.doubleValue == applied
    }

    /// I1 and I2 on a `cover` event's own data.
    private func invariants(_ event: [String: Any], _ label: String, own: pid_t) {
        guard let bars = coverBars(event) else {
            check(false, "\(label): the cover event could be read")
            return
        }
        for bar in bars {
            // Ice's own divider gives its room back at the applied length and is listed inside the last member's slot.
            let owners = Set(bar.verified.map(\.owner))
            let others = bar.slots.filter { !owners.contains($0.owner) && $0.owner != own }
            check(bar.verified.allSatisfy { inside($0, bar.blocks) },
                  "\(label) display \(bar.display): every verified member slot (\(bar.verified.count)) lies inside a block (\(bar.blocks.count)) [I2]")
            check(!others.contains { slot in bar.blocks.contains { $0.lowerBound < slot.maxX && slot.minX < $0.upperBound } },
                  "\(label) display \(bar.display): no block meets a slot of another owner [I1]")
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

    /// A display's blocks in a `cover` event; none also when the event cannot be read.
    private func blocks(of display: UInt32, in event: [String: Any]) -> [ClosedRange<Double>] {
        coverBars(event)?.first { $0.display == display }?.blocks ?? []
    }

    /// The `cover` events after `mark` that left a display without blocks.
    private func coverDrops(after mark: Int, display: UInt32) -> Int {
        (ice?.events ?? []).filter { seq($0) > mark && $0["event"] as? String == "cover" && blocks(of: display, in: $0).isEmpty }.count
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
        storeBefore = NSDictionary(contentsOfFile: Daily.storePath + ".plist")
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
        /// How many slots of the owners the cover verified, as this process reads the tree, lie outside the reported blocks.
        func outsideBlocks() -> Int? {
            guard let slots = reader.slots(of: external), let bar = coverBars(latestCover())?.first(where: { $0.display == external.displayID })
            else {
                return nil
            }
            let owners = Set(bar.verified.map(\.owner))
            return Set(slots).filter { owners.contains($0.owner) && !inside($0, bar.blocks) }.count
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

        // --- a member more: the real retire. The cover goes before the length does, and comes back over the new member too.
        var mark = ice?.events.last.map(seq) ?? 0
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
        guard !interrupted else { return stopped("the wait for the retire") }
        if retired == nil { say("note  no retire in 40 s; the helper's items: \(helperSections())") }
        let off = (ice?.events ?? []).last { seq($0) > mark && seq($0) < (retired.map(seq) ?? 0) && $0["event"] as? String == "cover" }
        check(retired != nil && off.flatMap(coverBars)?.isEmpty == true,
              "a member more: the cover went (seq \(off.map(seq) ?? -1), no bars) before the length was retired (seq \(retired.map(seq) ?? -1))")
        if let retired, let again = wait(after: seq(retired), timeout: 40, { self.isLength($0, applied: 736) }),
           wait(after: seq(again), timeout: 10, { self.isCover($0, withBlocks: true) }) != nil {
            spin(2)
            let back = latestCover()
            check(true, "the length came back (seq \(seq(again))) and the cover after it (seq \(seq(back)))")
            invariants(back, "after the member", own: labPID)
            let own = Set(reader.slots(of: external) ?? []).filter { $0.owner == added.pid }
            let reported = blocks(of: external.displayID, in: back)
            // The helper's slots outside every block lie under no panel: what a hit test answers there
            // and whether the helper is drawn there say why they were not verified.
            let bare = own.filter { !inside($0, reported) }.sorted { $0.minX < $1.minX }
            check(own.count == 2 && bare.isEmpty, "display \(external.displayID): the helper's two slots (\(own.count)) lie inside the blocks \(reported)")
            check(outsideBlocks() == 0, "after the member: every member slot lies inside a reported block")
            if !bare.isEmpty {
                // One capture session: is the helper drawn where the tree lists it?
                let strips = capturer.strips(of: external)
                let same = strips.flatMap { CoverPixels.sameColumns($0.onScreen, $0.below) }
                for slot in bare {
                    let hits = reader.owners(at: CoverPlan.verificationPoints(slot), of: external)
                        .map { $0 == slot.owner ? "own" : $0.map { "pid \($0)" } ?? "nil" }
                    let columns = Int(slot.minX * external.scale)..<min(same?.count ?? 0, Int(slot.maxX * external.scale))
                    let drawn = same.map { same in "\(columns.filter { !same[$0] }.count) of \(columns.count)" } ?? "unread"
                    say("note  helper slot \(slot.minX)-\(slot.maxX) outside the blocks; hit test at its verification points: \(hits); "
                        + "raw at its middle: \(rawHit(x: (slot.minX + slot.maxX) / 2, bar: external, helper: added.pid, lab: labPID)); "
                        + "columns where on-screen differs from below-Menubar: \(drawn)")
                }
                if let strips, let first = bare.first, let last = bare.last {
                    let crop = CGRect(
                        x: (first.minX - 30) * external.scale, y: 0, width: (last.maxX - first.minX + 60) * external.scale, height: Double(strips.onScreen.height)
                    )
                    if let image = strips.onScreen.cropping(to: crop) { Live.writePNG(image, to: dir.appendingPathComponent("helper-slots-onscreen.png")) }
                }
            }
        } else {
            guard !interrupted else { return stopped("the wait for the length and the cover to come back") }
            check(false, "the length and the cover came back after the member change")
        }

        // --- 25 s at rest, two periodic verifications: the cover never goes, and every member slot stays inside it
        mark = seq(latestCover())
        var outside = 0, reads = 0
        for _ in 0..<50 {
            spin(0.5)
            guard quiet() else { return stopped("the 25 s at rest") }
            if let count = outsideBlocks() {
                reads += 1
                outside += count
            }
        }
        let drops = coverDrops(after: mark, display: external.displayID)
        check(drops == 0, "25 s at rest: the cover on display \(external.displayID) never went (\(drops) events without blocks)")
        check(reads >= 40 && outside == 0, "25 s at rest: in \(reads) tree reads every member slot lay inside a reported block (\(outside) outside)")

        // --- pixels, two sessions: below the lowest window above the panel, against below-Menubar
        for session in 1...2 {
            if session == 2 { spin(13) }
            guard quiet() else { return stopped("the pixel sessions") }
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
        check(coverDrops(after: mark, display: external.displayID) == 0, "bar open: the cover did not go")
        ice?.send("bar close")
        spin(1)

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
        // Which of the store's values changed, and inside a dictionary which keys: the helpers' own (named), any other (counted).
        let storeAfter = NSDictionary(contentsOfFile: Daily.storePath + ".plist")
        for key in diff.valuesChanged {
            guard let old = storeBefore?[key] as? [String: NSObject], let new = storeAfter?[key] as? [String: NSObject] else {
                say("teardown: store value \(key) changed (not a dictionary)")
                continue
            }
            let changed = Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }
            let helpers = changed.filter { $0.contains("vzhelper") }.sorted()
            say("teardown: store value \(key): the helpers' keys changed \(helpers), keys of other apps changed \(changed.count - helpers.count)")
        }
        say("teardown: imported \(imported), daily Ice pid \(pid.map(String.init) ?? "none"), prefs differing \(differing), "
            + "store keys changed \(diff.keysChanged.count), values changed \(diff.valuesChanged.count)")
    }
}
