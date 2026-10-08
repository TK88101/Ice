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

    public init(checks: [ItemKey: SectionItemCheck], chevronListed: Bool?) {
        self.checks = checks
        self.chevronListed = chevronListed
    }

    static let nothing = HiddenLengthReading(checks: [:], chevronListed: nil)
}

/// IceBar's observation source on macOS 27 (plan 2026-10-03-icebar-build,
/// section 9.3; re-aimed by plan 2026-10-07-icebar-preference-hiding, T3b
/// design): a shown baseline of the roster, then each member's check at every
/// length Ice applies.
public actor HiddenLengthObserver {
    private let verification: HidingVerification
    public nonisolated let chevron: ChevronReader
    private let settle: Double
    private let sleep: @Sendable (Double) async -> Void
    private var prepared: PreparedVerification?

    public init(
        verification: HidingVerification,
        chevron: ChevronReader,
        settle: Double = 1.0,
        sleep: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.verification = verification
        self.chevron = chevron
        self.settle = settle
        self.sleep = sleep
    }

    /// Takes the baseline with the section shown, and says whether it covers
    /// every member the section map names and if not why. What `prepare`
    /// returned is kept either way (unless cancelled): a length Ice applies
    /// best effort then reports each member's real skip or refusal.
    public func takeBaseline(sectionMap: [TagKey: ItemSection]) async -> BaselineCoverage {
        let fresh = await verification.prepare(
            sections: [.hidden],
            sectionMap: sectionMap,
            explicitCandidates: nil,
            reusing: nil
        )
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
        let results = await verification.verify(prepared)
        guard !Task.isCancelled else { return .nothing }
        let listed = await chevron.chevronListed()
        return HiddenLengthReading(checks: results, chevronListed: listed)
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
