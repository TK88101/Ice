// Read-only CLI over MenuBarDiscovery (plan section 4.2). Never writes an AX
// attribute, never performs an action, never captures the screen -- every
// mode here only ever reads. See the package's HARD RULES: this binary is
// not run against the real bar except as a one-off smoke check whose output
// (installed app names/bundle ids) is never pasted or committed.
import ApplicationServices
import CryptoKit
import Foundation
import IceCore
import MenuBarDiscovery

let ownIdentifiers = OwnIdentifiers(
    visible: "Ice.ControlItem.Visible",
    hidden: "Ice.ControlItem.Hidden",
    alwaysHidden: "Ice.ControlItem.AlwaysHidden"
)

/// `mbdiscover` is a command-line process with no `NSApplication`, so nothing
/// in it answers Accessibility: reading its own pid can only time out, which
/// would mark every pass incomplete. Ice, an AppKit app that owns the
/// dividers, is the process that must read itself; this tool leaves itself out.
struct OtherProcesses: RunningAppsProviding {
    let base: RunningAppsProviding
    func processes() -> [ProcessInfoRecord] { base.processes().filter { !$0.isSelf } }
    func agentPID() -> Int32? { base.agentPID() }
}

func makeDiscoverer() -> MenuBarDiscoverer {
    MenuBarDiscoverer(
        apps: OtherProcesses(base: LiveRunningApps()),
        reader: LiveExtrasReader(),
        display: LiveDisplay(),
        isTrusted: { AXIsProcessTrusted() },
        ownIdentifiers: ownIdentifiers,
        now: { ProcessInfo.processInfo.systemUptime }
    )
}

func runOneDiscovery() async -> DiscoveryResult? {
    await makeDiscoverer().discover(previous: nil)
}

// MARK: - Plain listing (no args)

func printPlainListing(_ result: DiscoveryResult) {
    let set = result.set

    var byPosition = [String: Int]()
    var byBasis = [String: Int]()
    for item in set.items {
        byPosition[DiscoveryLabels.positionName(item.position), default: 0] += 1
        byBasis[DiscoveryLabels.basisName(item.basis), default: 0] += 1
    }

    print("items: \(set.items.count)")
    print("position: \(formatted(byPosition))")
    print("basis: \(formatted(byBasis))")
    print("systemElements: \(set.systemElements.count)")
    print("ownRead: \(set.ownRead)")
    print("completeness: \(describeCompleteness(set.completeness))")
    print("quarantined: \(result.quarantined.count)")
    print("duration: \(result.duration)")
    print("")

    for entry in DiscoveryLabels.indexed(set) {
        let frameText = entry.item.frame.map { "x=\(fmt($0.minX)) y=\(fmt($0.minY)) w=\(fmt($0.width)) h=\(fmt($0.height))" } ?? "noFrame"
        print("\(entry.owner)\tpid=\(entry.item.key.pid)\tchildIndex=\(entry.childIndex)\tposition=\(DiscoveryLabels.positionName(entry.item.position))\tbasis=\(DiscoveryLabels.basisName(entry.item.basis))\t\(frameText)")
    }
}

func formatted(_ counts: [String: Int]) -> String {
    counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
}

func fmt(_ value: Double) -> String {
    String(format: "%.1f", value)
}

func describeCompleteness(_ completeness: Completeness) -> String {
    switch completeness {
    case .complete: return "complete"
    case .permissionDenied: return "permissionDenied"
    case .incomplete(let failedPIDs): return "incomplete(\(failedPIDs.count) failed)"
    }
}

// MARK: - --plan [--collapsed]

func printPlan(collapsed: Bool) async {
    guard let result = await runOneDiscovery() else {
        print("discovery failed: no display, or cancelled")
        exit(1)
    }

    // Dividers are taken as collapsed only when --collapsed is given
    // (settled well past DiscoveredCachePlan.settleSeconds); otherwise
    // expanded, matching Ice's idle state (plan section 0).
    let state = DividerState(isEnabled: true, isCollapsed: collapsed, collapsedFor: collapsed ? 5.0 : 0.0, changedDuringPass: false)
    let states = DividerStates(hidden: state, alwaysHidden: state)
    let planResult = DiscoveredCachePlan.make(set: result.set, dividerStates: states, previous: [:])

    switch planResult {
    case .keepPrevious(let reason):
        print("keepPrevious: \(reason)")
    case .publish(let publication):
        printPlanSection("visible", publication.visible)
        printPlanSection("hidden", publication.hidden)
        printPlanSection("alwaysHidden", publication.alwaysHidden)
        for note in publication.notes {
            print("note: \(note)")
        }
    }
}

func printPlanSection(_ name: String, _ items: [DiscoveredItem]) {
    print("\(name): \(items.count)")
    for item in items {
        let x = item.frame.map { fmt($0.minX) } ?? "noFrame"
        print("  \(item.key.namespace) pid=\(item.key.pid) x=\(x)")
    }
}

