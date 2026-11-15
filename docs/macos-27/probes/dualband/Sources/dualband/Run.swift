//  Run.swift
//  dualband
//
//  The T0 sitting (plan 2026-11-15-secondary-display): preflight, the daily Ice
//  out, the Debug Ice in, U0, coarse and fine sweeps per condition, the helper
//  cross-check, and a verified teardown on every way out.

import AppKit
import DualbandCore

struct Abort: Error { let reason: String }

final class Sitting {
    static let menuConditions = [0, 4, 10, 24]
    static let idleToStart = 300.0
    static let inputQuiet = 5.0
    static let partLimit = 20.0 * 60
    static let startWait = 4.0 * 3600

    let debugApp: URL
    let dir: URL
    let vzhelper: URL?
    var bars: [Bar] = []
    var fingerprint = ""
    var ice: DebugIce?
    var helper: Helper?
    var ownerMembers = 0
    let started = Date()
    private let results: FileHandle
    private var done: Set<String> = []
    nonisolated(unsafe) static var stopRequested = false

    init(debugApp: URL, dir: URL, vzhelper: URL?) {
        self.debugApp = debugApp
        self.dir = dir
        self.vzhelper = vzhelper
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("strips"), withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("results.jsonl")
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                if let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], o["event"] as? String == "done",
                   let key = o["key"] as? String { done.insert(key) }
            }
        } else {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        results = try! FileHandle(forWritingTo: url)
        results.seekToEndOfFile()
    }

    func record(_ fields: [String: Any]) {
        var line = fields
        line["at"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) {
            results.write(data + Data("\n".utf8))
        }
        print(String(data: (try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? "")
    }

    // MARK: - Guards

    func guardSample() throws {
        if Sitting.stopRequested { throw Abort(reason: "signal") }
        guard let idle = Live.idleSeconds(), idle >= Sitting.inputQuiet else { throw Abort(reason: "hardware input") }
        guard Live.fingerprint(Live.bars()) == fingerprint else { throw Abort(reason: "display topology changed") }
        guard let ice, ice.isAlive else { throw Abort(reason: "Debug Ice gone") }
        let same = Daily.running()
        guard same.count == 1, same[0].processIdentifier == ice.process.processIdentifier else {
            throw Abort(reason: "a second process with the daily id")
        }
        if Date().timeIntervalSince(started) > Sitting.partLimit { throw Abort(reason: "part limit") }
    }

    // MARK: - Captures and readings

    struct Standard {
        let strips: [GrayStrip]
        let spots: [Range<Int>]
        let masks: [[Range<Int>]]
    }

    func captureAll(tag: String?) throws -> [GrayStrip] {
        try bars.map { bar in
            guard let (strip, image) = Live.capture(bar) else { throw Abort(reason: "capture failed") }
            if let tag { Live.writePNG(image, to: dir.appendingPathComponent("strips/\(tag)-\(bar.displayID).png")) }
            return strip
        }
    }

    /// Standard length, settled, captured twice; the spot from the roster's frames.
    func standard(cond: String, helperOnly: Bool = false) throws -> Standard {
        ice?.send("length standard")
        Thread.sleep(forTimeInterval: 1.5)
        try guardSample()
        let first = try captureAll(tag: nil)
        Thread.sleep(forTimeInterval: 1.0)
        let second = try captureAll(tag: "\(cond)-standard")
        let masks = bars.map { Masks.excluded(on: $0, ownPID: getpid()) }
        for index in bars.indices {
            let drift = Judge.changedLeft(of: second[index].width, sample: second[index], standard: first[index], excluded: masks[index])
            guard drift <= Judge.maxNewForeground else { throw Abort(reason: "standard strip unstable on \(bars[index].displayID): \(drift)") }
        }
        guard let snapshot = ice?.snapshot else { throw Abort(reason: "no snapshot") }
        let frames = DebugIce.memberFrames(snapshot, namespace: helperOnly ? "com.icespike4.target" : nil)
        guard !frames.isEmpty, let reference = bars.first(where: { bar in
            frames.allSatisfy { $0[0] + $0[2] / 2 >= bar.x && $0[0] + $0[2] / 2 <= bar.maxX }
        }) else {
            throw Abort(reason: "no member frames on one bar")
        }
        let spots = try bars.map { bar in
            guard let spot = Spot.columns(frames: frames, reference: reference, on: bar) else { throw Abort(reason: "spot off bar \(bar.displayID)") }
            return spot
        }
        let strips = second
        // The judge must see the members at standard length, or it is blind there.
        for index in bars.indices {
            let reading = try Judge.read(sample: strips[index], standard: strips[index], spot: spots[index], excluded: masks[index])
            guard !reading.hides else { throw Abort(reason: "judge blind at standard on \(bars[index].displayID)") }
        }
        record(["event": "standard", "cond": cond, "spots": spots.map { [$0.lowerBound, $0.upperBound] },
                "masks": masks.map { $0.map { [$0.lowerBound, $0.upperBound] } }, "reference": reference.displayID])
        return Standard(strips: strips, spots: spots, masks: masks)
    }

    /// One length: settled 1 s, read at 1 s and 2 s; per bar `hides`, or nil when the two disagree.
    func sample(_ length: Double, cond: String, part: String, base: Standard, save: Bool = false) throws -> [Bool?] {
        ice?.send("length \(Int(length))")
        Thread.sleep(forTimeInterval: 1.0)
        try guardSample()
        let a = try captureAll(tag: nil)
        Thread.sleep(forTimeInterval: 1.0)
        try guardSample()
        let b = try captureAll(tag: save ? "\(cond)-\(part)-\(Int(length))" : nil)
        var verdicts: [Bool?] = []
        for index in bars.indices {
            let ra = try Judge.read(sample: a[index], standard: base.strips[index], spot: base.spots[index], excluded: base.masks[index])
            let rb = try Judge.read(sample: b[index], standard: base.strips[index], spot: base.spots[index], excluded: base.masks[index])
            let verdict: Bool? = ra.hides == rb.hides ? rb.hides : nil
            verdicts.append(verdict)
            record(["event": "sample", "part": part, "cond": cond, "bar": bars[index].displayID, "length": length,
                    "new": [ra.newForeground, rb.newForeground], "spot": [ra.spotForeground, rb.spotForeground],
                    "hides": verdict.map { $0 as Any } ?? NSNull()])
        }
        return verdicts
    }

    // MARK: - Stages

    func conditions() -> [(key: String, bar: Bar, menus: Int)] {
        bars.enumerated().flatMap { index, bar in Sitting.menuConditions.map { (key: "a\(index)-m\($0)", bar: bar, menus: $0) } }
    }

    func enter(_ condition: (key: String, bar: Bar, menus: Int)) throws {
        let active = Front.present(menus: condition.menus, on: condition.bar)
        Thread.sleep(forTimeInterval: 1.5)
        record(["event": "condition", "cond": condition.key, "asked": condition.bar.displayID, "active": active.map { $0 as Any } ?? NSNull(), "menus": condition.menus])
    }

    func u0() throws {
        guard !done.contains("u0") else { return }
        let condition = conditions()[0]
        try enter(condition)
        let base = try standard(cond: "u0")
        ice?.send("length 736")
        for wait in [1.0, 2.0] {
            Thread.sleep(forTimeInterval: wait)
            try guardSample()
            let strips = try captureAll(tag: "u0-736-\(Int(wait == 1 ? 1 : 3))s")
            let readings = try bars.indices.map { try Judge.read(sample: strips[$0], standard: base.strips[$0], spot: base.spots[$0], excluded: base.masks[$0]) }
            record(["event": "u0", "after": wait == 1 ? 1 : 3, "dividerWidth": ice?.snapshot.flatMap(DebugIce.dividerWidth).map { $0 as Any } ?? NSNull(),
                    "hides": readings.map(\.hides), "new": readings.map(\.newForeground), "spot": readings.map(\.spotForeground)])
        }
        record(["event": "done", "key": "u0"])
    }

    func coarse() throws {
        for condition in conditions() where !done.contains("coarse-\(condition.key)") {
            try enter(condition)
            let base = try standard(cond: condition.key)
            var top = Sweep.coarseMax
            var grid = Sweep.coarseGrid(upTo: top)
            var perBar: [[(length: Double, hides: Bool)]] = Array(repeating: [], count: bars.count)
            var index = 0
            while index < grid.count {
                let verdicts = try sample(grid[index], cond: condition.key, part: "coarse", base: base, save: true)
                for bar in bars.indices { if let v = verdicts[bar] { perBar[bar].append((grid[index], v)) } }
                index += 1
                if index == grid.count, top == Sweep.coarseMax, perBar.contains(where: Sweep.changingAtTop) {
                    top += Sweep.extension_
                    grid = Sweep.coarseGrid(upTo: top)
                }
            }
            record(["event": "done", "key": "coarse-\(condition.key)", "top": top])
        }
    }

    func fine(transitions: [Double]) throws {
        let grid = Sweep.fineGrid(around: transitions)
        for condition in conditions() where !done.contains("fine-\(condition.key)") {
            try enter(condition)
            let base = try standard(cond: condition.key)
            var hit: [Double: Int] = [:]
            for (part, order) in [("fine-up", grid), ("fine-down", grid.reversed())] {
                for length in order {
                    let verdicts = try sample(length, cond: condition.key, part: part, base: base)
                    if verdicts.contains(where: { $0 == true }) { hit[length, default: 0] += 1 }
                }
            }
            for length in hit.filter({ $0.value == 2 }).keys.sorted() {
                for _ in 0..<3 {
                    ice?.send("length standard")
                    Thread.sleep(forTimeInterval: 1.0)
                    _ = try sample(length, cond: condition.key, part: "jump", base: base)
                }
            }
            record(["event": "done", "key": "fine-\(condition.key)"])
        }
    }

    /// Step 4: the helper as one more member; at P's bounding points, its glyph beside the strip judge.
    func helperCheck(points: [Double]) throws {
        guard !done.contains("helper") else { return }
        guard let vzhelper, let started = Helper(vzhelper: vzhelper, log: dir.appendingPathComponent("helper.log")) else {
            record(["event": "helper", "result": "unavailable"])
            return
        }
        helper = started
        guard ice?.waitSnapshot(timeout: 60, { DebugIce.memberFrames($0).count == self.ownerMembers + 1 }) != nil else {
            throw Abort(reason: "helper never became a member")
        }
        let condition = conditions()[0]
        try enter(condition)
        let base = try standard(cond: "helper")
        let helperBase = try standard(cond: "helper-only", helperOnly: true)
        var disagreements = 0
        for length in points {
            ice?.send("length \(Int(length))")
            Thread.sleep(forTimeInterval: 2.0)
            try guardSample()
            let strips = try captureAll(tag: "helper-\(Int(length))")
            for index in bars.indices {
                let reading = try Judge.read(sample: strips[index], standard: base.strips[index], spot: base.spots[index], excluded: base.masks[index])
                let template = Template.crop(helperBase.strips[index], columns: helperBase.spots[index])
                let score = Template.bestScore(of: template, in: strips[index], before: base.spots[index].upperBound)
                let helperDrawn = score >= 0.8
                if reading.hides && helperDrawn { disagreements += 1 }
                record(["event": "helper", "bar": bars[index].displayID, "length": length, "hides": reading.hides, "score": score])
            }
        }
        record(["event": "done", "key": "helper", "disagreements": disagreements])
        started.stop()
        helper = nil
    }

    // MARK: - Analysis

    func load() -> [[String: Any]] {
        let text = (try? String(contentsOf: dir.appendingPathComponent("results.jsonl"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    func transitionsFromCoarse() -> [Double] {
        var all = Set<Double>()
        let samples = load().filter { $0["event"] as? String == "sample" && $0["part"] as? String == "coarse" }
        let groups = Dictionary(grouping: samples) { "\($0["cond"] ?? "")/\($0["bar"] ?? "")" }
        for group in groups.values {
            let readings = group.compactMap { o -> (length: Double, hides: Bool)? in
                guard let l = o["length"] as? Double, let h = o["hides"] as? Bool else { return nil }
                return (l, h)
            }
            all.formUnion(Sweep.transitions(readings))
        }
        return all.sorted()
    }

    /// Per bar, the hiding points over every condition (fine, up, down and jumps), and whether anything was unreadable near them.
    func pointSets() -> (sets: [UInt32: Set<Double>], inconclusive: Bool) {
        let samples = load().filter { o in ["fine-up", "fine-down", "jump"].contains(o["part"] as? String ?? "") }
        var unreadable = Set<Double>()
        var sets: [UInt32: Set<Double>] = [:]
        for bar in bars {
            let mine = samples.filter { ($0["bar"] as? NSNumber)?.uint32Value == bar.displayID }
            let byCondition = Dictionary(grouping: mine) { $0["cond"] as? String ?? "" }.values.map { group -> [Double: [Bool]] in
                var map: [Double: [Bool]] = [:]
                for o in group {
                    guard let l = o["length"] as? Double else { continue }
                    if let h = o["hides"] as? Bool { map[l, default: []].append(h) } else { map[l, default: []].append(false); unreadable.insert(l) }
                }
                return map
            }
            sets[bar.displayID] = Sweep.hidingPoints(byCondition)
        }
        let candidates = sets.values.reduce(into: Set<Double>()) { $0.formUnion($1) }
        let near = candidates.contains { p in unreadable.contains { abs($0 - p) <= Sweep.fineStep } }
        return (sets, near)
    }

    // MARK: - Sitting

    func run() -> Int32 {
        var preflight: (prefs: URL, store: [String: String])?
        defer { teardown(preflight) }
        do {
            preflight = try setUp()
            try u0()
            try coarse()
            let transitions = transitionsFromCoarse()
            record(["event": "transitions", "lengths": transitions])
            if !transitions.isEmpty { try fine(transitions: transitions) }
            let (sets, inconclusive) = pointSets()
            let builtin = bars.first(where: \.isBuiltin).flatMap { sets[$0.displayID] } ?? []
            let sidecar = bars.first(where: { !$0.isBuiltin }).flatMap { sets[$0.displayID] } ?? []
            let bounds = [builtin, sidecar].flatMap { set -> [Double] in
                guard let lo = set.min(), let hi = set.max() else { return [] }
                return [lo - Sweep.fineStep, lo, hi, hi + Sweep.fineStep]
            }
            try helperCheck(points: Array(Set(bounds)).sorted())
            let helperLines = load().filter { $0["event"] as? String == "done" && $0["key"] as? String == "helper" }
            let helperOK = (helperLines.last?["disagreements"] as? Int) == 0
            let branch = Sweep.decide(builtin: builtin, sidecar: sidecar, inconclusive: inconclusive || !helperOK)
            record(["event": "result", "builtin": builtin.sorted(), "sidecar": sidecar.sorted(), "inconclusive": inconclusive,
                    "helperOK": helperOK, "branch": "\(branch)"])
            return 0
        } catch let abort as Abort {
            record(["event": "abort", "reason": abort.reason])
            return 3
        } catch {
            record(["event": "abort", "reason": "\(error)"])
            return 3
        }
    }

    func setUp() throws -> (prefs: URL, store: [String: String]) {
        bars = Live.bars()
        fingerprint = Live.fingerprint(bars)
        guard bars.count == 2, bars.contains(where: \.isBuiltin) else { throw Abort(reason: "needs the built-in and one more display") }
        let deadline = Date().addingTimeInterval(Sitting.startWait)
        while (Live.idleSeconds() ?? 0) < Sitting.idleToStart {
            guard Date() < deadline, !Sitting.stopRequested else { throw Abort(reason: "the Mac never went idle") }
            Thread.sleep(forTimeInterval: 10)
        }
        let running = Daily.running()
        guard running.count <= 1, running.allSatisfy({ $0.bundleURL?.path == Daily.appPath }) else {
            throw Abort(reason: "another process has the daily id")
        }
        let prefs = dir.appendingPathComponent("prefs-before.plist")
        if !FileManager.default.fileExists(atPath: prefs.path) {
            guard Daily.exportPrefs(to: prefs) else { throw Abort(reason: "prefs export failed") }
        }
        guard let store = Daily.settledStore() else { throw Abort(reason: "store unreadable") }
        record(["event": "start", "fingerprint": fingerprint, "bars": bars.map { "\($0.displayID) \($0.name) \($0.width)x\($0.height)" },
                "storeKeys": store.count])
        guard Daily.quit() else { throw Abort(reason: "daily Ice did not quit") }
        ice = try DebugIce(app: debugApp, log: dir.appendingPathComponent("report-\(Int(Date().timeIntervalSince1970)).jsonl"))
        guard let ready = ice?.waitSnapshot(timeout: 90, { s in
            s["hiddenBoundaryUsable"] as? Bool == true && !DebugIce.memberFrames(s).isEmpty
        }) else {
            throw Abort(reason: "Debug Ice never listed members")
        }
        ownerMembers = DebugIce.memberFrames(ready).count
        record(["event": "ready", "members": ownerMembers])
        return (prefs, store)
    }

    func teardown(_ preflight: (prefs: URL, store: [String: String])?) {
        helper?.stop()
        ice?.stop()
        guard let preflight else { return }
        Thread.sleep(forTimeInterval: 2)
        let imported = Daily.importPrefs(from: preflight.prefs)
        let pid = Daily.relaunch()
        Thread.sleep(forTimeInterval: 30)
        let after = dir.appendingPathComponent("prefs-after-\(Int(Date().timeIntervalSince1970)).plist")
        let exported = Daily.exportPrefs(to: after)
        let same = exported && FileManager.default.contentsEqual(atPath: preflight.prefs.path, andPath: after.path)
        let store = Daily.settledStore() ?? [:]
        let diff = Daily.storeDiff(preflight.store, store)
        record(["event": "teardown", "imported": imported, "dailyPID": pid.map { $0 as Any } ?? NSNull(), "prefsEqual": same,
                "storeKeysChanged": diff.keysChanged.count, "storeValuesChanged": diff.valuesChanged.count])
    }
}

@MainActor
enum Run {
    static func main(debugApp: URL, dir: URL, resume: Bool) {
        signal(SIGINT) { _ in Sitting.stopRequested = true }
        signal(SIGTERM) { _ in Sitting.stopRequested = true }
        signal(SIGHUP) { _ in Sitting.stopRequested = true }
        let vz = URL(fileURLWithPath: "/private/tmp/claude-501/visibility-live/apps/Target.app/Contents/MacOS/vzhelper")
        let sitting = Sitting(debugApp: debugApp, dir: dir, vzhelper: FileManager.default.isExecutableFile(atPath: vz.path) ? vz : nil)
        NSApplication.shared.setActivationPolicy(.regular)
        Thread {
            let status = sitting.run()
            DispatchQueue.main.async { exit(status) }
        }.start()
        NSApp.run()
    }
}
