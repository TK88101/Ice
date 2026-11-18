//  CoverController.swift
//  MenuBarCover

import CoreGraphics
import Foundation
import IceCore

/// Plan 2026-11-15-cover: while Ice rests with the hidden length applied,
/// keeps a panel over every hidden-section member that `MenuBarAgent` still
/// lays out on a bar. Main thread only, except a pass's body, which runs
/// where `Environment.background` puts it; every result comes back through
/// `Environment.main` and is applied only if its generation is still current.
public final class CoverController {
    public struct Environment {
        public var bars: () -> [CoverBar]
        /// What a bar's background depends on besides the windows under its
        /// strip: the display's Space, light or dark, the wallpaper's stamp.
        public var backgroundKey: (CoverBar) -> String
        public var canCapture: () -> Bool
        public var now: () -> Double
        /// Runs a pass off the main thread.
        public var background: (@escaping () -> Void) -> Void
        /// Delivers on the main thread.
        public var main: (@escaping () -> Void) -> Void
        /// From a pass: runs on the main thread and waits.
        public var mainSync: (() -> Void) -> Void
        /// On the main thread, after that many seconds.
        public var after: (Double, @escaping () -> Void) -> Void
        /// From a pass: waits that many seconds.
        public var pause: (Double) -> Void
        /// Ice's own pid: its hidden divider's slot is no overlap (`CoverSilentTrack`).
        public var ownPID: Int32

        public init(
            bars: @escaping () -> [CoverBar], backgroundKey: @escaping (CoverBar) -> String, canCapture: @escaping () -> Bool,
            now: @escaping () -> Double, background: @escaping (@escaping () -> Void) -> Void,
            main: @escaping (@escaping () -> Void) -> Void, mainSync: @escaping (() -> Void) -> Void,
            after: @escaping (Double, @escaping () -> Void) -> Void, pause: @escaping (Double) -> Void,
            ownPID: Int32 = ProcessInfo.processInfo.processIdentifier
        ) {
            self.bars = bars
            self.backgroundKey = backgroundKey
            self.canCapture = canCapture
            self.now = now
            self.background = background
            self.main = main
            self.mainSync = mainSync
            self.after = after
            self.pause = pause
            self.ownPID = ownPID
        }
    }

    /// The slots under panels are hit-tested again this often (their panels
    /// ignore mouse events meanwhile); the others are tried every pass.
    public static let reverifyEvery = 10.0
    /// After a change of the active display the panels stay this long without
    /// a fresh verification, then go (D5).
    public static let forcedDeadline = 0.5
    /// After the length is applied the bar is laid out anew; a read taken
    /// meanwhile lists slots half moved (MEASURED 2026-11-15, T5).
    public static let activationSettle = 0.3
    /// A panel told to ignore mouse events still stops a hit test until the
    /// window server has heard of it (MEASURED 2026-11-15, T5: every periodic
    /// verification failed without this wait). Polled this often, this many times.
    public static let openPoll = 0.01
    public static let openPolls = 20

    private struct BarState {
        var slots = [CoverSlot]()
        var candidates = [CoverSlot]()
        /// Confirmed by a hit test.
        var verified = [CoverSlot]()
        /// Members whose app answers no hit test here (Amendment B).
        var silent = CoverSilentTrack()
        var blocks = [ClosedRange<Double>]()
        var verifiedAt = -Double.infinity

        /// Every slot under a panel, left to right.
        var covered: [CoverSlot] {
            (verified + silent.standing).sorted { ($0.minX, $0.maxX) < ($1.minX, $1.maxX) }
        }
    }

    private struct Background {
        var strip: CGImage
        var key: String
        var underStrip: String
        var transparent: Bool
        var stale = false
    }

    private struct PassInput {
        let generation: Int
        let bars: [CoverBar]
        let coverable: Set<Int32>
        let states: [UInt32: BarState]
        /// The bars granted a capture in this pass, and why (`CoverBackgroundTrust`).
        let grants: [UInt32: CoverBackgroundTrust.Reason]
        let keys: [UInt32: String]
        let force: Bool
        let forcedID: Int?
        let now: Double
        let own: Int32
    }

