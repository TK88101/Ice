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

/// D1's observation source on macOS 27 (plan 2026-10-03-icebar-build, section
/// 9.3): a shown baseline of every hidden-section member, then, at each
/// length Ice tries, whether the members are gone and no `«` is up.
public actor HiddenLengthObserver {
    private let verification: HidingVerification
    /// Also read on its own, at rest, by IceBar's hiding.
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

    /// Takes the baseline with the section shown; `.covered` only when every
    /// member can be checked, and otherwise why not. The members are the
    /// hidden section's items alone: always-hidden items are pushed along but
    /// are not members.
    public func takeBaseline(sectionMap: [TagKey: ItemSection]) async -> BaselineCoverage {
        let fresh = await verification.prepare(
            sections: [.hidden],
            sectionMap: sectionMap,
            explicitCandidates: nil,
            reusing: nil
        )
        let coverage = Task.isCancelled ? .cancelled : Self.coverage(of: fresh)
        prepared = coverage == .covered ? fresh : nil
        return coverage
    }

    /// The outcome of the length the bar is at now, after the settle.
    public func observe() async -> HiddenLengthOutcome {
        guard let prepared else { return .unknown }
        await sleep(settle)
        guard !Task.isCancelled else { return .unknown }
        let results = await verification.verify(prepared)
        guard !Task.isCancelled else { return .unknown }
        let listed = await chevron.chevronListed()
        return HiddenLengthOutcomeRule.outcome(
            chevronListed: listed,
            checks: prepared.targets.compactMap { results[$0] },
            memberCount: prepared.targets.count
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
