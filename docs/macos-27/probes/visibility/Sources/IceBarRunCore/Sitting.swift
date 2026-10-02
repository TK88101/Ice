// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q17, Q20): the
// repeat rule of route C section 3, one S-adv sweep, the sitting's gates
// between S0, S-adv and S1, and the Chinese lines of route C 7a.
import IceBarOracle

public enum RepeatResult: String, Codable, Equatable, Sendable {
    case pass, noGo, inconclusive
}

public enum RepeatOutcome: Codable, Equatable, Sendable {
    case pass
    case noGo
    case notShown(String)
    /// Fewer passing repeats than needed so far.
    case incomplete
}

public enum Repeats {
    /// An inconclusive repeat is re-run at most twice; a third in a row is not shown.
    public static let maxInconclusiveInARow = 3

    public static func judge(_ results: [RepeatResult], needed: Int) -> RepeatOutcome {
        if results.contains(.noGo) { return .noGo }
        var passes = 0
        var inARow = 0
        for result in results {
            if result == .pass {
                passes += 1
                inARow = 0
            } else {
                inARow += 1
                if inARow == maxInconclusiveInARow { return .notShown("inconclusive three times") }
            }
        }
        return passes >= needed ? .pass : .incomplete
    }
}

public enum SAdvStepResult: Equatable, Sendable {
    /// The claim granted while the oracle saw a member or `«`.
    case noGo
    /// Every capture conclusive and no member seen: the upward endpoint.
    case membersGone
    case membersSeen
    case inconclusive
}

public enum SAdvSweepStatus: Equatable, Sendable {
    case continuing
    case done
    case noGo
    case inconclusive(String)
}

/// Q17: up from 16 pt in 16 pt steps until the members are gone, then down to 16 pt.
public struct SAdvSweep: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case up, down }

    public static let stepPt = 16.0
    public static let capPt = 1000.0

    public private(set) var phase = Phase.up
    public private(set) var status = SAdvSweepStatus.continuing
    private var length = SAdvSweep.stepPt

    public init() {}

    public func nextLength() -> Double? {
        status == .continuing ? length : nil
    }

    @discardableResult
    public mutating func record(_ result: SAdvStepResult) -> SAdvSweepStatus {
        guard status == .continuing else { return status }
        if result == .noGo {
            status = .noGo
        } else if phase == .up, result != .membersGone {
            if length + Self.stepPt > Self.capPt {
                status = .inconclusive("members still seen at \(Int(length)) pt, the last step under \(Int(Self.capPt))")
            } else {
                length += Self.stepPt
            }
        } else {
            phase = .down
            if length - Self.stepPt < Self.stepPt { status = .done } else { length -= Self.stepPt }
        }
        return status
    }
}

public struct SAdvVariant: Equatable, Sendable {
    public enum Appearance: String, Equatable, Sendable { case dark, light }

    public let appearance: Appearance
    public let colouredMembers: Bool

    public init(appearance: Appearance, colouredMembers: Bool) {
        self.appearance = appearance
        self.colouredMembers = colouredMembers
    }

    public var name: String { "\(appearance.rawValue)-\(colouredMembers ? "coloured" : "ordinary")" }

    public static let sweepsPerVariant = 2
    public static let all = [Appearance.dark, .light].flatMap { appearance in
        [false, true].map { SAdvVariant(appearance: appearance, colouredMembers: $0) }
    }
}

public enum SittingResult: Equatable, Sendable {
    case completed(String)
    case failed(String)
    case interrupted(String)
    case safetyStop(String)
}

public enum SittingDecision: Equatable, Sendable {
    case proceed
    case end(SittingResult)
}

/// Q20: what each stage's outcome does to the sitting.
public enum Sitting {
    public static func afterS0(_ outcome: S0Outcome, c3: C3Outcome, section8: Section8Outcome) -> SittingDecision {
        switch outcome {
        case .noGo: return .end(.failed("S0: the claim was granted with a long menu"))
        case .notShown(let why): return .end(.failed("S0 not shown: \(why)"))
        case .incomplete: return .end(.failed("S0 not shown: ended before \(S0Judge.cycles) cycles"))
        case .pass: break
        }
        switch c3 {
        case .notListed(let id): return .end(.interrupted("S0: window-server bounds unusable (\(id) not listed); the owner decides"))
        case .mismatch(let id): return .end(.interrupted("S0: window-server bounds unusable (\(id) off its AX frame); the owner decides"))
        case .holds: break
        }
        switch section8 {
        case .unmeasured(let names):
            return .end(.interrupted("S0: section 8 cannot be checked (\(names.joined(separator: ", ")) unmeasured); the owner decides"))
        case .contradiction(let names):
            return .end(.interrupted("S0: section 8 contradiction (\(names.joined(separator: ", "))); the owner decides"))
        case .consistent:
            return .proceed
        }
    }