    private struct BarResult {
        var state: BarState
        var ignoredMilliseconds: Double
        var strips: CoverStrips?
        var underStrip: String
        /// Of the candidates left uncovered: how their hit tests answered (D3 of plan 2026-11-18).
        var silent = 0
        var failed = 0
        var other = 0
    }

    private let reader: CoverBarReading
    private let capturer: CoverCapturing
    private let presenter: CoverPresenting
    private let environment: Environment

    public private(set) var generation = 0
    public private(set) var notice: CoverNotice?
    /// Called on the main thread whenever a bar's blocks or covered slots
    /// change, and when the cover goes off (no reports): the lab's `cover` event.
    public var onReport: (([CoverBarReport], Int) -> Void)?
    /// Called on the main thread when what is covered on a bar differs from the diagnosis last said (D3 of plan 2026-11-18).
    public var onDiagnosis: ((CoverBarDiagnosis) -> Void)?
    /// Called on the main thread for every capture attempted (D2 of plan 2026-11-18).
    public var onCapture: ((CoverCaptureFact) -> Void)?

    private var isActive = false
    private var coverable = Set<Int32>()
    private var states = [UInt32: BarState]()
    private var backgrounds = [UInt32: Background]()
    /// When and why each bar's background is captured again (plan 2026-11-18-cover-stale-and-lost, D1).
    private var trusts = [UInt32: CoverBackgroundTrust]()
    private var budget = CoverCaptureBudget()
    private var passRunning = false
    private var passWanted = false
    private var forceNext = false
    private var forcedCount = 0
    private var pendingForced: Int?
    private var captureRetryScheduled = false
    private var diagnoses = [UInt32: CoverBarDiagnosis]()

    public init(reader: CoverBarReading, capturer: CoverCapturing, presenter: CoverPresenting, environment: Environment) {
        self.reader = reader
        self.capturer = capturer
        self.presenter = presenter
        self.environment = environment
    }

    /// The blocks now covered on a display, display-local.
    public func blocks(displayID: UInt32) -> [ClosedRange<Double>] {
        states[displayID]?.blocks ?? []
    }

    // MARK: - Driving

    /// `active`: Ice rests with the hidden length applied. Going off bumps the
    /// generation first, so no pass under way can put a panel back, then
    /// removes every panel, before this returns (D4).
    public func sync(active: Bool, coverable: Set<Int32>) {
        guard active else {
            guard isActive else { return }
            isActive = false
            generation += 1
            presenter.remove(displayID: nil)
            states = [:]
            diagnoses = [:]
            self.coverable = []
            pendingForced = nil
            onReport?([], generation)
            return
        }
        let wasActive = isActive
        let changed = !isActive || coverable != self.coverable
        isActive = true
        self.coverable = coverable
        guard changed else { return }
        forceNext = true
        if wasActive {
            requestPass()
        } else {
            let started = generation
            environment.after(Self.activationSettle) { [weak self] in
                guard let self, self.isActive, self.generation == started else { return }
                self.requestPass()
            }
        }
    }

    /// Once a second while Ice rests.
    public func tick() {
        if isActive { requestPass() }
    }

    /// The display with the active menu bar changed: the bars are read and
    /// verified again at once; panels not confirmed within `forcedDeadline` go.
    public func activeDisplayChanged() {
        guard isActive else { return }
        forcedCount += 1
        let id = forcedCount
        pendingForced = id
        forceNext = true
        environment.after(Self.forcedDeadline) { [weak self] in
            guard let self, self.pendingForced == id else { return }
            self.pendingForced = nil
            self.failClosed()
        }
        requestPass()
    }

    /// The backgrounds may have changed with no key saying so (wake, unlock,
    /// the screen saver's end, the displays).
    public func invalidateBackgrounds() {
        for id in backgrounds.keys { backgrounds[id]?.stale = true }
        if isActive { requestPass() }
    }

    private func failClosed() {
        presenter.remove(displayID: nil)
        let had = states.values.contains { !$0.blocks.isEmpty }
        for id in states.keys {
            states[id]?.blocks = []
            states[id]?.verified = []
            states[id]?.silent = CoverSilentTrack()
            states[id]?.verifiedAt = -.infinity
        }
        if had { onReport?([], generation) }
    }

    // MARK: - A pass

