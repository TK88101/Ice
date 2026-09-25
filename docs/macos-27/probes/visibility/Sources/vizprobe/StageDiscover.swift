// `vizprobe discover` -- the 2026-09-23 plan's section 6 steps 1, 2, 4,
// 9, 10, 7, 8 and 11. Steps 9 and 10 decide D10's carry path and D9; they
// record what they measure and carry no expectation, so they run straight
// after step 4, before the steps that can stop the run on a verdict
// (plan Deviation 7).
import AppKit
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed
import MenuBarDiscovery

extension StageRun {
    func discoverSteps() -> [(name: String, body: () -> StepResult)] {
        [
            ("step0.bundles", step0Bundles),
            ("step1.preflight", step1Preflight),
            ("step2.launch", step2LaunchReferenceAndTarget),
            ("step4.hideShow", step4HideShow),
            ("step4.quitTarget", quitTargetKeepingReference),
            ("step9.noDivider", step9NoDivider),
            ("step10a.autosave", { self.step10Autosave(mimic: false) }),
            ("step10b.autosaveNoDivider", { self.step10Autosave(mimic: true) }),
            ("step10.verdict", step10Verdict),
            ("step7.positional", step7Positional),
            ("step8.unnamed", step8Unnamed),
        ]
    }

    /// Runs `body` when there is room for `count` items; a room skip is
    /// recorded and the step passes; a `«` or pill stops the run.
    func withRoom(_ count: Int, step: String, _ body: () -> StepResult) -> StepResult {
        switch room(forItems: count, step: step) {
        case .ok: return body()
        case .skip:
            summary[step] = "skipped (room)"
            return .ok
        case .abort(let reason): return .abort(reason)
        }
    }

    /// Step 4: hide and show the target. Raw `AXError`s recorded; absent from
    /// a discovery pass that read the target's process conclusively, then back
    /// under the same key; `CFEqual` recorded.
    func step4HideShow() -> StepResult {
        guard let target, let targetKey else { return .abort("helpers not launched") }

        let first = RawAX.read(pid: target.pid)
        let again = RawAX.read(pid: target.pid)
        guard let elementA = first.children.first(where: { $0.identifier == "vz-target" })?.element,
              let elementA2 = again.children.first(where: { $0.identifier == "vz-target" })?.element
        else { return .abort("step 4: the raw read did not find vz-target before hiding") }

        target.hide()
        Pump.run(1.0)
        let hiddenRead = RawAX.read(pid: target.pid)
        let hidden = discoverItems(of: target.pid, count: 0)
        let rawStillHasIt = hiddenRead.children.contains { $0.identifier == "vz-target" }
        let absent = hidden != nil && !rawStillHasIt
        if case .abort(let reason) = barCheck("step4.hidden") { return .abort(reason) }

        target.show()
        Pump.run(1.0)
        let shownRead = RawAX.read(pid: target.pid)
        let elementB = shownRead.children.first(where: { $0.identifier == "vz-target" })?.element
        let back = discoverItems(of: target.pid, count: 1)?.items.first

        let record: [String: Any] = [
            "beforeHide": first.record(),
            "whileHidden": hiddenRead.record(),
            "afterShow": shownRead.record(),
            "absentWhileHidden": absent,
            "hiddenPassCompleteness": hidden.map { "\($0.result.set.completeness)" } ?? "no conclusive pass within 5 s",
            "backUnderSameKey": back.map { $0.key == targetKey } ?? false,
            "cfEqualTwoReadsNoToggle": CFEqual(elementA, elementA2),
            "cfEqualAcrossHideShow": elementB.map { CFEqual(elementA, $0) } ?? NSNull(),
        ]
        evidence.record("step4", record)
        summary["step4"] = [
            "absentWhileHidden": absent,
            "backUnderSameKey": back.map { $0.key == targetKey } ?? false,
            "whileHiddenExtrasError": AXErrorNames.name(hiddenRead.extrasError),
            "cfEqualTwoReadsNoToggle": CFEqual(elementA, elementA2),
            "cfEqualAcrossHideShow": elementB.map { CFEqual(elementA, $0) } ?? NSNull(),
        ] as [String: Any]

        guard absent else { return .abort("step 4: the hidden target was not conclusively absent") }
        guard back?.key == targetKey else { return .abort("step 4: the target did not come back under the same key") }
        return safetyCheck("step4")
    }

