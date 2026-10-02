// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q20): the whole
// sitting as one pure state machine (route C O3: S0, S-adv, S1 in one
// sitting). `vizprobe icebar-run` only runs each requested step as a child
// process, verifies its report and hands it back here.
import C2Core
import IceBarOracle

public struct SittingRequest: Equatable, Sendable {
    public let kind: StepKind
    public let members: Int
    public let menu: C2MenuWidth
    /// The progress line's name ("S0", "S-adv dark-ordinary", "S1 k2-short").
    public let name: String

    public init(kind: StepKind, members: Int, menu: C2MenuWidth, name: String) {
        self.kind = kind
        self.members = members
        self.menu = menu
        self.name = name
    }
}

public enum SittingNext: Equatable, Sendable {
    case run(SittingRequest)
    /// Deviation 5 D5.2: set the desktop picture to the staged image of this
    /// appearance (`nil`: restore the original), then call `desktopPictureSet`.
    case setDesktopPicture(Appearance?)
    case finished(SittingResult)
}

public struct SittingDriver: Sendable {
    /// Route C: S0 is k = 2 with a long menu; S-adv is k = 4 with a short one.
    public static let s0 = SittingRequest(kind: .s0, members: 2, menu: .long, name: "S0")
    public static let sAdvMembers = 4
    public static let sAdvMenu = C2MenuWidth.short

    private enum Phase: Sendable {
        case s0
        case sAdv(SAdvSequencer)
        case s1(S1Sequencer, purpose: S1Purpose)
        case done(SittingResult)
    }

    private var phase = Phase.s0
    /// The staged picture now on the desktop; `nil`: the original.
    private var picture: Appearance?
    private var pendingPicture: Appearance?
    private var current: SittingRequest?
    /// Each process's `«` observations, merged before `BControl` (Q14).
    private var observations = [[BObservation]]()

    public init() {}

    public mutating func next() -> SittingNext {
        switch phase {
        case .done(let result):
            // The original picture back whatever ended the sitting.
            return picture == nil ? .finished(result) : requestPicture(nil)
        case .s0:
            return run(Self.s0)
        case .sAdv(let sequencer):
            let step = sequencer.next()
            if let variant = step.variant, picture != variant.appearance { return requestPicture(variant.appearance) }
            switch step {
            case .sweep(let variant):
                return run(SittingRequest(kind: .sAdvSweep(variant), members: Self.sAdvMembers, menu: Self.sAdvMenu, name: "S-adv \(variant.name)"))
            case .chevron(let variant):
                return run(SittingRequest(kind: .sAdvChevron(variant), members: Self.sAdvMembers, menu: Self.sAdvMenu, name: "S-adv «"))
            case .finished(let outcome):
                switch Sitting.afterSAdv(outcome, bControl: BControl.evaluate(ChevronEpisodes.merged(observations))) {
                case .end(let result): phase = .done(result)
                case .proceed: phase = .s1(S1Sequencer(), purpose: .bracket)
                }
                return next()
            }
        case .s1(let sequencer, _):
            // D5.2: the original picture is restored before S1.
            if picture != nil { return requestPicture(nil) }
            switch sequencer.next() {
            case .finished(let verdict):
                phase = .done(Sitting.afterS1(verdict))
                return next()
            case .run(let profile, let purpose, let lengths):
                phase = .s1(sequencer, purpose: purpose)
                let kind: StepKind = purpose == .bracket ? .s1Bracket(lengths) : .s1Confirm(lengths[0])
                return run(SittingRequest(kind: kind, members: profile.k, menu: profile.menu, name: "S1 \(profile.id)"))
            }
        }
    }

    /// The verified report of the step `next()` last requested.
    public mutating func record(_ report: StepReport) {
        if report.status == .safetyStop {
            return end(.safetyStop("\(current?.name ?? "step"): \(report.reason ?? "safety stop")"))
        }
        switch phase {
        case .done:
            return
        case .s0:
            observations.append(report.chevronObservations.map(\.observation))
            guard let s0 = report.s0 else { return end(.failed("S0 not shown: \(report.reason ?? "no S0 report")")) }
            if case .end(let result) = Sitting.afterS0(s0.outcome, c3: s0.c3, section8: s0.section8) { return end(result) }
            phase = .sAdv(SAdvSequencer())
        case .sAdv(var sequencer):
            observations.append(report.chevronObservations.map(\.observation))
            sequencer.record(ReportReading.sweep(report))
            phase = .sAdv(sequencer)
        case .s1(var sequencer, let purpose):
            sequencer.record(ReportReading.s1(report, purpose: purpose))
            phase = .s1(sequencer, purpose: purpose)
        }
    }

    /// D5.2: whether the requested desktop picture was set. A failure ends the
    /// sitting (a failed restore at its end keeps the result already reached).
    public mutating func desktopPictureSet(_ ok: Bool) {
        if ok {
            picture = pendingPicture
            return
        }
        picture = nil
        if case .done = phase { return }
        end(.interrupted("the desktop picture could not be set (deviation 5 D5.2)"))
    }

    private mutating func requestPicture(_ appearance: Appearance?) -> SittingNext {
        pendingPicture = appearance
        return .setDesktopPicture(appearance)
    }

    /// The runner ended the step itself (console left, no verified report).
    public mutating func end(_ result: SittingResult) {
        phase = .done(result)
    }

    private mutating func run(_ request: SittingRequest) -> SittingNext {
        current = request
        return .run(request)
    }
}