    private func requestPass() {
        guard isActive else { return }
        guard !passRunning else {
            passWanted = true
            return
        }
        guard environment.canCapture() else {
            notice = .noScreenRecording
            failClosed()
            return
        }
        let bars = environment.bars()
        let now = environment.now()
        var grants = [UInt32: CoverBackgroundTrust.Reason]()
        var keys = [UInt32: String]()
        for bar in bars {
            let key = environment.backgroundKey(bar)
            keys[bar.displayID] = key
            // Only a bar with a block has a use for a background: a capture shows the system's dot (D1).
            guard let state = states[bar.displayID], !state.blocks.isEmpty else { continue }
            guard let reason = captureReason(for: bar, key: key, now: now) else { continue }
            if budget.take(2, now: now) {
                grants[bar.displayID] = reason
            } else {
                scheduleCaptureRetry(after: budget.nextAllowed(now: now) - now)
            }
        }
        let input = PassInput(
            generation: generation, bars: bars, coverable: coverable, states: states, grants: grants, keys: keys,
            force: forceNext, forcedID: pendingForced, now: now, own: environment.ownPID
        )
        forceNext = false
        passRunning = true
        let (reader, capturer, presenter, environment) = (reader, capturer, presenter, environment)
        environment.background {
            let results = Self.run(input, reader: reader, capturer: capturer, clock: environment.now, pause: environment.pause) { ignores, id in
                environment.mainSync { presenter.setIgnoresMouseEvents(ignores, displayID: id) }
            }
            environment.main { [weak self] in
                self?.apply(results, of: input)
            }
        }
    }

    /// Why the bar's background is to be captured now, if it is: the rule's word alone.
    private func captureReason(for bar: CoverBar, key: String, now: Double) -> CoverBackgroundTrust.Reason? {
        let background = usableBackground(for: bar)
        return (trusts[bar.displayID] ?? CoverBackgroundTrust()).reason(
            now: now, hasUsableImage: background != nil, keyEqual: background?.key == key, stale: background?.stale ?? false
        )
    }

    /// The display's last image, if it still has the strip's pixel size.
    private func usableBackground(for bar: CoverBar) -> Background? {
        guard let background = backgrounds[bar.displayID] else { return nil }
        return background.strip.width == Int((Double(bar.frame.width) * bar.scale).rounded()) ? background : nil
    }

    private func scheduleCaptureRetry(after delay: Double) {
        guard !captureRetryScheduled else { return }
        captureRetryScheduled = true
        environment.after(max(0, delay) + 0.05) { [weak self] in
            self?.captureRetryScheduled = false
            self?.requestPass()
        }
    }

    /// Off the main thread: the tree, the hit tests, the captures granted.
    private static func run(
        _ input: PassInput, reader: CoverBarReading, capturer: CoverCapturing, clock: () -> Double, pause: (Double) -> Void,
        setIgnores: (Bool, UInt32) -> Void
    ) -> [UInt32: BarResult] {
        var results = [UInt32: BarResult]()
        for bar in input.bars {
            // A bar whose tree cannot be read has no result.
            guard let slots = reader.slots(of: bar) else { continue }
            let previous = input.states[bar.displayID] ?? BarState()
            let candidates = CoverPlan.candidates(slots: slots, coverable: input.coverable)
            var state = BarState(slots: slots, candidates: candidates, verifiedAt: previous.verifiedAt)
            // Every candidate is tested again when forced, when the candidates changed and every `reverifyEvery`;
            // between those the slots under panels stay on the tree's word and only the others are tested.
            let reverifies = input.force || candidates != previous.candidates || input.now - previous.verifiedAt >= reverifyEvery
            let kept = reverifies ? [] : Set(previous.verified.filter(candidates.contains))
            let standing = reverifies ? [] : Set(candidates.filter { previous.silent.stands($0, among: slots, own: input.own) })
            // A slot under a panel that takes mouse events answers nothing: the panels are opened for the test.
            let toggles = reverifies && !previous.blocks.isEmpty
            let started = clock()
            if toggles {
                setIgnores(true, bar.displayID)
                awaitOpen(previous.verified, on: bar, reader: reader, pause: pause)
            }
            let hits = test(candidates.filter { !kept.contains($0) && !standing.contains($0) }, on: bar, reader: reader)
            var ignored = 0.0
            if toggles {
                setIgnores(false, bar.displayID)
                ignored = (clock() - started) * 1000
            }
            state.verified = candidates.filter { kept.contains($0) || CoverPlan.isVerified(owner: $0.owner, hits: hits[$0] ?? []) }
            if reverifies { state.verifiedAt = input.now }
            state.silent = previous.silent.advanced(
                candidates: candidates, hitVerified: state.verified, slots: slots, hits: hits, own: input.own, now: input.now
            )
            state.blocks = CoverPlan.blocks(verified: state.covered, others: slots, barWidth: Double(bar.frame.width), notch: bar.notch)
            // A read that leaves the bar no block takes no capture, though one was granted: the pass that first
            // reads Mission Control's emptiness would take the dimmed strip (plan 2026-11-18, D6).
            var result = BarResult(
                state: state, ignoredMilliseconds: ignored, strips: Self.captures(input, state, of: bar) ? capturer.strips(of: bar) : nil,
                underStrip: capturer.underStripSignature(of: bar)
            )
            let covered = Set(state.covered)
            for candidate in candidates where !covered.contains(candidate) {
                let answers = hits[candidate] ?? []
                if answers.contains(.failed) {
                    result.failed += 1
                } else if answers.contains(where: { $0.owner != nil }) {
                    result.other += 1
                } else {
                    result.silent += 1
                }
            }
            results[bar.displayID] = result
        }
        return results
    }