    /// Before step 9 (as step 6 opens): the target quits, the reference stays.
    func quitTargetKeepingReference() -> StepResult {
        guard let target else { return .abort("helpers not launched") }
        let pid = target.pid
        quit(target)
        self.target = nil
        guard kill(pid, 0) != 0, discoverItems(of: pid, count: 0) != nil else { return .abort("the quit target is still running or listed") }
        return .ok
    }

    /// Step 9 (MEASURED, no expectation): Ice's `.noDivider` shown state on
    /// a helper -- whether discovery lists it, its AX frame, its own AppKit
    /// frame. Pre-registered skip: the width constraint was not found; a
    /// helper that did not end in Ice's state is recorded as "not
    /// reproduced", never as a D10 result.
    func step9NoDivider() -> StepResult {
        withRoom(1, step: "step9") {
            guard let helper = launch(label: "noDivider", app: apps.target, bundleID: HelperRole.target,
                                      arguments: ["--items", "1", "--identifiers", "vz-zero", "--mimic-nodivider"])
            else { return .abort("step 9: could not launch the helper") }
            defer { quit(helper) }
            Pump.run(1.0)
            if case .abort(let reason) = barCheck("step9.launched") { return .abort(reason) }

            let appKit = (helper.request("frames", reply: "frames")?["items"] as? [[String: Any]])?.first
            let raw = RawAX.read(pid: helper.pid)
            let pass = discover()
            let listed = pass?.set.items.filter { $0.process.pid == helper.pid } ?? []
            let dropped = pass?.set.dropped.filter { $0.pid == helper.pid }.map { "\($0.reason)" } ?? []
            let constraintFound = appKit?["constraintFound"] as? Bool ?? false
            let reproduced = appKit?["reachedNoDividerState"] as? Bool ?? false
            let conclusive = pass.map { readConclusively(helper.pid, in: $0) } ?? false

            evidence.record("step9", [
                "appKit": appKit ?? NSNull(),
                "raw": raw.record(),
                "listed": listed.map { describe($0) },
                "dropped": dropped,
                "readConclusively": pass.map { readConclusively(helper.pid, in: $0) } ?? false,
            ])
            summary["step9"] = [
                "status": appKit == nil ? "inconclusive: no frames reply from the helper"
                    : !constraintFound ? "skipped: the width constraint was not found (pre-registered)"
                    : !reproduced ? "not reproduced: the helper did not end in Ice's noDivider state" : "measured",
                "listed": conclusive ? !listed.isEmpty as Any : "inconclusive: the discovery pass did not read the helper conclusively",
                "position": listed.first.map { "\($0.position)" } ?? NSNull(),
                "axFrame": listed.first?.frame.map { [$0.minX, $0.minY, $0.width, $0.height] } ?? NSNull(),
                "rawChildren": raw.children.count,
                "rawExtrasError": AXErrorNames.name(raw.extrasError),
                "rawFrames": raw.children.map { $0.record()["frame"] ?? NSNull() },
                "appKitWindowFrame": appKit?["windowFrame"] ?? NSNull(),
                "matchingConstraints": appKit?["matchingConstraints"] ?? NSNull(),
            ] as [String: Any]
            return safetyCheck("step9")
        }
    }

