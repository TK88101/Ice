// Stages O1 and M. Their parameters come from earlier runs and are passed on the
// command line, so every number a stage used is in its manifest:
//   brackets   from the config's own scan ("hide:lo:hi,edge:lo:hi,top:lo:hi")
//   edge bound S's left bound seen in that scan
//   reset/hold the protocol O0/O1 settled on
import AppKit
import SafeWidthCore

struct Transition {
    let name: String
    var lo: Double
    var hi: Double

    /// "hide:24:32,edge:560:592" -> transitions.
    static func parse(_ text: String) -> [Transition] {
        text.split(separator: ",").compactMap { part in
            let fields = part.split(separator: ":")
            guard fields.count == 3, let lo = Double(fields[1]), let hi = Double(fields[2]) else {
                return nil
            }
            return Transition(name: String(fields[0]), lo: lo, hi: hi)
        }
    }
}

enum StageM {
    static let resolution = 4.0
    static let toggleCycles = 5

    struct Parameters {
        let transitions: [Transition]
        let edgeBound: Double?
        let reset: ResetKind
        let hold: Double
        let repeats: Int
        let candidate: Double?
    }

    /// Which side of a transition a sample is on: true = new state, false = old
    /// state, nil = neither (the sample cannot move the bracket).
    static func side(_ transition: String, _ sample: LegSample, edgeBound: Double?) -> Bool? {
        switch transition {
        case "hide":
            if sample.target == .overflowed { return true }
            if case .visible = sample.target { return false }
            return nil
        case "top":
            if case .visible = sample.target { return true }
            return sample.target == .overflowed ? false : nil
        case "edge":
            guard let left = sample.spacerLeft, let bound = edgeBound else { return nil }
            return left <= bound + 1.0
        case "selfov":
            return sample.spacerDrawn.map { !$0 }
        default:
            return nil
        }
    }

    // MARK: - M

    static func run(_ experiment: Experiment, config: FrontConfig, parameters: Parameters) throws {
        let actors = try Actors.up(experiment, config: config)
        defer { actors.teardown() }
        actors.world.overflowAttributed = true
        let holds = parameters.hold > 0 ? [parameters.hold] : []
        var jumpLegs: [[LegSample]] = []
        for rep in 0..<parameters.repeats where actors.canExpand {
            jumpLegs.append(bisectAll(actors, parameters: parameters, holds: holds, rep: rep))
        }
        var upLegs: [[LegSample]] = []
        var downLegs: [[LegSample]] = []
        var incomplete: [String: Int] = [:]
        for rep in 0..<parameters.repeats where actors.canExpand {
            let (up, down) = staircaseLoop(actors, parameters: parameters, holds: holds, rep: rep)
            upLegs.append(up)
            if let down {
                downLegs.append(down)
            } else {
                incomplete["up", default: 0] += 1
                incomplete["down", default: 0] += 1
            }
        }
        let toggleOK = actors.canExpand ? parameters.candidate.map { toggle(actors, at: $0, holds: holds) } : nil
        report(experiment, config: config, legs: ["jump": jumpLegs, "up": upLegs, "down": downLegs],
               toggleOK: toggleOK, incomplete: incomplete)
    }

    /// Bisects every transition inside its own scan bracket. All probes of one
    /// repeat form that repeat's jump leg.
    private static func bisectAll(_ actors: Actors, parameters: Parameters, holds: [Double], rep: Int) -> [LegSample] {
        var leg: [LegSample] = []
        for var transition in parameters.transitions {
            var inconclusive = false
            while actors.canExpand, let next = Planner.nextBisection(lo: transition.lo, hi: transition.hi, resolution: resolution) {
                let label: [String: Any] = ["stage": "m", "path": "jump", "rep": rep, "transition": transition.name]
                guard let record = actors.jump(next, reset: parameters.reset, holds: holds, label: label) else {
                    inconclusive = true
                    break
                }
                if case .harm = record.outcome {
                    leg.append(LegSample(length: next, target: .ambiguous, harm: true))
                    inconclusive = true
                    break
                }
                guard let sample = record.sample else {
                    inconclusive = true
                    break
                }
                leg.append(sample)
                switch side(transition.name, sample, edgeBound: parameters.edgeBound) {
                case .some(true): transition.hi = next
                case .some(false): transition.lo = next
                case .none:
                    actors.experiment.evidence.record("bisect.inconclusive", label.merging(["length": next, "lo": transition.lo, "hi": transition.hi]) { $1 })
                    inconclusive = true
                }
                if inconclusive {
                    break
                }
            }
            let converged = !inconclusive && actors.canExpand
            actors.experiment.evidence.record("bisect.result", [
                "rep": rep, "transition": transition.name, "lo": transition.lo, "hi": transition.hi,
                "converged": converged,
            ])
            print("M \(actors.config.name) rep \(rep) \(transition.name): (\(Int(transition.lo)), \(Int(transition.hi))]\(converged ? "" : " inconclusive")")
        }
        return leg
    }

    /// Up from rest to past W_top, then back down to rest, one length at a time.
    private static func staircaseLoop(_ actors: Actors, parameters: Parameters, holds: [Double], rep: Int) -> ([LegSample], [LegSample]?) {
        guard actors.reset(.full).ok else {
            return ([], nil)
        }
        let centres = parameters.transitions.map { ($0.lo + $0.hi) / 2 }
        let topHi = parameters.transitions.first { $0.name == "top" }?.hi ?? 1200
        let upLengths = Planner.staircase(from: 0, to: topHi + 48, coarse: 16, fine: 4, fineAround: centres, radius: 32)
        let up = walk(actors, lengths: upLengths, holds: holds, label: ["stage": "m", "path": "up", "rep": rep])
        guard up.completed, let last = upLengths.last else {
            return (up.samples, nil)
        }
        let downLengths = Planner.staircase(from: last, to: 8, coarse: 16, fine: 4, fineAround: centres, radius: 32)
        let down = walk(actors, lengths: downLengths, holds: holds, label: ["stage": "m", "path": "down", "rep": rep])
        actors.restNow()
        return (up.samples, down.samples)
    }