    /// Whether a pass asks the capturer for the bar's strips: granted, and its own read left the bar a block.
    private static func captures(_ input: PassInput, _ state: BarState, of bar: CoverBar) -> Bool {
        input.grants[bar.displayID] != nil && !state.blocks.isEmpty
    }

    /// Waits until the panels' new `ignoresMouseEvents` has reached the window
    /// server: a slot that lay under a panel, and whose owner answers, shows
    /// it by answering again (given up after `openPolls`: it may have moved).
    /// Where the panels cover only silent slots nothing can show it, and the
    /// whole of that time is waited.
    private static func awaitOpen(_ answering: [CoverSlot], on bar: CoverBar, reader: CoverBarReading, pause: (Double) -> Void) {
        guard let probe = answering.first else {
            pause(openPoll * Double(openPolls))
            return
        }
        let point = [(probe.minX + probe.maxX) / 2]
        for _ in 0..<openPolls {
            if reader.owners(at: point, of: bar).first == .owner(probe.owner) { return }
            pause(openPoll)
        }
    }

    /// What a hit test answers at each candidate's verification points.
    private static func test(_ candidates: [CoverSlot], on bar: CoverBar, reader: CoverBarReading) -> [CoverSlot: [CoverHit]] {
        guard !candidates.isEmpty else { return [:] }
        let points = candidates.map(CoverPlan.verificationPoints)
        let answers = reader.owners(at: points.flatMap { $0 }, of: bar)
        var hits = [CoverSlot: [CoverHit]]()
        var index = 0
        for (candidate, own) in zip(candidates, points) {
            hits[candidate] = Array(answers[min(index, answers.count)..<min(index + own.count, answers.count)])
            index += own.count
        }
        return hits
    }

    /// Says a bar's diagnosis when what is covered there is not as last said.
    private func diagnose(_ diagnosis: CoverBarDiagnosis) {
        guard diagnoses[diagnosis.displayID]?.coverage != diagnosis.coverage else { return }
        diagnoses[diagnosis.displayID] = diagnosis
        onDiagnosis?(diagnosis)
    }

