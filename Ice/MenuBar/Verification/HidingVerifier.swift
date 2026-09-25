//
//  HidingVerifier.swift
//  Ice
//

import Combine
import Foundation
import IceCore
import MenuBarDetectorFeed
import MenuBarDiscovery
import OSLog

/// What the layout pane shows about the last check (plan D7).
struct HidingCheckStatus: Equatable {
    /// One line: "Hiding did not take effect for N item(s)" when anything is still drawn; otherwise "Hidden: N" when
    /// something was seen hidden, followed by "Not checked: <reason names>" for what could not be checked; "Not checked:
    /// <reason names>" alone when nothing was observed; "No items to check" when the section was empty.
    let message: String

    init(summary: VerificationSummary) {
        let reasons = Set(summary.skipped.keys)
            .union(summary.refused.keys)
            .union(summary.unverifiable.keys)
            .sorted()
        let notChecked = reasons.isEmpty ? nil : "Not checked: \(reasons.joined(separator: ", "))"
        if summary.stillDrawn > 0 {
            self.message = "Hiding did not take effect for \(summary.stillDrawn) item(s)"
        } else if summary.hidden > 0 {
            self.message = ["Hidden: \(summary.hidden)", notChecked].compactMap { $0 }.joined(separator: "; ")
        } else {
            self.message = notChecked ?? "No items to check"
        }
    }
}

/// Checks, read-only, whether hiding a section on macOS 27 stopped its items being drawn (plan D7, D14-D19). Built only from
/// publishers and closures; it never acts on the menu bar.
@MainActor
final class HidingVerifier {
    private let sectionMap: @MainActor () -> [TagKey: ItemSection]
    private let verification: @MainActor () -> HidingVerification?
    private let settle: Duration
    private let report: @MainActor (HidingCheckStatus) -> Void

    private let logger = Logger(category: "HidingVerifier")

    private var cancellable: AnyCancellable?
    private var previousInputs: VerificationInputs?

    private var lastPrepared: PreparedVerification?
    private var lastPreparedSections: Set<ItemSection>?

    /// One unit of work, from `VerificationTrigger.reduce`.
    private struct Job {
        enum Kind {
            case prepare
            case verify
        }

        let id: Int
        let kind: Kind
        let sections: Set<ItemSection>
    }

    /// Jobs run one at a time, in order (D16); a newer job whose sections
    /// overlap a queued or running one replaces it, and a job for other
    /// sections waits its turn instead.
    private var queue = [Job]()
    private var current: (job: Job, task: Task<Void, Never>)?
    private var nextJobID = 0

    init(
        inputs: AnyPublisher<VerificationInputs, Never>,
        sectionMap: @escaping @MainActor () -> [TagKey: ItemSection],
        verification: @escaping @MainActor () -> HidingVerification?,
        settle: Duration = .seconds(1),
        report: @escaping @MainActor (HidingCheckStatus) -> Void
    ) {
        self.sectionMap = sectionMap
        self.verification = verification
        self.settle = settle
        self.report = report

        cancellable = inputs
            .removeDuplicates()
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] current in
                self?.handle(current)
            }
    }

    // MARK: - The reducer's output

    private func handle(_ current: VerificationInputs) {
        let jobs = VerificationTrigger.reduce(previous: previousInputs, current: current)
        previousInputs = current

        for job in jobs {
            switch job {
            case .prepare(let sections):
                enqueue(.prepare, sections: sections)
            case .verify(let sections):
                enqueue(.verify, sections: sections)
            case .skip(let sections, let reason):
                cancelOverlapping(with: sections)
                report(HidingCheckStatus(summary: skippedSummary(sections, reason)))
            }
        }
    }

    // MARK: - The queue

    private func enqueue(_ kind: Job.Kind, sections: Set<ItemSection>) {
        cancelOverlapping(with: sections)
        nextJobID += 1
        queue.append(Job(id: nextJobID, kind: kind, sections: sections))
        startNextIfIdle()
    }

    private func startNextIfIdle() {
        guard current == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        let task = Task { [weak self, settle] in
            try? await Task.sleep(for: settle)
            if !Task.isCancelled {
                switch job.kind {
                case .prepare: await self?.runPrepare(sections: job.sections)
                case .verify: await self?.runVerify(sections: job.sections)
                }
            }
            self?.finished(job)
        }
        current = (job, task)
    }

    private func finished(_ job: Job) {
        guard current?.job.id == job.id else { return }
        current = nil
        startNextIfIdle()
    }

    // MARK: - prepare

    private func runPrepare(sections: Set<ItemSection>) async {
        guard let verifier = verification() else { return }

        let prepared = await verifier.prepare(
            sections: sections,
            sectionMap: sectionMap(),
            explicitCandidates: nil,
            reusing: lastPrepared
        )

        guard !Task.isCancelled else { return }

        lastPrepared = prepared
        lastPreparedSections = sections

        if case .skip(let reason) = prepared.state {
            // A skip decided before any roster existed (no display, say) still
            // names its reason instead of reading "No items to check".
            let summary = prepared.targets.isEmpty
                ? skippedSummary(sections, reason)
                : VerificationSummary.make(Dictionary(uniqueKeysWithValues: prepared.targets.map { ($0, SectionItemCheck.skipped(reason)) }))
            report(HidingCheckStatus(summary: summary))
        }
    }

    // MARK: - verify

    private func runVerify(sections: Set<ItemSection>) async {
        guard
            let prepared = lastPrepared,
            let preparedSections = lastPreparedSections,
            sections.isSubset(of: preparedSections)
        else {
            guard !Task.isCancelled else { return }
            // The summary shows reason names only, so the seconds are not kept.
            report(HidingCheckStatus(summary: skippedSummary(sections, .noBaseline(shownSeconds: 0))))
            return
        }

        guard let verifier = verification() else { return }
        let results = await verifier.verify(prepared)

        guard !Task.isCancelled else { return }

        let map = sectionMap()
        let filtered = results.filter { key, _ in
            guard let section = map[key.tagKey(isSelf: false)] else { return false }
            return sections.contains(section)
        }

        report(HidingCheckStatus(summary: VerificationSummary.make(filtered)))

        for (key, check) in filtered {
            logger.info("Hiding check for \(key.encoded, privacy: .private): \(String(describing: check), privacy: .public)")
        }
    }

    // MARK: - Helpers

    private func cancelOverlapping(with sections: Set<ItemSection>) {
        queue.removeAll { !$0.sections.isDisjoint(with: sections) }
        if let current, !current.job.sections.isDisjoint(with: sections) {
            current.task.cancel()
        }
    }

    /// Builds a `VerificationSummary` naming every section in `sections` as skipped with `reason`, using placeholder keys --
    /// `VerificationSummary` only ever shows a reason's case name (never its associated value), so a real `ItemKey` roster
    /// is not needed here.
    private func skippedSummary(_ sections: Set<ItemSection>, _ reason: CheckSkipReason) -> VerificationSummary {
        var results = [ItemKey: SectionItemCheck]()
        for (index, _) in sections.enumerated() {
            let placeholder = ItemKey(namespace: "", identifier: "", pid: Int32(index), childIndex: nil)
            results[placeholder] = .skipped(reason)
        }
        return VerificationSummary.make(results)
    }
}