    private static func walk(_ actors: Actors, lengths: [Double], holds: [Double], label: [String: Any]) -> (samples: [LegSample], completed: Bool) {
        var samples: [LegSample] = []
        for length in lengths where length > 0 {
            actors.world.context = label.merging(["config": actors.config.name]) { $1 }
            guard let record = actors.expand(length, holds: holds) else {
                return (samples, false)
            }
            if case .harm = record.outcome {
                samples.append(LegSample(length: length, target: .ambiguous, harm: true))
                return (samples, false)
            }
            if case .stop = record.outcome {
                return (samples, false)
            }
            guard let sample = record.sample else {
                return (samples, false)
            }
            samples.append(sample)
        }
        return (samples, true)
    }

    /// Ice's own pattern: the same items toggled between rest and one length.
    private static func toggle(_ actors: Actors, at length: Double, holds: [Double]) -> Bool {
        guard actors.canExpand, actors.reset(.full).ok else {
            return false
        }
        for cycle in 0..<toggleCycles {
            actors.world.context = ["stage": "m", "path": "toggle", "cycle": cycle, "config": actors.config.name]
            guard let expanded = actors.expand(length, holds: holds) else {
                return false
            }
            let hidden = expanded.sample?.target == .overflowed
            let rest = actors.restNow()
            var visibleAtRest = false
            if case .visible = actors.settledSample(rest)?.target { visibleAtRest = true }
            actors.experiment.evidence.record("toggle", ["cycle": cycle, "length": length, "hidden": hidden, "visibleAtRest": visibleAtRest])
            guard hidden, visibleAtRest else {
                print("M \(actors.config.name) toggle cycle \(cycle): FAILED (hidden \(hidden), visible at rest \(visibleAtRest))")
                return false
            }
        }
        print("M \(actors.config.name) toggle at \(Int(length)): \(toggleCycles)/\(toggleCycles)")
        return true
    }

    // MARK: - Verdicts

    private static func report(_ experiment: Experiment, config: FrontConfig, legs: [String: [[LegSample]]],
                               toggleOK: Bool?, incomplete: [String: Int]) {
        var table: [String: Any] = [
            "config": config.name,
            "toggle": toggleOK.map { $0 ? "pass" : "fail" } ?? "not run",
            "incompleteLegs": incomplete,
        ]
        for path in ["jump", "up", "down"] {
            let perRepeat = (legs[path] ?? []).filter { !$0.isEmpty }.map { Analysis.brackets(for: $0, tolerance: 1.0) }
            guard !perRepeat.isEmpty else {
                table[path] = "no data"
                continue
            }
            var verdicts: [Bound: Verdict] = [:]
            for bound in Bound.allCases {
                verdicts[bound] = Analysis.verdict(hide: perRepeat.map(\.hide), bound: perRepeat.map { $0.bracket(for: bound) }, tolerance: resolution)
            }
            let headline = Analysis.headline(verdicts)
            table[path] = [
                "brackets": perRepeat.map(StageScan.describe),
                "verdicts": Dictionary(uniqueKeysWithValues: verdicts.map { ($0.key.rawValue, String(describing: $0.value)) }),
                "headline": String(describing: headline),
            ]
            let partial = incomplete[path] ?? 0
            print("M \(config.name) \(path): \(headline)\(partial > 0 ? "  [\(partial) of \(perRepeat.count) legs cut short]" : "")\(toggleOK == false ? "  [TOGGLE FAILED — interval not usable]" : "")")
            for bound in Bound.allCases {
                print("    \(bound.rawValue): \(verdicts[bound].map { String(describing: $0) } ?? "-")")
            }
        }
        experiment.evidence.record("m.report", table)
    }

    // MARK: - O1

    /// At each width: jump from a full reset, jump from a light reset, and a
    /// Δ=16 staircase from rest, each held with captures at the hold times.
    static func runO1(_ experiment: Experiment, widths: [Double], repeats: Int) throws {
        let actors = try Actors.up(experiment, config: FrontConfig.all["mid"]!)
        defer { actors.teardown() }
        actors.world.overflowAttributed = true
        for rep in 0..<repeats {
            for width in widths where actors.canExpand {
                for reset in [ResetKind.full, .light] {
                    let label: [String: Any] = ["stage": "o1", "path": "jump-\(reset.rawValue)", "rep": rep, "width": width]
                    let record = actors.jump(width, reset: reset, holds: Stages.holds, label: label)
                    print("O1 jump-\(reset.rawValue) \(Int(width)) rep \(rep): \(record.map { String(describing: $0.sample?.target) } ?? "void")")
                }
                guard actors.reset(.full).ok else {
                    continue
                }
                let steps = Planner.staircase(from: 0, to: width, coarse: 64, fine: 64, fineAround: [], radius: 0)
                let label: [String: Any] = ["stage": "o1", "path": "step", "rep": rep, "width": width]
                let walked = walk(actors, lengths: Array(steps.dropLast()), holds: [], label: label)
                if walked.completed {
                    actors.world.context = label.merging(["config": "mid"]) { $1 }
                    let record = actors.expand(width, holds: Stages.holds)
                    print("O1 step \(Int(width)) rep \(rep): \(String(describing: record?.sample?.target))")
                }
                actors.restNow()
            }
        }
    }
}
