import Foundation
import IceCore

/// Whether a baseline covers the hidden section, and if not, why (plan
/// 2026-10-07-icebar-menu-frame-fix, section 10): T7's second attempt failed
/// its baseline with no record of the reason. Reasons and counts only, no
/// item names, so the description can be logged as public.
public enum BaselineCoverage: Equatable, Sendable, CustomStringConvertible {
    case covered
    case skip(CheckSkipReason, targets: Int)
    case noTargets
    case cancelled
    /// The plan skipped or the baseline rejected some members, or fewer were
    /// checkable than named; each reason with its count, sorted by name.
    case incomplete(targets: Int, checkable: Int, planSkipped: [String: Int], rejected: [String: Int])

    public var description: String {
        switch self {
        case .covered: "covered"
        case .skip(let reason, let targets): "skip(\(Self.name(reason))) targets=\(targets)"
        case .noTargets: "noTargets"
        case .cancelled: "cancelled"
        case .incomplete(let targets, let checkable, let planSkipped, let rejected):
            "incomplete targets=\(targets) checkable=\(checkable) planSkipped=\(Self.counts(planSkipped)) rejected=\(Self.counts(rejected))"
        }
    }

    /// An enum case's name without its associated values.
    static func name(_ value: Any) -> String {
        String(String(describing: value).prefix { $0 != "(" })
    }

    static func tally(_ reasons: some Sequence<some Any>) -> [String: Int] {
        reasons.reduce(into: [:]) { counts, reason in counts[name(reason), default: 0] += 1 }
    }

    private static func counts(_ counts: [String: Int]) -> String {
        counts.isEmpty ? "none" : counts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
    }
}

/// What Ice read at one length: each member's check against its shown
/// baseline, and whether `MenuBarAgent` listed a `«` -- recorded beside the
/// checks, never part of them (plan 2026-10-07-icebar-preference-hiding, D-b).
public struct HiddenLengthReading: Equatable, Sendable {
    public let checks: [ItemKey: SectionItemCheck]
    /// `nil` when the agent could not be read.
    public let chevronListed: Bool?
    /// What the matcher read of each reference; `nil` when no observation was read.
    public let diagnostics: ObservationDiagnostics?
    /// How long the session waited for a bar clear of the capture indicator.
    public let waited: Double
    /// From the burst's first capture to this session's last; `nil` without a burst clock.
    public let burstAge: Double?

    public init(
        checks: [ItemKey: SectionItemCheck],
        chevronListed: Bool?,
        diagnostics: ObservationDiagnostics? = nil,
        waited: Double = 0,
        burstAge: Double? = nil
    ) {
        self.checks = checks
        self.chevronListed = chevronListed
        self.diagnostics = diagnostics
        self.waited = waited
        self.burstAge = burstAge
    }

    public static let nothing = HiddenLengthReading(checks: [:], chevronListed: nil)
}

