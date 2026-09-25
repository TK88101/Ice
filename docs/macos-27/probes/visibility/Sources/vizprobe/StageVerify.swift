// `vizprobe verify` -- the 2026-09-23 plan's section 6 steps 1, 2, 3, 5,
// 6 and 11: the 2026-09-19 protocol read through discovery, then Ice's
// verification composition (`HidingVerification`) on helpers.
import AppKit
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

extension StageRun {
    func verifySteps() -> [(name: String, body: () -> StepResult)] {
        [
            ("step0.bundles", step0Bundles),
            ("step1.preflight", step1Preflight),
            ("step2.launch", step2LaunchReferenceAndTarget),
            ("step3.fiveCycles", step3FiveCycles),
            ("step5.wiring", step5Wiring),
            ("step6.twoItems", step6TwoItems),
        ]
    }

    /// Step 3: the 2026-09-19 protocol's 6.1 steps 4-6 without control (c),
    /// with the discovered keys as ids and `DiscoveredFrameReader` as the
    /// reader. Verdicts as then.
    func step3FiveCycles() -> StepResult {
        guard let target, let reference, let targetKey, let referenceKey else { return .abort("helpers not launched") }
        guard let pass = discover() else { return .abort("step 3: discovery failed") }
        let origin = pass.origin

        let legacy = LiveRun(apps: apps)
        legacy.geometry = geometry
        legacy.evidence = evidence
        legacy.monitor = monitor
        legacy.preflightBaseline = preflightBaseline
        legacy.sampler = Sampler(capturer: capturer, axReader: feedReader(origin: origin))
        legacy.observer = VisibilityObserver(sampler: legacy.sampler, parameters: parameters)
        legacy.target = target
        legacy.reference = reference
        legacy.targetID = targetKey.encoded
        legacy.referenceID = referenceKey.encoded
        legacy.includeControlC = false
        legacy.alsoObservedIDs = neighboursLeft(of: [targetKey, referenceKey], in: pass.set)
        evidence.record("step3.neighbours", ["count": legacy.alsoObservedIDs.count])

        warmUp()
        if case .abort(let reason) = barCheck("step3.start") { return .abort(reason) }
        for (name, body) in [("6.1-4 baseline", legacy.step4Baseline), ("6.1-5 cycles", legacy.step5Cycles), ("6.1-6 controls a, b", legacy.step6Controls)] {
            if case .abort(let reason) = body() {
                return .abort("step 3 (\(name)): \(reason)")
            }
        }
        summary["step3"] = "five cycles and controls (a), (b) as on 2026-09-19"
        return barCheck("step3.end")
    }

    /// Step 5 (composition only): the target as the section, the reference
    /// the only candidate, the stand-in divider at the target's `maxX`, the
    /// helper's own `isVisible` as the "hide". prepare -> hide -> verify ->
    /// hidden(folded: false); show -> reuse -> verify -> stillDrawn. A reuse
    /// that does not happen (the target came back elsewhere) is recorded,
    /// not a stop (plan Deviation 7).
    func step5Wiring() -> StepResult {
        guard let target, let reference, let targetKey, let referenceKey else { return .abort("helpers not launched") }
        guard let found = discoverItems(of: target.pid, count: 1) else { return .abort("step 5: the target was not discovered") }
        let sectionMap = [found.items[0].tagKey: ItemSection.hidden]
        let ids: [String: pid_t] = [targetKey.encoded: target.pid, referenceKey.encoded: reference.pid]
        let verification = makeVerification(sectionKeys: [targetKey])

        let first = Pump.blocking { await verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [referenceKey], reusing: nil) }
        evidence.record("step5.prepare", describe(first))
        guard case .ready = first.state else {
            switch explain(first, ids: ids, referenceID: referenceKey.encoded, origin: found.result.origin, step: "step5") {
            case .recorded(let why), .skipped(let why):
                summary["step5"] = "not run: \(why)"
                return safetyCheck("step5")
            case .unexpected(let why):
                return .abort(why)
            }
        }

