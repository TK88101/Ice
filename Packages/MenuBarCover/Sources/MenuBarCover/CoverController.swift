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

        public init(
            bars: @escaping () -> [CoverBar], backgroundKey: @escaping (CoverBar) -> String, canCapture: @escaping () -> Bool,
            now: @escaping () -> Double, background: @escaping (@escaping () -> Void) -> Void,
            main: @escaping (@escaping () -> Void) -> Void, mainSync: @escaping (() -> Void) -> Void,
            after: @escaping (Double, @escaping () -> Void) -> Void
        ) {
            self.bars = bars
            self.backgroundKey = backgroundKey
            self.canCapture = canCapture
            self.now = now
            self.background = background
            self.main = main
            self.mainSync = mainSync
            self.after = after
        }
    }

    /// Verified slots are hit-tested again this often (their panels ignore
    /// mouse events meanwhile); candidates that failed are tried every pass.
    public static let reverifyEvery = 10.0
    /// A background is taken again after this long whatever the signals say.
    public static let refreshEvery = 1800.0
    /// After a change of the active display the panels stay this long without
    /// a fresh verification, then go (D5).
    public static let forcedDeadline = 0.5

    private struct BarState {
        var slots = [CoverSlot]()
        var candidates = [CoverSlot]()
        var verified = [CoverSlot]()
        var blocks = [ClosedRange<Double>]()
        var verifiedAt = -Double.infinity
    }

    private struct Background {
        var strip: CGImage
        var key: String
        var underStrip: String
        var capturedAt: Double
        var transparent: Bool
        var stale = false
    }

    private struct PassInput {
        let generation: Int
        let bars: [CoverBar]
        let coverable: Set<Int32>
        let states: [UInt32: BarState]
        let grants: Set<UInt32>
        let keys: [UInt32: String]
        let force: Bool
        let forcedID: Int?
        let now: Double
    }

    private struct BarResult {
        var state: BarState
        var ignoredMilliseconds: Double
        var strips: CoverStrips?
        var underStrip: String
    }

    private let reader: CoverBarReading
    private let capturer: CoverCapturing
    private let presenter: CoverPresenting
    private let environment: Environment

    public private(set) var generation = 0
    public private(set) var notice: CoverNotice?
    /// Called on the main thread whenever a bar's blocks or verified slots
    /// change, and when the cover goes off (no reports): the lab's `cover` event.
    public var onReport: (([CoverBarReport], Int) -> Void)?

    private var isActive = false
    private var coverable = Set<Int32>()
    private var states = [UInt32: BarState]()
    private var backgrounds = [UInt32: Background]()
    private var budget = CoverCaptureBudget()
    private var passRunning = false
    private var passWanted = false
    private var forceNext = false
    private var forcedCount = 0
    private var pendingForced: Int?
    private var captureRetryScheduled = false

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
            self.coverable = []
            pendingForced = nil
            onReport?([], generation)
            return
        }
        let changed = !isActive || coverable != self.coverable
        isActive = true
        self.coverable = coverable
        if changed {
            forceNext = true
            requestPass()
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
        var grants = Set<UInt32>()
        var keys = [UInt32: String]()
        for bar in bars {
            let key = environment.backgroundKey(bar)
            keys[bar.displayID] = key
            guard let state = states[bar.displayID], !state.candidates.isEmpty else { continue }
            guard needsCapture(bar, key: key, now: now) else { continue }
            if budget.take(2, now: now) {
                grants.insert(bar.displayID)
            } else {
                scheduleCaptureRetry(after: budget.nextAllowed(now: now) - now)
            }
        }
        let input = PassInput(
            generation: generation, bars: bars, coverable: coverable, states: states, grants: grants, keys: keys,
            force: forceNext, forcedID: pendingForced, now: now
        )
        forceNext = false
        passRunning = true
        let (reader, capturer, presenter, environment) = (reader, capturer, presenter, environment)
        environment.background {
            let results = Self.run(input, reader: reader, capturer: capturer, clock: environment.now) { ignores, id in
                environment.mainSync { presenter.setIgnoresMouseEvents(ignores, displayID: id) }
            }
            environment.main { [weak self] in
                self?.apply(results, of: input)
            }
        }
    }

    private func needsCapture(_ bar: CoverBar, key: String, now: Double) -> Bool {
        guard let background = usableBackground(for: bar) else { return true }
        return background.key != key || background.stale || now - background.capturedAt >= Self.refreshEvery
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
        _ input: PassInput, reader: CoverBarReading, capturer: CoverCapturing, clock: () -> Double,
        setIgnores: (Bool, UInt32) -> Void
    ) -> [UInt32: BarResult] {
        var results = [UInt32: BarResult]()
        for bar in input.bars {
            guard let slots = reader.slots(of: bar) else { continue }
            let previous = input.states[bar.displayID] ?? BarState()
            let candidates = CoverPlan.candidates(slots: slots, coverable: input.coverable)
            var state = BarState(slots: slots, candidates: candidates, verifiedAt: previous.verifiedAt)
            var ignored = 0.0
            if input.force || candidates != previous.candidates || input.now - previous.verifiedAt >= reverifyEvery {
                // The verified slots lie under panels that take mouse events,
                // which a hit test would hit instead.
                let toggles = !previous.blocks.isEmpty
                let started = clock()
                if toggles { setIgnores(true, bar.displayID) }
                state.verified = verify(candidates, on: bar, reader: reader)
                if toggles {
                    setIgnores(false, bar.displayID)
                    ignored = (clock() - started) * 1000
                }
                state.verifiedAt = input.now
            } else {
                // No panel lies over a candidate that failed: no toggle.
                let kept = previous.verified.filter(candidates.contains)
                state.verified = kept + verify(candidates.filter { !kept.contains($0) }, on: bar, reader: reader)
            }
            let verified = Set(state.verified)
            state.blocks = CoverPlan.blocks(
                verified: state.verified, others: slots.filter { !verified.contains($0) },
                barWidth: Double(bar.frame.width), notch: bar.notch
            )
            results[bar.displayID] = BarResult(
                state: state, ignoredMilliseconds: ignored,
                strips: input.grants.contains(bar.displayID) ? capturer.strips(of: bar) : nil,
                underStrip: capturer.underStripSignature(of: bar)
            )
        }
        return results
    }

    private static func verify(_ candidates: [CoverSlot], on bar: CoverBar, reader: CoverBarReading) -> [CoverSlot] {
        guard !candidates.isEmpty else { return [] }
        let points = candidates.map(CoverPlan.verificationPoints)
        let hits = reader.owners(at: points.flatMap { $0 }, of: bar)
        var verified = [CoverSlot]()
        var index = 0
        for (candidate, own) in zip(candidates, points) {
            let slice = Array(hits[index..<min(hits.count, index + own.count)])
            index += own.count
            if CoverPlan.isVerified(owner: candidate.owner, hits: slice) { verified.append(candidate) }
        }
        return verified
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
            guard let result = results[id] else { continue }
            let old = states[id] ?? BarState()
            if old.blocks != result.state.blocks || old.verified != result.state.verified { changed = true }
            states[id] = result.state

            if let strips = result.strips {
                backgrounds[id] = Background(
                    strip: strips.below, key: input.keys[id] ?? "", underStrip: result.underStrip, capturedAt: input.now,
                    transparent: CoverPixels.isTransparent(
                        below: strips.below, onScreen: strips.onScreen, slots: result.state.slots.map { $0.minX...$0.maxX }, scale: bar.scale
                    )
                )
            } else if let background = backgrounds[id], background.underStrip != result.underStrip {
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
                // A capture can be had at once: do not wait for the next tick.
                if budget.nextAllowed(now: environment.now()) <= environment.now() { again = true }
            }
            reports.append(CoverBarReport(
                displayID: id, slots: result.state.slots, verified: result.state.verified, blocks: result.state.blocks,
                ignoredMilliseconds: result.ignoredMilliseconds
            ))
        }
        for id in states.keys where !input.bars.contains(where: { $0.displayID == id }) {
            presenter.remove(displayID: id)
            states[id] = nil
            backgrounds[id] = nil
            changed = true
        }
        notice = opaque.map { .barNotTransparent(displayID: $0) }
        if input.forcedID != nil, input.forcedID == pendingForced { pendingForced = nil }
        if changed { onReport?(reports, generation) }
    }
}