// MARK: - --check <labels.json> [--hash] [--strict]

/// Pids only: nothing here names an app.
func describePIDs(_ processes: [ProcessInfoRecord]) -> String {
    "[" + processes.map { String($0.pid) }.joined(separator: ",") + "]"
}

/// One pass with nothing carried in, or the process ends saying why not.
func discoverOrExit(_ discoverer: MenuBarDiscoverer) async -> DiscoveryResult {
    guard let result = await discoverer.discover(previous: nil) else {
        print("discovery failed: no display, or cancelled")
        exit(1)
    }
    return result
}

func runCheck(labelsPath: String, printHash: Bool, strict: Bool) async {
    let url = URL(fileURLWithPath: labelsPath)
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        print("could not read \(labelsPath): \(error)")
        exit(1)
    }

    if printHash {
        let digest = SHA256.hash(data: data)
        print("labels-hash: \(digest.map { String(format: "%02x", $0) }.joined())")
    }

    let labels: [DiscoveryLabel]
    do {
        labels = try JSONDecoder().decode([DiscoveryLabel].self, from: data)
    } catch {
        print("could not decode \(labelsPath): \(error)")
        exit(1)
    }

    // A warm-up pass on the same discoverer, then the checked pass, neither
    // carrying anything into the other (responsiveness-quarantine plan, 3.6,
    // ledger D-3): a stall first met is counted where it is met, so a single
    // cold pass could never be complete while a suspended process is up. The
    // checked pass's quarantined pids are printed and belong in T6's record;
    // `--strict` refuses any, restoring the old cold-complete meaning.
    let discoverer = makeDiscoverer()
    let warmUp = await discoverOrExit(discoverer)
    print("warm-up: \(describeCompleteness(warmUp.set.completeness)), quarantined \(describePIDs(warmUp.quarantined))")
    let result = await discoverOrExit(discoverer)
    print("checked: quarantined \(result.quarantined.count) \(describePIDs(result.quarantined))")

    // The plan order is checked too (T6): dividers as Ice leaves them at idle
    // (expanded), no previous sections, so every listed item is a new
    // `visible` item in bar order.
    let idle = DividerState(isEnabled: true, isCollapsed: false, collapsedFor: 0, changedDuringPass: false)
    var planVisible: [DiscoveredItem]?
    if case .publish(let publication) = DiscoveredCachePlan.make(set: result.set, dividerStates: DividerStates(hidden: idle, alwaysHidden: idle), previous: [:]) {
        planVisible = publication.visible
    }
    var mismatches = DiscoveryLabels.compare(labels: labels, set: result.set, planVisible: planVisible)
    if strict, !result.quarantined.isEmpty {
        mismatches.append("strict: \(result.quarantined.count) process(es) quarantined, not read")
    }
    if mismatches.isEmpty {
        print("agree: \(labels.count) labels")
        exit(0)
    } else {
        for mismatch in mismatches {
            print(mismatch)
        }
        exit(1)
    }
}

// MARK: - --census-json

struct CensusAttribute<Value: Codable>: Codable {
    let value: Value?
    let error: String
}

struct CensusFrame: Codable {
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double
}

struct CensusRecord: Codable {
    let childIndex: Int
    let role: CensusAttribute<String>
    let identifier: CensusAttribute<String>
    let title: CensusAttribute<String>
    let description: CensusAttribute<String>
    let help: CensusAttribute<String>
    let frame: CensusAttribute<CensusFrame>
}

struct CensusProcess: Codable {
    let pid: Int32
    let owner: String
    let bundleID: String?
    let localizedName: String?
    let executableName: String?
    let launchTime: Double?
    let isSelf: Bool
}

struct CensusRead: Codable {
    let process: CensusProcess
    let extrasError: String
    let extrasElapsed: Double
    let childrenError: String?
    let childrenElapsed: Double?
    let records: [CensusRecord]
    /// Both carried so a census can still tell a truncated walk from a complete
    /// one. Before one attribute error became tolerable, a stop always left
    /// `notAttempted` in the records for a reader to spot; it no longer does,
    /// and this file is the artifact the 2026-09-25 tolerance was argued from.
    let walkInterrupted: Bool
    let childCount: Int
}

func censusRead(from raw: RawRead) -> CensusRead {
    CensusRead(
        process: CensusProcess(
            pid: raw.process.pid,
            owner: ItemNamespace.resolve(raw.process),
            bundleID: raw.process.bundleID,
            localizedName: raw.process.localizedName,
            executableName: raw.process.executableName,
            launchTime: raw.process.launchTime,
            isSelf: raw.process.isSelf
        ),
        extrasError: raw.extrasError,
        extrasElapsed: raw.extrasElapsed,
        childrenError: raw.childrenError,
        childrenElapsed: raw.childrenElapsed,
        records: raw.records.map { record in
            CensusRecord(
                childIndex: record.childIndex,
                role: CensusAttribute(value: record.role.value, error: record.role.error),
                identifier: CensusAttribute(value: record.identifier.value, error: record.identifier.error),
                title: CensusAttribute(value: record.title.value, error: record.title.error),
                description: CensusAttribute(value: record.description.value, error: record.description.error),
                help: CensusAttribute(value: record.help.value, error: record.help.error),
                frame: CensusAttribute(
                    value: record.frame.value.map { CensusFrame(minX: $0.minX, minY: $0.minY, width: $0.width, height: $0.height) },
                    error: record.frame.error
                )
            )
        },
        walkInterrupted: raw.walkInterrupted,
        childCount: raw.childCount
    )
}