    /// Step 10 (MEASURED; decides D9): an item with both an autosave name and
    /// an accessibility identifier, as Ice's control items will have. Does
    /// `AXIdentifier` read back -- from the harness, and from the helper
    /// itself, in-process, on a background queue? Each reader's answer is
    /// yes, no (the children were read and none carries it), or
    /// inconclusive (with the reason), so a failed read is never reported as
    /// D9 failing.
    func step10Autosave(mimic: Bool) -> StepResult {
        let step = mimic ? "step10b" : "step10a"
        return withRoom(1, step: step) {
            let base = ["--items", "1", "--identifiers", "vz-ident", "--autosave", "vz-autosave"]
            let arguments = mimic ? base + ["--mimic-nodivider"] : base + ["--glyphs", "target"]
            guard let helper = launch(label: step, app: apps.target, bundleID: HelperRole.target, arguments: arguments) else {
                return .abort("\(step): could not launch the helper")
            }
            Pump.run(1.0)
            if case .abort(let reason) = barCheck("\(step).launched") {
                quit(helper)
                return .abort(reason)
            }

            let appKit = (helper.request("frames", reply: "frames")?["items"] as? [[String: Any]])?.first
            let raw = RawAX.read(pid: helper.pid)
            let selfRead = helper.request("selfread", reply: "selfread", timeout: 5)
            let pass = discover()
            let listed = pass?.set.items.filter { $0.process.pid == helper.pid } ?? []
            let listingConclusive = pass.map { readConclusively(helper.pid, in: $0) } ?? false
            let domainKeys = HelperDefaults.keys(HelperRole.target)
            let safety = safetyCheck(step)

            quit(helper)
            let domainKeysAfter = HelperDefaults.keys(HelperRole.target)

            let harness = harnessAnswer(raw)
            let own = selfAnswer(selfRead)
            evidence.record(step, [
                "appKit": appKit ?? NSNull(),
                "raw": raw.record(),
                "selfRead": selfRead ?? NSNull(),
                "listed": listed.map { describe($0) },
                "domainKeysWhileRunning": domainKeys ?? ["<unreadable>"],
                "domainKeysAfterDelete": domainKeysAfter ?? ["<unreadable>"],
            ])
            summary[step] = [
                "harnessReadsBack": harness,
                "selfReadsBack": own,
                "rawChildren": raw.children.count,
                "rawIdentifierErrors": raw.children.map { AXErrorNames.name($0.identifierError) },
                "selfReadTrusted": selfRead?["trusted"] ?? NSNull(),
                "selfReadOnMainThread": selfRead?["isMainThread"] ?? NSNull(),
                "discoveryListsDeclared": listingConclusive ? listed.contains { $0.basis == .declared && $0.key.identifier == "vz-ident" } as Any : "inconclusive",
                "mimicReachedNoDividerState": mimic ? (appKit?["reachedNoDividerState"] ?? NSNull()) : NSNull(),
                "autosaveWroteKeys": domainKeys.map { !$0.isEmpty } as Any? ?? NSNull(),
                "domainEmptyAfter": domainKeysAfter == [],
            ] as [String: Any]
            return safety
        }
    }

    /// `noValue` and `attributeUnsupported` are answers; any other error on
    /// a child's identifier read makes "no" unprovable.
    private static let conclusiveIdentifierErrors: Set<Int32> = [AXError.success.rawValue, AXError.noValue.rawValue, AXError.attributeUnsupported.rawValue]

    private func harnessAnswer(_ raw: RawAXRead) -> String {
        guard raw.extrasError == .success else { return "inconclusive: extras \(AXErrorNames.name(raw.extrasError))" }
        guard raw.childrenError == .success else { return "inconclusive: children \(raw.childrenError.map { AXErrorNames.name($0) } ?? "not read")" }
        if raw.children.contains(where: { $0.identifier == "vz-ident" }) { return "yes" }
        if raw.children.isEmpty { return "inconclusive: no child element (a step 9 matter, not D9)" }
        if let bad = raw.children.first(where: { !Self.conclusiveIdentifierErrors.contains($0.identifierError.rawValue) }) {
            return "inconclusive: identifier \(AXErrorNames.name(bad.identifierError))"
        }
        return "no"
    }