    /// Takes a capture attempted in this pass into the bar's background and its trust, and says what it was.
    private func take(_ strips: CoverStrips?, reason: CoverBackgroundTrust.Reason, of bar: CoverBar, result: BarResult, input: PassInput) {
        let id = bar.displayID
        let trust = trusts[id] ?? CoverBackgroundTrust()
        /// Stores the trust the capture leaves and says the capture.
        func settle(_ next: CoverBackgroundTrust, equal: Bool? = nil, transparent: Bool = false, failed: Bool = false, ignored: Bool = false) {
            trusts[id] = next
            onCapture?(CoverCaptureFact(
                displayID: id, luma: strips.flatMap { CoverPixels.luma($0.below) }, equal: equal, transparent: transparent, failed: failed,
                reason: reason, step: next.step, unequalRun: next.unequalRun, ignored: ignored
            ))
        }
        guard let strips else {
            settle(trust.captureFailed(at: input.now), failed: true)
            return
        }
        let held = usableBackground(for: bar)
        // Against the strip held before it; one of another size is no comparison.
        let equal = held.map { CoverPixels.isSameBackground($0.strip, strips.below, blocks: result.state.blocks, scale: bar.scale) ?? false }
        let transparent = CoverPixels.isTransparent(
            below: strips.below, onScreen: strips.onScreen, slots: result.state.slots.map { $0.minX...$0.maxX }, scale: bar.scale
        )
        guard trust.believes(transparent: transparent, heldTransparent: held?.transparent == true) else {
            // Nothing is taken from it: the image, its key and the stale flag stay, and the same reason asks again.
            settle(trust.doubted(at: input.now), equal: equal, ignored: true)
            return
        }
        // The newer strip always replaces the held one.
        backgrounds[id] = Background(strip: strips.below, key: input.keys[id] ?? "", underStrip: result.underStrip, transparent: transparent)
        settle(trust.captured(reason: reason, equal: equal ?? false, at: input.now), equal: equal, transparent: transparent)
    }

    private func apply(_ results: [UInt32: BarResult], of input: PassInput) {
        passRunning = false
        var again = passWanted
        passWanted = false
        defer { if again { requestPass() } }
        guard isActive, input.generation == generation else { return }

        var changed = false
        var reports = [CoverBarReport]()
        var opaque: UInt32?
        for bar in input.bars {
            let id = bar.displayID
            // An unreadable bar keeps what it had.
            guard let result = results[id] else {
                diagnose(CoverBarDiagnosis(
                    displayID: id, readable: false, coverable: input.coverable.count, slots: 0, owners: 0, candidates: 0, covered: 0,
                    silent: 0, failed: 0, other: 0, hasNotch: bar.notch != nil
                ))
                continue
            }
            let old = states[id] ?? BarState()
            if old.blocks != result.state.blocks || old.covered != result.state.covered { changed = true }
            states[id] = result.state
            diagnose(CoverBarDiagnosis(
                displayID: id, readable: true, coverable: input.coverable.count, slots: result.state.slots.count,
                owners: Set(result.state.slots.map(\.owner)).count, candidates: result.state.candidates.count,
                covered: Set(result.state.covered).count, silent: result.silent, failed: result.failed, other: result.other,
                hasNotch: bar.notch != nil
            ))

            if let reason = input.grants[id], Self.captures(input, result.state, of: bar) {
                take(result.strips, reason: reason, of: bar, result: result, input: input)
            }
            if result.strips == nil, let background = backgrounds[id], background.underStrip != result.underStrip {
                backgrounds[id]?.stale = true
            }

            if result.state.blocks.isEmpty {
                presenter.remove(displayID: id)
            } else if let background = usableBackground(for: bar) {
                if background.transparent {
                    presenter.show(blocks: result.state.blocks, strip: background.strip, bar: bar)
                } else {
                    presenter.remove(displayID: id)
                    opaque = id
                }
            } else {
                presenter.remove(displayID: id)
                // A capture can be had at once: do not wait for the next tick. Only if the rule wants one now:
                // after a capture that returned nothing it waits, and asking again at once would never end.
                let now = environment.now()
                if budget.nextAllowed(now: now) <= now, captureReason(for: bar, key: input.keys[id] ?? "", now: now) != nil { again = true }
            }
            reports.append(CoverBarReport(
                displayID: id, slots: result.state.slots, covered: result.state.covered, silent: result.state.silent.standing,
                blocks: result.state.blocks, ignoredMilliseconds: result.ignoredMilliseconds
            ))
        }
        for id in states.keys where !input.bars.contains(where: { $0.displayID == id }) {
            presenter.remove(displayID: id)
            states[id] = nil
            backgrounds[id] = nil
            trusts[id] = nil
            diagnoses[id] = nil
            changed = true
        }
        notice = opaque.map { .barNotTransparent(displayID: $0) }
        if input.forcedID != nil, input.forcedID == pendingForced { pendingForced = nil }
        if changed { onReport?(reports, generation) }
    }
}