func printCensusJSON() {
    let apps = OtherProcesses(base: LiveRunningApps())
    let reader = LiveExtrasReader()
    let processes = apps.processes()
    // A census reads every process whole: no deadline, nothing to cancel.
    let reads = processes.map { reader.read($0, timeout: ReadClassifier.defaultTimeout, interrupt: { false }) }
    let census = reads.map(censusRead(from:))

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let data = try encoder.encode(census)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    } catch {
        print("could not encode census: \(error)")
        exit(1)
    }
}

// MARK: - Entry point

// One line at a time even into a file or a pipe, so a harness can act on a
// pass as soon as it is printed (`--time --watch-pid`), not when the process
// exits and the block buffer finally flushes.
setvbuf(stdout, nil, _IOLBF, 0)

let arguments = Array(CommandLine.arguments.dropFirst())

/// `--time N [--every S] [--watch-pid P]`: N passes in one process, printing
/// each duration, so the warm cost of a pass (plan T6: > 50 ms warm revisits
/// D12) can be read at all -- every other mode is a fresh process and therefore
/// a cold pass. `--every S` starts the passes S seconds apart (start to start);
/// `--watch-pid P` adds, per pass, whether P owns a listed item, failed, or is
/// quarantined -- yes/no only, so a live check can decide from it without any
/// app's name (responsiveness-quarantine plan, section 6).
func runTimed(passes: Int, every spacing: Double?, watchPID: Int32?) async {
    let discoverer = makeDiscoverer()
    var previous: DiscoveredItemSet?
    let clock = ContinuousClock()
    let start = clock.now
    for index in 0..<passes {
        if let spacing {
            let due = start + .milliseconds(Int((spacing * Double(index) * 1000).rounded()))
            if clock.now < due { try? await Task.sleep(until: due, clock: clock) }
        }
        guard let result = await discoverer.discover(previous: previous) else {
            print("pass \(index): discovery failed")
            exit(1)
        }
        previous = result.set
        var line = "pass \(index): \(Int((result.duration * 1000).rounded())) ms, \(result.set.items.count) items, completeness \(result.set.completeness), quarantined \(result.quarantined.count)"
        if let watchPID {
            let item = result.set.listedItems.contains { $0.key.pid == watchPID }
            var failed = false
            if case .incomplete(let pids) = result.set.completeness { failed = pids.contains(watchPID) }
            let quarantined = result.quarantined.contains { $0.pid == watchPID }
            line += ", watch item=\(item ? "yes" : "no") failed=\(failed ? "yes" : "no") quarantined=\(quarantined ? "yes" : "no")"
        }
        print(line)
    }
}

/// The value after `flag`, if both are there.
func value(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

/// `flag`'s value parsed by `parse`; `nil` when the flag is absent. A flag that
/// is present but unreadable ends the process: `--every 5s` silently running
/// the passes back to back would be misread as evidence.
func parsed<T>(_ flag: String, _ parse: (String) -> T?) -> T? {
    guard arguments.contains(flag) else { return nil }
    guard let text = value(after: flag), let result = parse(text) else {
        print("\(flag) needs a value it can read")
        exit(64)
    }
    return result
}

if arguments.contains("--time") {
    let passes = parsed("--time") { Int($0) } ?? 5
    let spacing = parsed("--every") { Double($0) }
    // Checked up front: a negative count or a non-finite spacing would trap
    // (a closed range already refuses NaN and both infinities).
    guard (0...10_000).contains(passes), spacing.map({ (0...3600).contains($0) }) ?? true else {
        print("--time wants 0...10000 passes, --every 0...3600 seconds")
        exit(64)
    }
    await runTimed(passes: passes, every: spacing, watchPID: parsed("--watch-pid") { Int32($0) })
} else if arguments.contains("--census-json") {
    printCensusJSON()
} else if arguments.contains("--plan") {
    await printPlan(collapsed: arguments.contains("--collapsed"))
} else if let checkIndex = arguments.firstIndex(of: "--check") {
    guard arguments.indices.contains(checkIndex + 1) else {
        print("--check requires a path to a labels JSON file")
        exit(1)
    }
    await runCheck(labelsPath: arguments[checkIndex + 1], printHash: arguments.contains("--hash"), strict: arguments.contains("--strict"))
} else {
    guard let result = await runOneDiscovery() else {
        print("discovery failed: no display, or cancelled")
        exit(1)
    }
    printPlainListing(result)
}
