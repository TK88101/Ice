// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q4, Q12-Q14): the
// one capture path of a step. Every capture goes through
// `BoundsRecordingCapturer`, which reads the window server's bounds of every
// glyph helper right after it (deviation 2 C3); every sample is the frozen
// `Sampler` bracket; every judged sample feeds `OverlapGuard`, the oracle and,
// in S0 and S-adv, the live `«` (b) control's episodes (deviation 2 C5).
import Foundation
import IceBarOracle
import IceBarRunCore
import IceCore
import MenuBarCapture

/// Q12: after every capture, the window-server bounds of every glyph helper.
public final class BoundsRecordingCapturer: StripCapturing, @unchecked Sendable {
    public struct Entry: Equatable {
        public let phase: String
        public let bounds: [String: WindowBounds]
    }

    private let base: any StripCapturing
    private let windows: any IceBarWindowListing
    private let lock = NSLock()
    private var helpers = [String: Int32]()
    private var log = [Entry]()
    private var phase = "warm-up"

    public init(base: any StripCapturing, windows: any IceBarWindowListing) {
        self.base = base
        self.windows = windows
    }

    public var entries: [Entry] { lock.withLock { log } }

    func setHelpers(_ pids: [String: Int32]) { lock.withLock { helpers = pids } }
    func setPhase(_ name: String) { lock.withLock { phase = name } }

    public func capture() -> StripImage? {
        guard let image = base.capture() else { return nil }
        let pids = lock.withLock { helpers }
        let listed = StatusWindows.bounds(helpers: pids, windows: windows.windows())
        lock.withLock { log.append(Entry(phase: phase, bounds: listed)) }
        return image
    }
}

/// One frozen bracket, with its start and the bounds read after each capture.
struct Taken {
    let timed: TimedSample
    let bounds: [[String: WindowBounds]]
    let phase: String
}

/// A judged sample: the oracle on both captures, `OverlapGuard`, the verdict.
struct Judged {
    let taken: Taken
    let labels: [CaptureLabels]
    let verdict: AttemptVerdict
    let state: BarState
}

final class Probe {
    let environment: IceBarEnvironment
    let recorder: BoundsRecordingCapturer
    let templates: StageTemplates
    private(set) var roster = [RosterEntry]()
    /// Glyph helpers and the spacer, for the AX read of every sample.
    private(set) var pids = [String: pid_t]()
    var feedsBControl = false
    var collectsC3 = false
    private(set) var episodes = ChevronEpisodes()
    private(set) var c3 = [C3Capture]()
    /// Captures judged (warm-up excluded): one bounds read and, when
    /// `feedsBControl`, one `BObservation` each.
    private(set) var judgedCaptures = 0
    private var sequence = 0

    init(environment: IceBarEnvironment, templates: StageTemplates) {
        self.environment = environment
        self.templates = templates
        recorder = BoundsRecordingCapturer(base: environment.capturer, windows: environment.windows)
    }

    var members: [String] { roster.filter { $0.role == .member }.map(\.id) }
    var visible: [String] { roster.filter { $0.role == .visible }.map(\.id) }
    var rosterIDs: [String] { roster.map(\.id) }
    private var barHeight: Double { environment.geometry.heightPt }

    func register(_ entry: RosterEntry, pid: pid_t) {
        roster.removeAll { $0.id == entry.id }
        roster.append(entry)
        pids[entry.id] = pid
        recorder.setHelpers(glyphPIDs)
    }

    func registerSpacer(pid: pid_t) { pids["spacer"] = pid }

    func unregister(_ id: String) {
        roster.removeAll { $0.id == id }
        pids[id] = nil
        recorder.setHelpers(glyphPIDs)
    }

    private var glyphPIDs: [String: Int32] { pids.filter { $0.key != "spacer" } }

    /// Warm-up captures go through the same recorder but are never judged.
    func warmUp(_ parameters: CadenceParameters) -> Bool {
        recorder.setPhase("warm-up")
        var next = environment.clock.now()
        for _ in 0..<parameters.warmUpCaptures {
            environment.clock.sleep(until: next)
            guard recorder.capture() != nil else { return false }
            next = environment.clock.now() + parameters.warmUpSpacing
        }
        return true
    }

    /// One frozen bracket started no earlier than `notBefore`; `nil` when a capture or the read failed.
    func take(_ phase: String, notBefore: Double) -> Taken? {
        let clock = environment.clock
        clock.sleep(until: notBefore)
        let start = clock.now()
        recorder.setPhase(phase)
        let before = recorder.entries.count
        let sampler = Sampler(capturer: recorder, axReader: environment.axReader, now: { clock.now() })
        guard let sample = sampler.sample(items: pids) else { return nil }
        let entries = recorder.entries
        guard entries.count == before + 2 else { return nil }
        sequence += 1
        environment.evidence.keep(sample.before, label: "\(sequence)-\(phase)-a")
        environment.evidence.keep(sample.after, label: "\(sequence)-\(phase)-b")
        return Taken(timed: TimedSample(start: start, sample: sample), bounds: entries[before...].map(\.bounds), phase: phase)
    }

