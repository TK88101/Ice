/// D1 (plan 2026-10-03-icebar-build, section 8 T1): on macOS 27 the hidden
/// section is hidden by a control item length inside a band -- below it the
/// pushed items fold into the system's `«`, above it they are drawn again
/// (T0: 632-840 pt for up to eight items). This file only proposes which
/// length to try next and where to rest; Ice applies the lengths, reads the
/// outcomes and keeps the layout signature (T4).

/// What one length did to the bar.
public enum HiddenLengthOutcome: Equatable, Sendable {
    /// A member's check saw the fold go up with it.
    case folded
    /// Every member positively assessed absent, none under the fold.
    case hiddenClean
    /// Some hidden-section item is drawn on the bar.
    case drawn
    /// Anything that could not be assessed: a refusal, an unreadable read, a
    /// missing item.
    case unknown
}

/// One length tried and what it did.
public struct HiddenLengthObservation: Equatable, Sendable {
    public let length: Double
    public let outcome: HiddenLengthOutcome

    public init(length: Double, outcome: HiddenLengthOutcome) {
        self.length = length
        self.outcome = outcome
    }
}

/// The calibration's grid and bounds.
public struct HiddenLengthParameters: Equatable, Sendable {
    public let step: Double
    public let minLength: Double
    public let maxLength: Double
    /// Where a calibration starts without a last good length.
    public let defaultStart: Double
    /// How many distinct lengths may be tried before giving up.
    public let maxObservations: Int

    public init(step: Double, minLength: Double, maxLength: Double, defaultStart: Double, maxObservations: Int) {
        precondition([step, minLength, maxLength, defaultStart].allSatisfy(\.isFinite), "parameters must be finite")
        precondition(step > 0, "step must be positive")
        precondition(minLength <= defaultStart && defaultStart <= maxLength, "defaultStart must lie within the limits")
        precondition(maxObservations > 0, "maxObservations must be positive")
        self.step = step
        self.minLength = minLength
        self.maxLength = maxLength
        self.defaultStart = defaultStart
        self.maxObservations = maxObservations
    }

    /// T0's grid (408-1000 pt by 16) and band midpoint (736 pt), MEASURED in
    /// run `20261004-105226-spike`. The bound is INFERRED: the 14 clean lengths,
    /// the 2 edges, and 8 steps of approach.
    public static let standard = HiddenLengthParameters(
        step: 16,
        minLength: 408,
        maxLength: 1000,
        defaultStart: 736,
        maxObservations: 24
    )
}

/// What to do next.
public enum HiddenLengthProposal: Equatable, Sendable {
    /// Why a calibration ended without a length; the section is then shown.
    public enum Reason: Equatable, Sendable {
        /// An outcome or a length that could not be trusted.
        case unknownOutcome
        /// Folded on one side, drawn on the other, nothing clean between.
        case noBand
        /// The history contradicts itself or leaves the grid.
        case inconsistent
        /// Too many lengths tried.
        case stepBound
    }

    case tryLength(Double)
    case rest(Double)
    case giveUp(Reason)
}

/// Brackets the band one grid step at a time and rests at its midpoint.
///
/// Stateless: every call reads the whole history (the latest observation of a
/// length wins), so the caller keeps no phase. Every doubt gives up, and giving
/// up shows the section -- Ice never rests at a length it has not seen hide
/// every item cleanly.
public enum HiddenLengthCalibrator {
    public static func next(
        observations: [HiddenLengthObservation],
        lastGood: Double?,
        parameters: HiddenLengthParameters
    ) -> HiddenLengthProposal {
        let grid = Grid(lastGood: lastGood, parameters: parameters)
        if observations.contains(where: grid.isUntrusted) { return .giveUp(.unknownOutcome) }
        guard let history = grid.history(of: observations) else { return .giveUp(.inconsistent) }
        let proposal = decide(history: history, grid: grid)
        if case .tryLength = proposal, history.count >= parameters.maxObservations {
            return .giveUp(.stepBound)
        }
        return proposal
    }

    static func decide(history: [Int: HiddenLengthOutcome], grid: Grid) -> HiddenLengthProposal {
        guard !history.isEmpty else { return .tryLength(grid.length(0)) }
        let clean = history.filter { $0.value == .hiddenClean }.keys
        guard let lo = clean.min(), let hi = clean.max() else {
            return approach(history: history, grid: grid)
        }
        let run = lo...hi
        // Contradictions first: a missing point must not mask a non-clean one.
        if run.contains(where: { history[$0] != nil && history[$0] != .hiddenClean }) {
            return .giveUp(.inconsistent)
        }
        if let missing = run.first(where: { history[$0] == nil }) {
            return .tryLength(grid.length(missing))
        }
        if let edge = [lo - 1, hi + 1].first(where: { grid.contains($0) && history[$0] == nil }) {
            return .tryLength(grid.length(edge))
        }
        return .rest((grid.length(lo) + grid.length(hi)) / 2)
    }

    /// No clean length yet: step towards the band from the side seen so far.
    static func approach(history: [Int: HiddenLengthOutcome], grid: Grid) -> HiddenLengthProposal {
        let folded = history.filter { $0.value == .folded }.keys
        let drawn = history.filter { $0.value == .drawn }.keys
        let candidate: Int? = switch (folded.max(), drawn.min()) {
        case (let top?, nil): top + 1
        case (nil, let bottom?): bottom - 1
        default: nil
        }
        guard let candidate, grid.contains(candidate) else { return .giveUp(.noBand) }
        return .tryLength(grid.length(candidate))
    }

    /// Lengths as whole steps from the start, so the walk never drifts.
    struct Grid {
        let start: Double
        let parameters: HiddenLengthParameters

        /// How far a length may sit from a grid point and still be on it.
        static let tolerance = 1e-9

        /// Anchored at the last good length when it is usable, else at the
        /// default start.
        init(lastGood: Double?, parameters: HiddenLengthParameters) {
            if let lastGood, lastGood.isFinite, (parameters.minLength...parameters.maxLength).contains(lastGood) {
                self.start = lastGood
            } else {
                self.start = parameters.defaultStart
            }
            self.parameters = parameters
        }

        func length(_ index: Int) -> Double { start + Double(index) * parameters.step }

        func contains(_ index: Int) -> Bool { inLimits(length(index)) }

        /// One bound policy for what is proposed and what is accepted back, so
        /// a grid point that rounds a hair past a limit is not refused later.
        func inLimits(_ length: Double) -> Bool {
            length >= parameters.minLength - Self.tolerance && length <= parameters.maxLength + Self.tolerance
        }

        /// An unknown outcome, or a length that is not a number or lies
        /// outside the limits.
        func isUntrusted(_ observation: HiddenLengthObservation) -> Bool {
            observation.outcome == .unknown || !observation.length.isFinite || !inLimits(observation.length)
        }

        /// The latest outcome per grid index, or `nil` if any length is off
        /// the grid.
        func history(of observations: [HiddenLengthObservation]) -> [Int: HiddenLengthOutcome]? {
            var indexed = [Int: HiddenLengthOutcome]()
            for observation in observations {
                let steps = (observation.length - start) / parameters.step
                let index = steps.rounded()
                guard abs(steps - index) <= Self.tolerance else { return nil }
                indexed[Int(index)] = observation.outcome
            }
            return indexed
        }
    }
}