/// IceBar's observation source on macOS 27 (plan 2026-10-03-icebar-build,
/// section 9.3; re-aimed by plan 2026-10-07-icebar-preference-hiding, T3b
/// design): a shown baseline of the roster, then each member's check at every
/// length Ice applies.
public actor HiddenLengthObserver {
    private let verification: HidingVerification
    private let chevron: ChevronReader
    private let settle: Double
    private let sleep: @Sendable (Double) async -> Void
    /// When the capturer behind `verification` captured, and so when a
    /// session may start out of the capture indicator's reach; `nil` leaves
    /// every session to start at once.
    private let burst: CaptureBurstClock?
    private let now: @Sendable () -> Double
    private var prepared: PreparedVerification?
    /// Which `takeBaseline` call may still set `prepared`: the actor is
    /// reentrant across `prepare`, so an older call can resume after a newer
    /// one (Codex review, T3b round 3).
    private var generation = 0

    public init(
        verification: HidingVerification,
        chevron: ChevronReader,
        settle: Double = 1.0,
        sleep: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
        burst: CaptureBurstClock? = nil,
        now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.verification = verification
        self.chevron = chevron
        self.settle = settle
        self.sleep = sleep
        self.burst = burst
        self.now = now
    }

    /// Sleeps until `session` may start in a burst the capture indicator
    /// cannot reach; the seconds slept. The caller checks for cancellation.
    private func waitForBurst(_ session: CaptureSession) async -> Double {
        var waited = 0.0
        // Asked again after every sleep: a capture taken elsewhere meanwhile
        // (the hiding check shares the clock) moves the moment the bar is clear.
        while !Task.isCancelled {
            let start = now()
            guard case .wait(let until)? = burst?.decision(for: session, now: start) else { break }
            await sleep(until - start)
            waited += until - start
        }
        return waited
    }

    /// Takes the baseline with the section shown, and says whether it covers
    /// every member the section map names and if not why. What `prepare`
    /// returned is kept either way (unless cancelled): a length Ice applies
    /// best effort then reports each member's real skip or refusal.
    public func takeBaseline(sectionMap: [TagKey: ItemSection]) async -> BaselineCoverage {
        generation += 1
        let mine = generation
        _ = await waitForBurst(.baseline)
        guard mine == generation else { return .cancelled }
        guard !Task.isCancelled else {
            prepared = nil
            return .cancelled
        }
        let fresh = await verification.prepare(
            sections: [.hidden],
            sectionMap: sectionMap,
            explicitCandidates: nil,
            reusing: nil
        )
        // Whatever the baseline captured, nothing else is read in its burst.
        burst?.closeBurst()
        guard mine == generation else { return .cancelled }
        guard !Task.isCancelled else {
            prepared = nil
            return .cancelled
        }
        prepared = fresh
        return Self.coverage(of: fresh)
    }

    /// Whether the kept baseline can check every one of `keys` (the ready
    /// members): ready, and each one baselined without a rejection.
    public func covers(_ keys: [ItemKey]) -> Bool {
        guard !keys.isEmpty, let prepared, case .ready(let ready) = prepared.state else { return false }
        let checkable = Set(ready.checkableTargets).subtracting(ready.baselineRejections.keys)
        return checkable.isSuperset(of: keys)
    }

    /// Each member's check at the length the bar is at now, after the
    /// settle, and the `«` reading. Nothing without a baseline.
    public func observe() async -> HiddenLengthReading {
        guard let prepared else { return .nothing }
        await sleep(settle)
        guard !Task.isCancelled else { return .nothing }
        let waited = await waitForBurst(.observation)
        guard !Task.isCancelled else { return .nothing }
        let report = await verification.verifyReporting(prepared)
        guard !Task.isCancelled else { return .nothing }
        let listed = await chevron.chevronListed()
        return HiddenLengthReading(
            checks: report.checks,
            chevronListed: listed,
            diagnostics: report.diagnostics,
            waited: waited,
            burstAge: burst?.snapshot.burstAge
        )
    }

    /// A baseline is complete when it is ready, names at least one member,
    /// and the detector can check every one of them.
    static func coverage(of prepared: PreparedVerification) -> BaselineCoverage {
        let ready: PreparedVerification.Ready
        switch prepared.state {
        case .skip(let reason): return .skip(reason, targets: prepared.targets.count)
        case .ready(let value): ready = value
        }
        guard !prepared.targets.isEmpty else { return .noTargets }
        if ready.planSkipped.isEmpty, ready.baselineRejections.isEmpty, Set(ready.checkableTargets) == Set(prepared.targets) {
            return .covered
        }
        return .incomplete(
            targets: prepared.targets.count,
            checkable: ready.checkableTargets.count,
            planSkipped: BaselineCoverage.tally(ready.planSkipped.values),
            rejected: BaselineCoverage.tally(ready.baselineRejections.values)
        )
    }
}