    private func selfAnswer(_ reply: [String: Any]?) -> String {
        guard let reply else { return "inconclusive: no reply within 5 s" }
        guard reply["trusted"] as? Bool == true else { return "inconclusive: the helper is not trusted for Accessibility" }
        guard let extras = reply["extrasError"] as? Int, extras == Int(AXError.success.rawValue) else {
            return "inconclusive: extras error \(reply["extrasError"] ?? "?")"
        }
        guard let childrenError = reply["childrenError"] as? Int, childrenError == Int(AXError.success.rawValue) else {
            return "inconclusive: children error \(reply["childrenError"] ?? "?")"
        }
        let children = (reply["children"] as? [[String: Any]]) ?? []
        if children.contains(where: { ($0["identifier"] as? String) == "vz-ident" }) { return "yes" }
        if children.isEmpty { return "inconclusive: no child element (a step 9 matter, not D9)" }
        if let bad = children.compactMap({ $0["identifierError"] as? Int }).first(where: { !Self.conclusiveIdentifierErrors.contains(Int32($0)) }) {
            return "inconclusive: identifier error \(bad)"
        }
        return "no"
    }

    /// After 10a and 10b: the explicit D9 verdict the plan asks for. Any
    /// conclusive "no" is the blocker (the sections fall to D10's carry path
    /// for good); "holds" needs every reader of the plain item to say yes.
    func step10Verdict() -> StepResult {
        let answers = ["step10a", "step10b"].flatMap { step -> [(String, String)] in
            guard let entry = summary[step] as? [String: Any] else { return [(step, "not run")] }
            return [("\(step).harness", entry["harnessReadsBack"] as? String ?? "?"), ("\(step).self", entry["selfReadsBack"] as? String ?? "?")]
        }
        let plain = answers.filter { $0.0.hasPrefix("step10a") }.map(\.1)
        let verdict: String
        if answers.contains(where: { $0.1 == "no" }) {
            verdict = "fails: the identifier did not read back -- a blocker; the sections fall to D10's carry path"
        } else if plain == ["yes", "yes"] {
            let mimic = answers.filter { $0.0.hasPrefix("step10b") }.map(\.1)
            verdict = mimic == ["yes", "yes"] ? "holds (plain and noDivider items)" : "holds for a plain item; the noDivider item: \(mimic.joined(separator: " / "))"
        } else {
            verdict = "inconclusive: \(answers.map { "\($0.0)=\($0.1)" }.joined(separator: ", "))"
        }
        summary["D9"] = verdict
        evidence.record("step10.verdict", ["D9": verdict])
        return .ok
    }

    /// Step 7: two items of one pid with no identifier -> two `.positional`
    /// keys; the child order against x recorded; the feed gives no frame;
    /// `CheckPlan` skips both as `.positional`.
    func step7Positional() -> StepResult {
        guard let referenceKey else { return .abort("reference not discovered") }
        return withRoom(2, step: "step7") {
            guard let helper = launch(label: "positional", app: apps.target, bundleID: HelperRole.target,
                                      arguments: ["--items", "2", "--identifiers", "none", "--glyphs", "target,alt"])
            else { return .abort("step 7: could not launch the helper") }
            defer { quit(helper) }
            Pump.run(1.0)
            if case .abort(let reason) = barCheck("step7.launched") { return .abort(reason) }

            guard let found = discoverItems(of: helper.pid, count: 2) else { return .abort("step 7: two items were not discovered") }
            let items = found.items
            guard items.allSatisfy({ $0.basis == .positional && $0.key.childIndex != nil }) else {
                evidence.record("step7.unexpected", ["items": items.map { describe($0) }])
                return .abort("step 7: expected two .positional items")
            }

            let order = items.map { ["childIndex": $0.key.childIndex ?? -1, "minX": $0.frame?.minX ?? -1] as [String: Any] }
            let reader = feedReader(origin: found.result.origin)
            let fed = reader.read(items: Dictionary(uniqueKeysWithValues: items.map { ($0.key.encoded, helper.pid) }))
            let feedFrames = fed?.itemFrames.count ?? -1

            let standIn = StandInDividerDiscoverer(base: discoverer, sectionKeys: Set(items.map(\.key)))
            let set = Pump.blocking { await standIn.discover(previous: nil) }?.set
            let sectionMap = Dictionary(uniqueKeysWithValues: items.map { ($0.tagKey, ItemSection.hidden) })
            let plan = set.map { CheckPlan.make(sections: [.hidden], set: $0, sectionMap: sectionMap, explicitCandidates: [referenceKey]) }

            // Only the helpers' own keys reach the evidence: `alsoObserved` is
            // counted, never listed.
            var planRecord: [String: Any] = ["result": "discovery failed"]
            if case .observe(let targets, let alsoObserved, let candidates, let skipped)? = plan {
                planRecord = ["targets": targets.map(\.encoded), "alsoObserved": alsoObserved.count,
                              "referenceCandidates": candidates.map(\.encoded),
                              "skipped": Dictionary(uniqueKeysWithValues: skipped.map { ($0.key.encoded, "\($0.value)") })]
            } else if case .skip(let reason)? = plan {
                planRecord = ["skip": "\(reason)"]
            }
            evidence.record("step7", ["items": items.map { describe($0) }, "childOrderAgainstX": order, "feedFrames": feedFrames, "checkPlan": planRecord])
            summary["step7"] = ["childOrderAgainstX": order, "feedFrames": feedFrames, "checkPlan": planRecord] as [String: Any]

            guard feedFrames == 0 else { return .abort("step 7: the feed returned a frame for a positional key") }
            let expectedSkips = Dictionary(uniqueKeysWithValues: items.map { ($0.key, CheckSkipReason.positional) })
            guard case .observe(let targets, _, _, let skipped)? = plan, targets.isEmpty, skipped == expectedSkips else {
                return .abort("step 7: CheckPlan did not skip both items as .positional")
            }
            return safetyCheck("step7")
        }
    }