    /// Q18, risk K2: S-adv needs both appearance variants; how is the owner's decision.
    public static func beforeSAdv(appearanceDecided: Bool) -> SittingDecision {
        appearanceDecided ? .proceed : .end(.interrupted("S-adv waits for the owner's decision on the appearance variants (E3, K2)"))
    }

    public static func afterSAdv(_ outcome: RepeatOutcome, bControl: BOutcome) -> SittingDecision {
        switch outcome {
        case .noGo: return .end(.failed("S-adv: the claim was granted while the oracle saw a member or «"))
        case .notShown(let why): return .end(.failed("S-adv not shown: \(why)"))
        case .incomplete: return .end(.failed("S-adv not shown: ended before every sweep"))
        case .pass: break
        }
        switch bControl {
        case .valid: return .proceed
        case .mismatch(let index): return .end(.interrupted("« (b) control: mismatch at capture \(index); the owner decides"))
        case .insufficientCaptures(let n):
            return .end(.interrupted("« (b) control: \(n) captures, \(BControl.minCaptures) needed; the owner decides"))
        case .insufficientEpisodes(let n):
            return .end(.interrupted("« (b) control: \(n) episodes, \(BControl.minEpisodes) needed; the owner decides"))
        }
    }

    public static func afterS1(_ verdict: S1Verdict) -> SittingResult {
        switch verdict {
        case .capacity(let k): .completed("S1 capacity \(k)")
        case .capacityBelowFour(let k): .interrupted("S1 capacity \(k), below \(S1Sequencer.minCapacity); the owner decides before S2")
        case .noGo(let why): .failed("S1 NO-GO: \(why)")
        case .safetyStop(let why): .safetyStop(why)
        }
    }
}

/// Route C 7a: what the owner reads in the morning.
public enum ProgressLine {
    public static func start(step: Int, name: String, clock: String, elapsed: Int) -> String {
        "步驟 \(step) \(name) 開始 [\(clock)，已過 \(hoursMinutes(elapsed))]"
    }

    public static func end(step: Int, name: String, status: String, clock: String, elapsed: Int) -> String {
        "步驟 \(step) \(name) 結束：\(status) [\(clock)，已過 \(hoursMinutes(elapsed))]"
    }

    public static func final(_ result: SittingResult, directory: String) -> String {
        let (word, reason): (String, String) = switch result {
        case .completed(let why): ("完成", why)
        case .failed(let why): ("失敗", why)
        case .interrupted(let why): ("中斷", why)
        case .safetyStop(let why): ("安全停止", why)
        }
        return "結果：\(word)｜\(reason)｜\(directory)"
    }

    static func hoursMinutes(_ seconds: Int) -> String {
        let minutes = seconds % 3600 / 60
        return "\(seconds / 3600):\(minutes < 10 ? "0" : "")\(minutes)"
    }
}

public enum SAdvStep: Equatable, Sendable {
    case sweep(SAdvVariant)
    case chevron(SAdvVariant)
    case finished(RepeatOutcome)
}

/// Q17: each variant's two sweeps (route C: "two sweeps each way per
/// variant"), an inconclusive sweep re-run at most twice, then the `«` rest
/// state. One step process per sweep.
public struct SAdvSequencer: Equatable, Sendable {
    private var variantIndex = 0
    private var results = [RepeatResult]()
    private var outcome: RepeatOutcome?

    public init() {}

    public func next() -> SAdvStep {
        if let outcome { return .finished(outcome) }
        return variantIndex < SAdvVariant.all.count ? .sweep(SAdvVariant.all[variantIndex]) : .chevron(SAdvVariant.all[0])
    }

    public mutating func record(_ result: RepeatResult) {
        guard outcome == nil else { return }
        results.append(result)
        let inSweeps = variantIndex < SAdvVariant.all.count
        let name = inSweeps ? SAdvVariant.all[variantIndex].name : "«"
        switch Repeats.judge(results, needed: inSweeps ? SAdvVariant.sweepsPerVariant : 1) {
        case .noGo: outcome = .noGo
        case .notShown(let why): outcome = .notShown("\(name): \(why)")
        case .incomplete: break
        case .pass:
            results = []
            if inSweeps { variantIndex += 1 } else { outcome = .pass }
        }
    }
}
