// T0: one bracket (capture, AX read, capture) read by the oracle into a
// `StepObservation`, and whether it passes as a member control.
import Foundation
import IceBarOracle
import IceBarRunCore
import IceCore
import MenuBarCapture
import SpikeCore

struct BracketRead {
    let observation: StepObservation
    /// Every member and visible helper drawn (full) where AX puts them, no ambiguity.
    let controlPassed: Bool
}

extension SpikeStage {
    func bracket(_ name: String, notBefore: Double) -> BracketRead? {
        clock.sleep(until: notBefore)
        let clock = self.clock
        let sampler = Sampler(capturer: environment.capturer, axReader: environment.axReader, now: { clock.now() })
        guard let sample = sampler.sample(items: pids) else {
            evidence.record("bracket.failed", ["label": name])
            return nil
        }
        sequence += 1
        evidence.keep(sample.before, label: "\(sequence)-\(name)-a")
        evidence.keep(sample.after, label: "\(sequence)-\(name)-b")
        let frames = OnBar.frames(sample.agentFrames, heightPt: barHeight)
        let leftmost = visible.compactMap { sample.itemFrames[$0]?.minX }.min()
        let context = OracleContext(notch: environment.geometry.notch, agentFrames: Set(frames.map(\.span)).sorted { $0.lo < $1.lo },
                                    leftmostReferenceOriginPt: leftmost)
        let helperTemplates = roster.compactMap { templates.helpers[$0.id] }
        // Both captures through the oracle at once (each label is pure), as `Probe.judge` does.
        let captures = [sample.before, sample.after]
        var labels = [CaptureLabels?](repeating: nil, count: captures.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: captures.count) { i in
            let result = label(captures[i], helperTemplates, context)
            lock.withLock { labels[i] = result }
        }
        let labelled = labels.compactMap { $0 }
        let visibleHelpers = visible.map { VisibleHelper(id: $0, axMinX: sample.itemFrames[$0]?.minX ?? .infinity) }
        let members = self.members
        // A member identified (drawn, full) or sighted unexplained (a partial
        // match at the notch's edge): seen, fail closed.
        let seen = labelled.flatMap { capture in
            members.filter { id in
                if case .drawn = capture.labels[id] { return true }
                return capture.sightings.contains { $0.templateID == id && !$0.explained }
            }
        }
        let observation = StepObservation(
            axChevron: ChevronRule.fromAX(reads: [sample.agentFrames], barHeightPt: barHeight),
            pixelChevron: labelled.map(\.chevron),
            membersSeen: Array(Set(seen)).sorted(),
            visibleMissing: Array(Set(labelled.flatMap { Controls.positiveMisses($0, visible: visibleHelpers) })).sorted(),
            ambiguous: labelled.contains { !$0.inconclusive.isEmpty }
        )
        let controlPassed = observation.visibleMissing.isEmpty && !observation.ambiguous
            && labelled.allSatisfy { Controls.memberMisses($0, members: members).isEmpty }
        evidence.record("bracket", [
            "label": name, "axChevron": observation.axChevron, "pixelChevron": observation.pixelChevron.map { $0.rawValue },
            "membersSeen": observation.membersSeen, "visibleMissing": observation.visibleMissing, "ambiguous": observation.ambiguous,
            "controlPassed": controlPassed, "labels": labelled.map { $0.labels.mapValues { "\($0)" } },
            "agentFrames": sample.agentFrames.map { [$0.minX, $0.minY, $0.width] },
            "itemFrames": sample.itemFrames.mapValues { [$0.minX, $0.width] },
        ])
        return BracketRead(observation: observation, controlPassed: controlPassed)
    }

    private func label(_ image: StripImage, _ helpers: [OracleTemplate], _ context: OracleContext) -> CaptureLabels {
        do {
            return try Oracle.label(image: image, helpers: helpers, chevron: templates.chevron, context: context)
        } catch {
            return CaptureLabels(labels: [:], matches: [:], sightings: [], inconclusive: [], chevron: .notEvaluable)
        }
    }
}