    /// Step 8: one item with no identifier -> `.unnamed`, observed drawn.
    func step8Unnamed() -> StepResult {
        guard let reference, let referenceKey else { return .abort("reference not discovered") }
        return withRoom(1, step: "step8") {
            guard let helper = launch(label: "unnamed", app: apps.target, bundleID: HelperRole.target,
                                      arguments: ["--items", "1", "--identifiers", "none", "--glyphs", "target"])
            else { return .abort("step 8: could not launch the helper") }
            defer { quit(helper) }
            Pump.run(1.0)
            if case .abort(let reason) = barCheck("step8.launched") { return .abort(reason) }

            guard let found = discoverItems(of: helper.pid, count: 1) else { return .abort("step 8: the item was not discovered") }
            let item = found.items[0]
            guard item.basis == .unnamed else {
                evidence.record("step8.unexpected", ["item": describe(item)])
                return .abort("step 8: expected .unnamed, got \(item.basis)")
            }

            let observer = VisibilityObserver(sampler: Sampler(capturer: capturer, axReader: feedReader(origin: found.result.origin)), parameters: parameters)
            let own: [String: pid_t] = [item.key.encoded: helper.pid, referenceKey.encoded: reference.pid]
            let neighbours = neighboursLeft(of: [item.key, referenceKey], in: found.result.set)
            let ids = own.merging(neighbours) { first, _ in first }
            guard let baseline = baseline(observer: observer, items: ids) else { return .abort("step 8: the baseline failed") }
            evidence.record("step8.baseline", ["accepted": baseline.acceptedIDs.filter { own[$0] != nil }, "rejections": baseline.rejections.filter { own[$0.key] != nil }.mapValues { "\($0)" }, "fold": "\(baseline.foldAtBaseline)", "neighbours": neighbours.count, "neighboursAccepted": baseline.acceptedIDs.filter { neighbours[$0] != nil }.count])
            guard baseline.templates[item.key.encoded] != nil, baseline.templates[referenceKey.encoded] != nil else {
                return .abort("step 8: the baseline did not accept both the unnamed item and the reference")
            }
            guard let observed = observer.observe(baseline: baseline, targets: [item.key.encoded] + Array(neighbours.keys), references: [referenceKey.encoded], items: ids) else {
                return .abort("step 8: the observation failed")
            }
            let visibility = observed.visibility[item.key.encoded]
            evidence.record("step8", ["item": describe(item), "visibility": visibility.map { "\($0)" } ?? "none", "stable": observed.reading.captureStable])
            summary["step8"] = ["basis": "\(item.basis)", "visibility": visibility.map { "\($0)" } ?? "none"]
            guard case .drawn? = visibility else { return .abort("step 8: expected drawn, got \(String(describing: visibility))") }
            return safetyCheck("step8")
        }
    }
}