        target.hide()
        Pump.run(1.0)
        let hiddenResults = Pump.blocking { await verification.verify(first) }
        let hidden = hiddenResults[targetKey]
        evidence.record("step5.verifyHidden", ["result": hidden.map { "\($0)" } ?? "none"])

        target.show()
        Pump.run(1.0)
        if case .abort(let reason) = barCheck("step5.shown") { return .abort(reason) }
        let second = Pump.blocking { await verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [referenceKey], reusing: first) }
        let reused = second.createdAt == first.createdAt
        evidence.record("step5.prepareAgain", describe(second).merging(["reused": reused]) { $1 })
        guard case .ready = second.state else {
            switch explain(second, ids: ids, referenceID: referenceKey.encoded, origin: found.result.origin, step: "step5.again") {
            case .recorded(let why), .skipped(let why):
                summary["step5"] = ["hidden": hidden.map { "\($0)" } ?? "none", "shown": "not run: \(why)"]
                guard classify(hidden, expected: .hidden(folded: false)) != .unexpected else {
                    return .abort("step 5: hidden=\(String(describing: hidden))")
                }
                return safetyCheck("step5")
            case .unexpected(let why):
                return .abort(why)
            }
        }
        let drawnResults = Pump.blocking { await verification.verify(second) }
        let drawn = drawnResults[targetKey]
        evidence.record("step5.verifyShown", ["result": drawn.map { "\($0)" } ?? "none"])

        summary["step5"] = [
            "hidden": hidden.map { "\($0)" } ?? "none",
            "shown": drawn.map { "\($0)" } ?? "none",
            "reused": reused ? "yes" : "no (recorded: the target came back at another frame or roster)",
        ]
        let outcomes = [classify(hidden, expected: .hidden(folded: false)), classify(drawn, expected: .stillDrawn)]
        guard !outcomes.contains(.unexpected) else {
            return .abort("step 5: hidden=\(String(describing: hidden)) shown=\(String(describing: drawn))")
        }
        return safetyCheck("step5")
    }

    /// Step 6: the target quits; one helper under its id with two
    /// `.declared` items. (a) the non-first child observed drawn at its own
    /// x; (b) both as one section: quit -> both hidden(folded: false), and,
    /// relaunched, no quit -> both stillDrawn.
    func step6TwoItems() -> StepResult {
        guard let target, let reference, let referenceKey else { return .abort("helpers not launched") }
        let targetPID = target.pid
        quit(target)
        self.target = nil
        guard kill(targetPID, 0) != 0, discoverItems(of: targetPID, count: 0) != nil else { return .abort("step 6: the quit target is still running or listed") }

        let arguments = ["--items", "2", "--identifiers", "vz-a,vz-b", "--glyphs", "target,alt"]
        switch room(forItems: 2, step: "step6") {
        case .ok: break
        case .skip:
            summary["step6"] = "skipped (room)"
            return .ok
        case .abort(let reason): return .abort(reason)
        }
        guard let pair = launchPair(arguments: arguments) else { return .abort("step 6: two .declared items vz-a, vz-b were not discovered") }
        if case .abort(let reason) = barCheck("step6.launched") {
            quit(pair.helper)
            return .abort(reason)
        }

        if case .abort(let reason) = step6a(pair: pair, reference: reference, referenceKey: referenceKey) {
            quit(pair.helper)
            return .abort(reason)
        }

        // (b), first half: prepare, quit the helper (both gone), verify --
        // classified before anything else happens.
        let keys = pair.items.map(\.key)
        var ids = [referenceKey.encoded: reference.pid]
        for key in keys { ids[key.encoded] = pair.helper.pid }
        let verification = makeVerification(sectionKeys: keys)
        let sectionMap = Dictionary(uniqueKeysWithValues: pair.items.map { ($0.tagKey, ItemSection.hidden) })
        let prepared = Pump.blocking { await verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [referenceKey], reusing: nil) }
        evidence.record("step6b.prepare", describe(prepared))
        guard case .ready = prepared.state else {
            let failure = explain(prepared, ids: ids, referenceID: referenceKey.encoded, origin: pair.origin, step: "step6b")
            quit(pair.helper)
            switch failure {
            case .recorded(let why), .skipped(let why):
                summary["step6b"] = "not run: \(why)"
                return safetyCheck("step6b")
            case .unexpected(let why):
                return .abort(why)
            }
        }
        quit(pair.helper)
        Pump.run(1.0)
        let goneResults = Pump.blocking { await verification.verify(prepared) }
        let gone = keys.map { goneResults[$0] }
        let goneText = gone.map { $0.map { "\($0)" } ?? "none" }
        evidence.record("step6b.verifyGone", ["results": goneText])
        summary["step6b"] = ["gone": goneText]
        guard !gone.map({ classify($0, expected: .hidden(folded: false)) }).contains(.unexpected) else {
            return .abort("step 6(b): gone=\(gone)")
        }
        if case .abort(let reason) = safetyCheck("step6b.gone") { return .abort(reason) }

        // (b), second half: relaunched (same identifiers, new pid and keys),
        // prepared afresh, not quit, verified.
        switch room(forItems: 2, step: "step6b.relaunch") {
        case .ok: break
        case .skip:
            summary["step6b"] = ["gone": goneText, "stayed": "skipped (room)"]
            return .ok
        case .abort(let reason): return .abort(reason)
        }
        guard let again = launchPair(arguments: arguments) else { return .abort("step 6(b): the relaunched pair was not discovered") }
        defer { quit(again.helper) }
        if case .abort(let reason) = barCheck("step6b.relaunched") { return .abort(reason) }
        let againKeys = again.items.map(\.key)
        var againIDs = [referenceKey.encoded: reference.pid]
        for key in againKeys { againIDs[key.encoded] = again.helper.pid }
        let againVerification = makeVerification(sectionKeys: againKeys)
        let againMap = Dictionary(uniqueKeysWithValues: again.items.map { ($0.tagKey, ItemSection.hidden) })
        let preparedAgain = Pump.blocking { await againVerification.prepare(sections: [.hidden], sectionMap: againMap, explicitCandidates: [referenceKey], reusing: nil) }
        evidence.record("step6b.prepareAgain", describe(preparedAgain))
        guard case .ready = preparedAgain.state else {
            switch explain(preparedAgain, ids: againIDs, referenceID: referenceKey.encoded, origin: again.origin, step: "step6b.again") {
            case .recorded(let why), .skipped(let why):
                summary["step6b"] = ["gone": goneText, "stayed": "not run: \(why)"]
                return safetyCheck("step6b.again")
            case .unexpected(let why):
                return .abort(why)
            }
        }
        let stayedResults = Pump.blocking { await againVerification.verify(preparedAgain) }
        let stayed = againKeys.map { stayedResults[$0] }
        let stayedText = stayed.map { $0.map { "\($0)" } ?? "none" }
        evidence.record("step6b.verifyStayed", ["results": stayedText])
        summary["step6b"] = ["gone": goneText, "stayed": stayedText]
        guard !stayed.map({ classify($0, expected: .stillDrawn) }).contains(.unexpected) else {
            return .abort("step 6(b): stayed=\(stayed)")
        }
        return safetyCheck("step6b")
    }

    /// Launches the two-item helper under the target's id and discovers its
    /// two `.declared` items; `childOrder` is their AX child order.
    private func launchPair(arguments: [String]) -> (helper: HelperControl, items: [DiscoveredItem], childOrder: [String], origin: DiscoveryOrigin)? {
        guard let helper = launch(label: "pair", app: apps.target, bundleID: HelperRole.target, arguments: arguments) else { return nil }
        guard let found = discoverItems(of: helper.pid, count: 2),
              found.items.allSatisfy({ $0.basis == .declared }),
              Set(found.items.map(\.key.identifier)) == ["vz-a", "vz-b"]
        else {
            quit(helper)
            return nil
        }
        let childOrder = RawAX.read(pid: helper.pid).children.compactMap(\.identifier)
        return (helper, found.items, childOrder, found.result.origin)
    }

    /// Step 6(a). Pre-registered skips: the two frames still overlap after
    /// trimming, or the old first-extra reader's frame equals the non-first
    /// child's (then the old reader could not have missed it).
    private func step6a(pair: (helper: HelperControl, items: [DiscoveredItem], childOrder: [String], origin: DiscoveryOrigin), reference: HelperControl, referenceKey: ItemKey) -> StepResult {
        guard pair.childOrder.count == 2,
              let nonFirst = pair.items.first(where: { $0.key.identifier == pair.childOrder[1] }),
              let nonFirstFrame = nonFirst.frame
        else { return .abort("step 6(a): the AX child order of the pair could not be read") }

        let trimmed = pair.items.compactMap(\.frame).map { CheckFrames.trim($0) }
        let stillOverlap = trimmed.count == 2 && trimmed[0].minX < trimmed[1].maxX && trimmed[1].minX < trimmed[0].maxX
        let old = (NSScreen.main.map { LiveMenuBarAXReader(screen: $0) } ?? LiveMenuBarAXReader()).read(items: ["old": pair.helper.pid])?.itemFrames["old"]
        let oldEqualsNonFirst = old.map { abs($0.minX - nonFirstFrame.minX) < 0.5 && abs($0.width - nonFirstFrame.width) < 0.5 } ?? false
        evidence.record("step6a.discriminating", ["childOrder": pair.childOrder, "trimmedStillOverlap": stillOverlap, "oldReaderEqualsNonFirst": oldEqualsNonFirst])
        if stillOverlap || oldEqualsNonFirst {
            evidence.record("step.skipped", ["step": "step6a", "reason": stillOverlap ? "frames overlap after trimming" : "the old reader's frame equals the non-first child's"])
            summary["step6a"] = "skipped (pre-registered)"
            return .ok
        }

        let observer = VisibilityObserver(sampler: Sampler(capturer: capturer, axReader: feedReader(origin: pair.origin)), parameters: parameters)
        var own = [referenceKey.encoded: reference.pid]
        for item in pair.items { own[item.key.encoded] = pair.helper.pid }
        guard let pass = discover() else { return .abort("step 6(a): discovery failed") }
        let neighbours = neighboursLeft(of: pair.items.map(\.key) + [referenceKey], in: pass.set)
        let ids = own.merging(neighbours) { first, _ in first }
        guard let baseline = baseline(observer: observer, items: ids) else { return .abort("step 6(a): the baseline failed") }
        evidence.record("step6a.baseline", ["accepted": baseline.acceptedIDs.filter { own[$0] != nil }, "rejections": baseline.rejections.filter { own[$0.key] != nil }.mapValues { "\($0)" }, "fold": "\(baseline.foldAtBaseline)", "neighbours": neighbours.count])
        guard own.keys.allSatisfy({ baseline.templates[$0] != nil }) else { return .abort("step 6(a): the baseline did not accept all three items") }
        guard let observed = observer.observe(baseline: baseline, targets: [nonFirst.key.encoded] + Array(neighbours.keys), references: [referenceKey.encoded], items: ids) else {
            return .abort("step 6(a): the observation failed")
        }
        let visibility = observed.visibility[nonFirst.key.encoded]
        evidence.record("step6a", ["nonFirst": describe(nonFirst), "visibility": visibility.map { "\($0)" } ?? "none"])
        summary["step6a"] = ["visibility": visibility.map { "\($0)" } ?? "none", "axMinX": nonFirstFrame.minX]
        guard case .drawn? = visibility else { return .abort("step 6(a): expected the non-first child drawn, got \(String(describing: visibility))") }
        return safetyCheck("step6a")
    }
}
