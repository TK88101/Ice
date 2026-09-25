import IceCore
import MenuBarCapture
import MenuBarDiscovery

/// What `HidingVerification.prepare` produced, handed unchanged to
/// `HidingVerification.verify` (plan section 4.3).
///
/// `targets` is the roster the check reports on, in one of three shapes:
/// empty when there was no set to plan from (cancelled before or during
/// discovery, or no display); every item `sectionMap` places in the
/// requested sections, parked ones included, when there is no geometry or
/// `CheckPlan` skipped the whole section; otherwise `CheckPlan`'s targets
/// plus its per-item skips, whether or not a baseline could be taken.
/// `verify` reports a `SectionItemCheck` for every one of these -- as
/// `.skipped(reason)` when `state` is `.skip`, or as whatever `state.ready`'s
/// own per-key data says otherwise -- so no item on the roster goes without
/// a result.
public struct PreparedVerification: Sendable, Equatable {
    /// Either the section could not be prepared at all (`skip`), or a
    /// baseline exists and `verify` can read it (`ready`).
    public enum State: Sendable, Equatable {
        case skip(CheckSkipReason)
        case ready(Ready)
    }

    /// Everything a baseline needs to be read back by `verify`, and reused by
    /// a later `prepare` (D16).
    public struct Ready: Sendable, Equatable {
        public let baseline: BaselineResult
        public let geometry: BarGeometry
        /// The display origin the baseline's reader was built with --
        /// `verify` reuses it so its own reader reads the same coordinate
        /// space.
        public let origin: DiscoveryOrigin
        /// `CheckPlan`'s own `targets`: the items actually baselined and
        /// reported as `.checked`/`.refusedAtBaseline` (a subset of the
        /// struct's own `targets` -- the rest are in `planSkipped`).
        public let checkableTargets: [ItemKey]
        /// The other listed items whose ink must be explained at baseline
        /// and observation time so it cannot be mistaken for a target's
        /// (D15), with anything the baseline marked dynamic already dropped.
        public let alsoObserved: [ItemKey]
        /// The candidates the baseline actually accepted as templates,
        /// reconciled by `CheckPlan.references`.
        public let references: [ItemKey]
        /// `CheckPlan`'s per-item skips within the section (`.positional`,
        /// `.stacked`) -- reported by `verify` as `.skipped(reason)`.
        public let planSkipped: [ItemKey: CheckSkipReason]
        /// Baseline rejections for `checkableTargets` only -- reported by
        /// `verify` as `.refusedAtBaseline(reason)`.
        public let baselineRejections: [ItemKey: Rejection]
        /// The raw (untrimmed) AX frames the baseline's items had at prepare
        /// time, keyed by `ItemKey` -- what a later `prepare`'s fresh read is
        /// compared against by `BaselineReuse.isReusable`.
        public let baselineFrames: [ItemKey: BarRect]

        public init(
            baseline: BaselineResult,
            geometry: BarGeometry,
            origin: DiscoveryOrigin,
            checkableTargets: [ItemKey],
            alsoObserved: [ItemKey],
            references: [ItemKey],
            planSkipped: [ItemKey: CheckSkipReason],
            baselineRejections: [ItemKey: Rejection],
            baselineFrames: [ItemKey: BarRect]
        ) {
            self.baseline = baseline
            self.geometry = geometry
            self.origin = origin
            self.checkableTargets = checkableTargets
            self.alsoObserved = alsoObserved
            self.references = references
            self.planSkipped = planSkipped
            self.baselineRejections = baselineRejections
            self.baselineFrames = baselineFrames
        }
    }

    public let state: State
    public let targets: [ItemKey]
    /// When the baseline behind `state.ready` was captured (or, for a reused
    /// baseline, when it was *originally* captured -- reuse never resets this,
    /// which is what lets `BaselineReuse.maxAge` bound a baseline's total
    /// lifetime rather than a sliding window since its last reuse).
    public let createdAt: Double

    public init(state: State, targets: [ItemKey], createdAt: Double) {
        self.state = state
        self.targets = targets
        self.createdAt = createdAt
    }
}
