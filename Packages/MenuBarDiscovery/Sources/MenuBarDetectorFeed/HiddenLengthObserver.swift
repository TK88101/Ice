import Foundation
import IceCore

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

    /// Takes the baseline with the section shown; `true` only when every
    /// member can be checked. The members are the hidden section's items
    /// alone: always-hidden items are pushed along but are not members.
    public func takeBaseline(sectionMap: [TagKey: ItemSection]) async -> Bool {
        let fresh = await verification.prepare(
            sections: [.hidden],
            sectionMap: sectionMap,
            explicitCandidates: nil,
            reusing: nil
        )
        let covered = Self.covers(fresh) && !Task.isCancelled
        prepared = covered ? fresh : nil
        return covered
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
    static func covers(_ prepared: PreparedVerification) -> Bool {
        guard case .ready(let ready) = prepared.state, !prepared.targets.isEmpty else { return false }
        return ready.planSkipped.isEmpty
            && ready.baselineRejections.isEmpty
            && Set(ready.checkableTargets) == Set(prepared.targets)
    }
}