    /// Q4: the oracle on both captures (agent frames = `canonical` union this
    /// read's on-bar frames), `OverlapGuard` on each capture's bounds, the verdict.
    func judge(_ taken: Taken, canonical: [AgentFrame], leftmost: Double?) -> Judged {
        let sample = taken.timed.sample
        let onBar = sample.agentFrames.filter { $0.minY >= 0 && $0.minY < barHeight }
        let spans = Set((canonical + onBar).map(\.span)).sorted { $0.lo < $1.lo }
        let context = OracleContext(notch: environment.geometry.notch, agentFrames: spans, leftmostReferenceOriginPt: leftmost)
        let helperTemplates = roster.compactMap { templates.helpers[$0.id] }
        let labels = [sample.before, sample.after].map { image -> CaptureLabels in
            do {
                return try Oracle.label(image: image, helpers: helperTemplates, chevron: templates.chevron, context: context)
            } catch {
                // Nothing identified and `«` not evaluable: the attempt is inconclusive.
                return CaptureLabels(labels: [:], matches: [:], sightings: [], inconclusive: [], chevron: .notEvaluable)
            }
        }
        let overlap = OracleSummary.overlap(taken.bounds.map { OverlapGuard.evaluate(roster: rosterIDs, bounds: $0) })
        let visibleHelpers = visible.map { VisibleHelper(id: $0, axMinX: sample.itemFrames[$0]?.minX ?? .infinity) }
        let verdict = AttemptVerdict.evaluate(captures: labels, reads: [sample.agentFrames], barHeightPt: barHeight,
                                              members: Set(members), visible: visibleHelpers, overlap: overlap)
        let state = state(of: taken)
        if feedsBControl {
            let readShows = ChevronRule.fromAX(reads: [sample.agentFrames], barHeightPt: barHeight)
            let pixels = readShows ? chevronUnlisted(sample, canonical: canonical, leftmost: leftmost, helperTemplates: helperTemplates)
                                   : labels.map(\.chevron)
            _ = episodes.observe(readShowsChevron: readShows, captures: pixels)
        }
        if collectsC3 {
            let frames = sample.itemFrames.filter { visible.contains($0.key) }
            c3 += taken.bounds.map { C3Capture(roster: rosterIDs, visible: visible, bounds: $0, visibleFrames: frames) }
        }
        judgedCaptures += labels.count
        environment.evidence.record("sample", [
            "seq": sequence, "phase": taken.phase, "start": taken.timed.start, "end": taken.timed.end,
            "seesMember": verdict.seesMember, "seesChevron": verdict.seesChevron, "inconclusive": verdict.inconclusive,
            "controlMisses": verdict.controlMisses, "overlap": "\(overlap)", "appearance": state.appearance.rawValue,
            "indicator": state.indicator, "labels": labels.map { $0.labels.mapValues { "\($0)" } },
            "agentFrames": sample.agentFrames.map { [$0.minX, $0.minY, $0.width] },
        ])
        return Judged(taken: taken, labels: labels, verdict: verdict, state: state)
    }

    /// Risk K6 (open, owner): with `«` listed by AX, its own frame is one of the
    /// attempt's on-bar agent frames, whose columns the oracle never sees (D6),
    /// so (b) is blind to it by construction and deviation 2 C5's "(a) implies
    /// (b)" could never hold. For the C5 control only, (b) is read as it is used
    /// -- a chevron AX does not list: the same oracle, the chevron-width frames
    /// left out of its context. The safety verdict keeps the registered context.
    private func chevronUnlisted(_ sample: ObservationSample, canonical: [AgentFrame], leftmost: Double?,
                                 helperTemplates: [OracleTemplate]) -> [ChevronSighting] {
        let others = (canonical + sample.agentFrames.filter { $0.minY >= 0 && $0.minY < barHeight })
            .filter { !FoldWitness.isChevron($0, parameters: .preRegistered) }
        let context = OracleContext(notch: environment.geometry.notch, agentFrames: Set(others.map(\.span)).sorted { $0.lo < $1.lo },
                                    leftmostReferenceOriginPt: leftmost)
        return [sample.before, sample.after].map { image in
            (try? Oracle.label(image: image, helpers: helperTemplates, chevron: templates.chevron, context: context))?.chevron ?? .notEvaluable
        }
    }

    /// Q8, Q18: the appearance variant and the indicator state of a sample.
    func state(of taken: Taken) -> BarState {
        let sample = taken.timed.sample
        return BarState(appearance: Appearance.of(sample.before, notch: environment.geometry.notch),
                        indicator: BarState.indicator(sample.agentFrames, barHeightPt: barHeight))
    }

    /// Q8: every member and visible helper `drawn(full)`, every control and the guard clear.
    func controlPassed(_ judged: Judged) -> Bool {
        !judged.verdict.inconclusive && !judged.verdict.chevronNotEvaluable
            && judged.labels.allSatisfy { Controls.memberMisses($0, members: members).isEmpty }
    }
}
