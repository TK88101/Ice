// Stage "scan" — per config, a coarse jump scan from a full reset at every grid
// length. It yields the brackets every later bisection must stay inside, the
// attribution of the overflow to T, and the validated template of the chevron.
import AppKit
import SafeWidthCore

enum StageScan {
    static let grid = Planner.grid(
        [GridSegment(from: 8, to: 256, step: 8), GridSegment(from: 288, to: 1200, step: 32)],
        extras: [2000, 5000, 10_000]
    )
    static let validationCycles = 3

    static func run(_ experiment: Experiment, config: FrontConfig) throws {
        let actors = try Actors.up(experiment, config: config)
        defer { actors.teardown() }
        var samples: [LegSample] = []
        var attributed: Bool?
        var voids = 0
        for length in grid where actors.canExpand {
            let label: [String: Any] = ["stage": "scan", "path": "jump"]
            guard let record = actors.jump(length, reset: .full, holds: [], label: label) else {
                voids += 1
                if voids >= 3 {
                    print("scan \(config.name): three trials in a row could not reach a verified rest state — stopping")
                    break
                }
                continue
            }
            voids = 0
            if case .harm = record.outcome {
                samples.append(LegSample(length: length, target: .ambiguous, harm: true))
                print("scan \(config.name): guard fired at \(Int(length)) — config stops")
                break
            }
            if case .stop(let reasons) = record.outcome {
                print("scan \(config.name): the guard could not verify the bar at \(Int(length)) — stopping (\(reasons.count) reasons)")
                break
            }
            guard let sample = record.sample else {
                continue
            }
            samples.append(sample)
            print("scan \(config.name) \(Int(length)): \(sample.target) S.left=\(sample.spacerLeft.map { String(format: "%.1f", $0) } ?? "-")\(sample.spacerLeftFromAX ? "(AX)" : "") appkit=\(sample.spacerAppKitWidth.map { String(Int($0)) } ?? "-") drawn=\(String(describing: sample.spacerDrawn))")
            if attributed == nil, sample.target == .overflowed {
                attributed = attribute(actors, at: length)
                actors.world.overflowAttributed = attributed
            }
        }
        let final = attributed == false ? samples.map(downgrade) : samples
        let brackets = Analysis.brackets(for: final, tolerance: 1.0)
        experiment.evidence.record("scan.brackets", [
            "config": config.name,
            "attributed": attributed.map { $0 ? "yes" : "no" } ?? "never overflowed",
            "chevronTemplate": actors.instrument.chevronTemplate != nil,
            "brackets": describe(brackets),
        ])
        print("scan \(config.name) brackets: \(describe(brackets))")
    }

    /// At the first overflowed length: cut the chevron template from where the new
    /// MenuBarAgent item sits, validate it over hide/unhide cycles, then quit T
    /// alone. The overflow is T's if the chevron goes away with T while S's
    /// markers stay drawn.
    private static func attribute(_ actors: Actors, at length: Double) -> Bool {
        let world = actors.world
        let evidence = actors.experiment.evidence
        guard actors.reset(.full).ok else {
            evidence.record("attribution", ["length": length, "result": "no verified rest to start from"])
            return false
        }
        world.context = ["stage": "scan", "path": "attribution", "config": actors.config.name]
        guard let first = actors.expand(length, holds: []), case .settled = first.outcome,
              let observation = world.last, let chevronItem = world.newAgentItems(observation).first else {
            evidence.record("attribution", ["length": length, "result": "could not reproduce the overflow"])
            actors.restNow()
            return false
        }
        let template = Calibrate.template(id: "chevron", x: chevronItem.x, w: chevronItem.w, from: observation.frame.bitmap)
        evidence.keep(observation.frame.file, label: "chevron-source-\(Int(length))")
        let validated = validate(template, actors: actors, length: length)
        if validated {
            actors.instrument.setChevronTemplate(template)
        }
        guard let again = actors.expand(length, holds: []), case .settled = again.outcome else {
            evidence.record("attribution", ["length": length, "result": "the guard ended the attribution"])
            actors.restNow()
            return false
        }
        actors.quitTargetOnly()
        Session.spin(1.0)
        let after = actors.instrument.observe(spacer: actors.spacer, extraPids: world.helperPids)
        let chevronGone = after.map { !world.chevronPresent($0) } ?? false
        let spacerDrawn = after.map { world.legSample($0, length: length).spacerDrawn == true } ?? false
        evidence.record("attribution", [
            "length": length,
            "chevronAX": [chevronItem.x, chevronItem.w],
            "templateValidated": validated,
            "chevronGoneWithT": chevronGone,
            "spacerStillDrawn": spacerDrawn,
            "capture": after.flatMap { evidence.keep($0.frame.file, label: "attribution-\(Int(length))") } ?? "?",
        ])
        print("attribution at \(Int(length)): template \(validated ? "validated" : "REJECTED"), chevron gone with T: \(chevronGone), S still drawn: \(spacerDrawn)")
        _ = actors.reset(.full)
        return chevronGone && spacerDrawn
    }

    /// The template must be found at the overflowed length and absent at rest,
    /// every cycle; a single coincidence is not enough.
    private static func validate(_ template: ItemTemplate, actors: Actors, length: Double) -> Bool {
        let probe = actors.experiment.instrument(markers: [:])
        probe.setChevronTemplate(template)
        for cycle in 0..<validationCycles {
            guard case .settled = actors.restNow() else {
                return false
            }
            let atRest = probe.observe(spacer: actors.spacer, extraPids: [])?.chevron
            guard let expanded = actors.expand(length, holds: []), case .settled = expanded.outcome else {
                return false
            }
            let hidden = probe.observe(spacer: actors.spacer, extraPids: [])?.chevron
            actors.experiment.evidence.record("chevron.validate", [
                "cycle": cycle, "atRest": atRest.map(LiveWorld.describe) ?? "?", "hidden": hidden.map(LiveWorld.describe) ?? "?",
            ])
            guard atRest == .absent, case .unique = hidden ?? .absent else {
                return false
            }
        }
        return true
    }

    private static func downgrade(_ sample: LegSample) -> LegSample {
        guard sample.target == .overflowed else {
            return sample
        }
        var copy = sample
        copy.target = .invisibleUnconfirmed
        return copy
    }

    static func describe(_ brackets: LegBrackets) -> [String: String] {
        [
            "hide": describe(brackets.hide), "edge": describe(brackets.edge), "sat": describe(brackets.sat),
            "selfov": describe(brackets.selfov), "top": describe(brackets.top), "harm": describe(brackets.harm),
        ]
    }

    static func describe(_ bracket: Bracket) -> String {
        switch bracket {
        case .at(let lo, let hi): return "(\(lo.map { String(Int($0)) } ?? "-"), \(Int(hi))]"
        case .notObserved(let maxTested): return "not observed up to \(Int(maxTested))"
        }
    }
}
