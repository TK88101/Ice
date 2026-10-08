import Testing
@testable import IceCore

/// When Ice hides the hidden section on macOS 27, and when it puts it back
/// (plan 2026-10-03-icebar-build, D1 and section 9.2). The machine never
/// touches the bar: these tests feed it events and read its commands.
@Suite("IceBarHidingMachine")
struct IceBarHidingMachineTests {
    // MARK: - Fixtures

    static func signature(hidden: [String] = ["h1", "h2"], frontmostPID: Int32 = 10) -> LayoutSignature {
        LayoutSignature(
            visible: ["v1"],
            hidden: hidden,
            alwaysHidden: [],
            frontmostPID: frontmostPID,
            menuMaxX: 400,
            displayID: 1,
            spaceID: 7
        )
    }

    static func sample(
        _ signature: LayoutSignature = signature(),
        menu: MenuWidthVerdict = .fits,
        interacting: Bool = false,
        dragging: Bool = false,
        boundaryUsable: Bool = true,
        iconLeftOfDivider: Bool = false
    ) -> IceBarHidingSample {
        IceBarHidingSample(
            signature: signature,
            menuVerdict: menu,
            isInteracting: interacting,
            isDragging: dragging,
            boundaryUsable: boundaryUsable,
            iconLeftOfDivider: iconLeftOfDivider
        )
    }

    /// A band: folded below `lo`, clean to `hi`, drawn above. T0's by default.
    static func band(_ lo: Double = 632, _ hi: Double = 840) -> @Sendable (Double) -> HiddenLengthOutcome {
        { length in
            if length < lo { return .folded }
            if length > hi { return .drawn }
            return .hiddenClean
        }
    }

    /// Feeds the machine and plays the bar: it keeps the length the commands
    /// set, and can answer baselines and observations from a world.
    struct Driver {
        var machine = IceBarHidingMachine()
        var now = 0.0
        var length: Double?
        var log = [IceBarHidingCommand]()
        /// The lengths observed, each with the bar's length at that moment.
        var observed = [(asked: Double, barLength: Double?)]()
        var baselines = 0
        var world: (Double) -> HiddenLengthOutcome = IceBarHidingMachineTests.band()
        var baselineOK = true
        /// When false, baselines and observations are left unanswered.
        var answers = true

        @discardableResult
        mutating func send(_ event: IceBarHidingEvent) -> [IceBarHidingCommand] {
            let (next, commands) = machine.step(event, now: now)
            machine = next
            log += commands
            for command in commands {
                switch command {
                case .setLength(let value):
                    length = value
                case .takeBaseline(let token):
                    baselines += 1
                    if answers { send(.baseline(token: token, ok: baselineOK)) }
                case .observe(let token, let asked):
                    observed.append((asked, length))
                    if answers { send(.observed(token: token, outcome: world(asked))) }
                case .report:
                    break
                }
            }
            return commands
        }

        @discardableResult
        mutating func tick(_ sample: IceBarHidingSample = IceBarHidingMachineTests.sample(), seconds: Double = 1) -> [IceBarHidingCommand] {
            now += seconds
            return send(.sample(sample))
        }

        mutating func ticks(_ count: Int, _ sample: IceBarHidingSample = IceBarHidingMachineTests.sample()) {
            for _ in 0..<count { tick(sample) }
        }

        /// IceBar mode on if it is off, then ticks until the machine rests or
        /// shows.
        mutating func settle(_ sample: IceBarHidingSample = IceBarHidingMachineTests.sample(), maxTicks: Int = 400) {
            if machine.phase == .off { send(.mode(isIceBar: true)) }
            for _ in 0..<maxTicks {
                tick(sample)
                switch machine.phase {
                case .resting, .shown: return
                default: continue
                }
            }
        }

        var lastStatus: IceBarHidingStatus? {
            for command in log.reversed() {
                if case .report(let status) = command { return status }
            }
            return nil
        }
    }

    // MARK: - Off and on

    @Test("the machine starts off and ignores everything but the mode")
    func startsOff() {
        var driver = Driver()
        #expect(driver.machine.phase == .off)
        #expect(driver.tick().isEmpty)
        #expect(driver.send(.baseline(token: 0, ok: true)).isEmpty)
        #expect(driver.send(.observed(token: 0, outcome: .hiddenClean)).isEmpty)
        #expect(driver.send(.chevronSeenAtRest).isEmpty)
        #expect(driver.send(.mode(isIceBar: false)).isEmpty)
        #expect(driver.machine.phase == .off)
    }

    @Test("IceBar mode on waits for a quiet period before anything is tried")
    func modeOnStartsQuiet() {
        var driver = Driver()
        let commands = driver.send(.mode(isIceBar: true))
        #expect(commands == [.report(.checking)])
        #expect(driver.machine.phase == .quiet(since: 0))
        driver.ticks(3)
        #expect(driver.baselines == 0)
        driver.ticks(2)
        #expect(driver.baselines == 1)
    }

    @Test("IceBar mode on twice changes nothing")
    func modeOnTwice() {
        var driver = Driver()
        driver.settle()
        #expect(driver.send(.mode(isIceBar: true)).isEmpty)
        #expect(driver.machine.phase == .resting(length: 736))
    }

    @Test("IceBar mode off restores the standard length")
    func modeOffRestores() {
        var driver = Driver()
        driver.settle()
        #expect(driver.length == 736)
        let commands = driver.send(.mode(isIceBar: false))
        #expect(commands == [.setLength(nil), .report(.off)])
        #expect(driver.machine.phase == .off)
        #expect(driver.length == nil)
    }

    // MARK: - Calibration

    @Test("T0's band is walked and rested at 736 pt")
    func walksT0Band() {
        var driver = Driver()
        driver.settle()
        #expect(driver.machine.phase == .resting(length: 736))
        #expect(driver.length == 736)
        #expect(driver.lastStatus == .active)
        #expect(driver.baselines == 1)
        // 736 down to the folded edge at 624, then up to the drawn edge at 848.
        #expect(driver.observed.map(\.asked).min() == 624)
        #expect(driver.observed.map(\.asked).max() == 848)
        #expect(driver.observed.count == 15)
        // Every observation is taken with the bar at the length asked about.
        #expect(driver.observed.allSatisfy { $0.asked == $0.barLength })
    }

    @Test("every trial is a jump from the standard length")
    func trialsJumpFromRest() {
        var driver = Driver()
        driver.settle()
        var current: Double?
        var lengthBeforeLastSet: Double?
        var previous: IceBarHidingCommand?
        var trials = 0
        var jumpsFromRest = 0
        for command in driver.log {
            if case .setLength(let value) = command {
                lengthBeforeLastSet = current
                current = value
            }
            if case .observe = command {
                trials += 1
                if case .setLength(_?)? = previous, lengthBeforeLastSet == nil { jumpsFromRest += 1 }
            }
            previous = command
        }
        #expect(trials == 15)
        #expect(jumpsFromRest == trials)
    }

    @Test("a trial waits for the rest dwell after the previous one")
    func trialsAreSpacedByTheDwell() {
        var driver = Driver()
        driver.send(.mode(isIceBar: true))
        driver.ticks(5)
        #expect(driver.observed.count == 1)
        driver.tick(seconds: 0.5)
        #expect(driver.observed.count == 1)
        driver.tick(seconds: 0.5)
        #expect(driver.observed.count == 2)
    }

    @Test("no calibration starts before the hidden boundary decided the sections")
    func waitsForBoundary() {
        var driver = Driver()
        driver.send(.mode(isIceBar: true))
        driver.ticks(20, Self.sample(boundaryUsable: false))
        #expect(driver.baselines == 0)
        driver.tick()
        #expect(driver.baselines == 1)
    }

    @Test("no calibration starts while the user is on the bar")
    func waitsForInteractionToEnd() {
        var driver = Driver()
        driver.send(.mode(isIceBar: true))
        driver.ticks(20, Self.sample(interacting: true))
        #expect(driver.baselines == 0)
        driver.tick()
        #expect(driver.baselines == 1)
    }

    @Test("interaction during a calibration puts the section back")
    func interactionAborts() {
        var driver = Driver()
        driver.send(.mode(isIceBar: true))
        driver.ticks(6)
        #expect(driver.observed.count >= 1)
        driver.answers = false
        driver.tick()
        #expect(driver.length != nil)
        driver.tick(Self.sample(interacting: true))
        #expect(driver.length == nil)
        #expect(driver.machine.phase == .quiet(since: driver.now))
    }

    // MARK: - Showing instead

    @Test("a frontmost app whose menus reach the notch shows the section", arguments: [
        (MenuWidthVerdict.crossesNotch, IceBarShownReason.longMenu),
        (MenuWidthVerdict.unreadable, IceBarShownReason.menuUnreadable),
    ])
    func longMenuShows(verdict: MenuWidthVerdict, reason: IceBarShownReason) {
        var driver = Driver()
        driver.settle()
        let commands = driver.tick(Self.sample(menu: verdict))
        #expect(commands.contains(.setLength(nil)))
        #expect(driver.machine.phase == .shown(reason))
        #expect(driver.lastStatus == .shown(reason))
        #expect(driver.length == nil)
    }

    // MARK: - Ice's icon left of its divider (plan 2026-10-07-icebar-preference-hiding, T2c)

    /// A machine brought to each phase a sample can meet, by name.
    static func driver(in phase: String) -> Driver {
        var driver = Driver()
        switch phase {
        case "quiet":
            driver.send(.mode(isIceBar: true))
        case "baselining":
            driver.answers = false
            driver.send(.mode(isIceBar: true))
            driver.ticks(4)
        case "calibrating":
            driver.send(.mode(isIceBar: true))
            driver.ticks(4)
        case "trial":
            driver.send(.mode(isIceBar: true))
            driver.ticks(4)
            driver.answers = false
            driver.ticks(2)
        case "confirming":
            driver.settle()
            driver.tick(sample(dragging: true))
            driver.now += 60
            // The baseline is answered, the observation of the remembered length is not.
            driver.answers = false
            driver.ticks(4)
            if case .baselining(let token) = driver.machine.phase {
                driver.send(.baseline(token: token, ok: true))
            }
        case "resting":
            driver.settle()
        case "shownForAnotherReason":
            driver.settle()
            driver.tick(sample(menu: .crossesNotch))
        case "unstable":
            driver.world = { _ in .unknown }
            for _ in 0..<3 {
                driver.settle()
                driver.now += 60
                driver.tick()
            }
        default:
            Issue.record("no such phase: \(phase)")
        }
        return driver
    }

    @Test("the fixture reaches the phase it names")
    func fixturePhases() {
        func isPhase(_ name: String, _ matches: (IceBarHidingMachine.Phase) -> Bool) -> Bool {
            matches(Self.driver(in: name).machine.phase)
        }
        #expect(isPhase("quiet") { if case .quiet = $0 { true } else { false } })
        #expect(isPhase("baselining") { if case .baselining = $0 { true } else { false } })
        #expect(isPhase("calibrating") { if case .calibrating(_, nil, _) = $0 { true } else { false } })
        #expect(isPhase("trial") { if case .calibrating(_, .some, _) = $0 { true } else { false } })
        #expect(isPhase("confirming") { if case .confirming = $0 { true } else { false } })
        #expect(isPhase("resting") { if case .resting = $0 { true } else { false } })
        #expect(isPhase("shownForAnotherReason") { $0 == .shown(.longMenu) })
        #expect(isPhase("unstable") { $0 == .shown(.unstableLayout) })
    }

    @Test("Ice's icon left of its divider puts the section back and says so, from every phase", arguments: [
        "quiet", "baselining", "calibrating", "trial", "confirming", "resting", "shownForAnotherReason", "unstable",
    ])
    func iconLeftOfDividerShows(phase: String) {
        var driver = Self.driver(in: phase)
        let commands = driver.tick(Self.sample(iconLeftOfDivider: true))
        #expect(commands.contains(.setLength(nil)))
        #expect(commands.last == .report(.shown(.iconLeftOfDivider)))
        #expect(driver.machine.phase == .shown(.iconLeftOfDivider))
        #expect(driver.length == nil)
    }

    @Test("it comes before every other reason to show the section", arguments: [
        MenuWidthVerdict.crossesNotch, .unreadable,
    ])
    func iconLeftOfDividerComesFirst(verdict: MenuWidthVerdict) {
        var driver = Driver()
        driver.settle()
        driver.tick(Self.sample(Self.signature(hidden: []), menu: verdict, iconLeftOfDivider: true))
        #expect(driver.machine.phase == .shown(.iconLeftOfDivider))
    }

    @Test("while it lasts nothing is tried and nothing is said twice")
    func iconLeftOfDividerHolds() {
        var driver = Driver()
        driver.settle()
        driver.tick(Self.sample(iconLeftOfDivider: true))
        let baselines = driver.baselines
        driver.now += 600
        var later = [IceBarHidingCommand]()
        for _ in 0..<10 { later += driver.tick(Self.sample(iconLeftOfDivider: true)) }
        #expect(later.isEmpty)
        #expect(driver.baselines == baselines)
        #expect(driver.length == nil)
    }

    @Test("once the icon is right of the divider again the machine waits out the quiet period, then hides")
    func iconLeftOfDividerClears() {
        var driver = Driver()
        driver.settle()
        driver.tick(Self.sample(iconLeftOfDivider: true))
        let commands = driver.tick()
        #expect(commands == [.setLength(nil), .report(.checking)])
        #expect(driver.machine.phase == .quiet(since: driver.now))
        driver.now += 60
        driver.settle()
        #expect(driver.machine.phase == .resting(length: 736))
    }

    @Test("a drag under way is the owner arranging: quiet, not the notice, until it ends")
    func iconLeftOfDividerDuringDrag() {
        var driver = Driver()
        driver.settle()
        driver.tick(Self.sample(dragging: true, iconLeftOfDivider: true))
        #expect(driver.machine.phase == .quiet(since: driver.now))
        driver.tick(Self.sample(iconLeftOfDivider: true))
        #expect(driver.machine.phase == .shown(.iconLeftOfDivider))
    }

    @Test("its status line is the notice's text, with nothing added")
    func iconLeftOfDividerMessage() {
        #expect(IceBarHidingStatus.shown(.iconLeftOfDivider).message == IcePlacementNotice.iconLeftOfDivider.message)
    }

    @Test("short menus again hide the section after the quiet period")
    func shortMenusHideAgain() {
        var driver = Driver()
        driver.settle()
        driver.tick(Self.sample(menu: .crossesNotch))
        driver.tick()
        #expect(driver.machine.phase == .quiet(since: driver.now))
        driver.now += 60
        driver.settle()
        #expect(driver.machine.phase == .resting(length: 736))
    }

    @Test("an empty hidden section is shown as such and nothing is tried")
    func noMembersShows() {
        var driver = Driver()
        driver.settle(Self.sample(Self.signature(hidden: [])))
        #expect(driver.machine.phase == .shown(.noMembers))
        #expect(driver.baselines == 0)
    }

    @Test("a baseline that could not cover every member shows the section")
    func failedBaselineShows() {
        var driver = Driver()
        driver.baselineOK = false
        driver.settle()
        #expect(driver.machine.phase == .shown(.cannotAssess))
        #expect(driver.lastStatus == .shown(.cannotAssess))
        #expect(driver.observed.isEmpty)
        #expect(driver.length == nil)
    }

    @Test("an unknown outcome shows the section at once")
    func unknownOutcomeShows() {
        var driver = Driver()
        driver.world = { _ in .unknown }
        driver.settle()
        #expect(driver.machine.phase == .shown(.cannotAssess))
        #expect(driver.observed.count == 1)
        #expect(driver.length == nil)
    }

    @Test("folded on one side and drawn on the other shows the section")
    func noBandShows() {
        var driver = Driver()
        driver.world = { $0 < 760 ? .folded : .drawn }
        driver.settle()
        #expect(driver.machine.phase == .shown(.noCleanLength(.noBand)))
        #expect(driver.length == nil)
    }

    @Test("a band too narrow for the rest margin is not rested in")
    func narrowBandShows() {
        var driver = Driver()
        // Clean at 720, 736 and 752 only: the midpoint has 16 pt either side.
        driver.world = Self.band(720, 752)
        driver.settle()
        #expect(driver.machine.phase == .shown(.noCleanLength(.noBand)))
        #expect(driver.length == nil)
    }

    @Test("a band just wide enough for the rest margin is rested in")
    func marginBandRests() {
        var driver = Driver()
        // Clean from 704 to 768: 32 pt either side of 736.
        driver.world = Self.band(704, 768)
        driver.settle()
        #expect(driver.machine.phase == .resting(length: 736))
    }

    // MARK: - Invalidation

    @Test("a new layout signature restores the standard length at once, in every phase")
    func signatureChangeRestores() {
        let other = Self.sample(Self.signature(hidden: ["h1", "h2", "h3"]))

        var resting = Driver()
        resting.settle()
        #expect(resting.tick(other).first == .setLength(nil))
        #expect(resting.machine.phase == .quiet(since: resting.now))

        var baselining = Driver()
        baselining.answers = false
        baselining.send(.mode(isIceBar: true))
        baselining.ticks(5)
        #expect(baselining.baselines == 1)
        baselining.tick(other)
        #expect(baselining.machine.phase == .quiet(since: baselining.now))

        var trying = Driver()
        trying.send(.mode(isIceBar: true))
        trying.ticks(5)
        trying.answers = false
        trying.ticks(2)
        #expect(trying.length != nil)
        trying.tick(other)
        #expect(trying.length == nil)
        #expect(trying.machine.phase == .quiet(since: trying.now))

        var shown = Driver()
        shown.baselineOK = false
        shown.settle()
        shown.tick(other)
        #expect(shown.machine.phase == .quiet(since: shown.now))
    }

    @Test("a result for an abandoned baseline is ignored")
    func staleBaselineIsIgnored() {
        var driver = Driver()
        driver.answers = false
        driver.send(.mode(isIceBar: true))
        driver.ticks(5)
        guard case .baselining(let token) = driver.machine.phase else {
            Issue.record("expected baselining, got \(driver.machine.phase)")
            return
        }
        #expect(driver.send(.baseline(token: token + 1, ok: true)).isEmpty)
        #expect(driver.machine.phase == .baselining(token: token))

        // A signature change abandons the baseline; its late answer changes nothing.
        driver.tick(Self.sample(Self.signature(frontmostPID: 11)))
        let phase = driver.machine.phase
        #expect(driver.send(.baseline(token: token, ok: true)).isEmpty)
        #expect(driver.send(.observed(token: token, outcome: .hiddenClean)).isEmpty)
        #expect(driver.machine.phase == phase)
    }

    @Test("an observation for an abandoned trial is ignored")
    func staleObservationIsIgnored() {
        var driver = Driver()
        driver.send(.mode(isIceBar: true))
        driver.ticks(4)
        driver.answers = false
        driver.ticks(3)
        guard case .calibrating(_, let pending?, _) = driver.machine.phase else {
            Issue.record("expected a pending trial, got \(driver.machine.phase)")
            return
        }
        let phase = driver.machine.phase
        #expect(driver.send(.observed(token: pending.token + 1, outcome: .hiddenClean)).isEmpty)
        #expect(driver.machine.phase == phase)
        driver.send(.mode(isIceBar: false))
        #expect(driver.send(.observed(token: pending.token, outcome: .hiddenClean)).isEmpty)
        #expect(driver.machine.phase == .off)
    }

    @Test("a Command-drag at rest puts the section back so it can be arranged")
    func dragRestores() {
        var driver = Driver()
        driver.settle()
        let commands = driver.tick(Self.sample(dragging: true))
        #expect(commands.first == .setLength(nil))
        #expect(driver.machine.phase == .quiet(since: driver.now))
        // Still dragging: the quiet period keeps restarting.
        driver.ticks(10, Self.sample(dragging: true))
        #expect(driver.machine.phase == .quiet(since: driver.now))
        #expect(driver.baselines == 1)
    }

    @Test("a chevron seen at rest puts the section back and forgets the length")
    func chevronAtRestRestores() {
        var driver = Driver()
        driver.settle()
        let trialsBefore = driver.observed.count
        let commands = driver.send(.chevronSeenAtRest)
        #expect(commands.first == .setLength(nil))
        #expect(driver.machine.phase == .quiet(since: driver.now))
        driver.now += 60
        driver.settle()
        // A full calibration again, not a one-observation confirmation.
        #expect(driver.observed.count == trialsBefore + 15)
    }

    @Test("a chevron event outside rest is ignored")
    func chevronOutsideRestIsIgnored() {
        var driver = Driver()
        driver.send(.mode(isIceBar: true))
        #expect(driver.send(.chevronSeenAtRest).isEmpty)
    }

    // MARK: - Reuse and rate limit

    @Test("a signature seen before is confirmed with one observation")
    func cachedLengthIsConfirmed() {
        let other = Self.sample(Self.signature(frontmostPID: 11))
        var driver = Driver()
        driver.settle()
        driver.now += 60
        driver.settle(other)
        let trialsBefore = driver.observed.count
        let baselinesBefore = driver.baselines
        driver.now += 60
        driver.settle()
        #expect(driver.machine.phase == .resting(length: 736))
        #expect(driver.observed.count == trialsBefore + 1)
        #expect(driver.observed.last?.asked == 736)
        #expect(driver.observed.last?.barLength == 736)
        #expect(driver.baselines == baselinesBefore + 1)
    }

    @Test("a cached length that no longer hides cleanly is dropped and the band walked again")
    func refusedConfirmationRecalibrates() {
        let other = Self.sample(Self.signature(frontmostPID: 11))
        var driver = Driver()
        driver.settle()
        driver.now += 60
        driver.settle(other)
        driver.now += 60
        let trialsBefore = driver.observed.count
        // The band moved up: 736 pt now folds.
        driver.world = Self.band(760, 904)
        driver.settle()
        #expect(driver.observed[trialsBefore].asked == 736)
        guard case .resting(let length) = driver.machine.phase else {
            Issue.record("expected resting, got \(driver.machine.phase)")
            return
        }
        #expect(length >= 760 + 32)
        #expect(length <= 904 - 32)
        // The refused confirmation is the walk's first observation, not repeated.
        #expect(driver.observed[(trialsBefore + 1)...].allSatisfy { $0.asked != 736 })
    }

    @Test("calibrations start no closer together than the minimum interval")
    func minimumInterval() {
        var driver = Driver()
        driver.baselineOK = false
        driver.settle()
        #expect(driver.baselines == 1)
        let failedAt = driver.now
        driver.ticks(20)
        #expect(driver.baselines == 1)
        while driver.baselines == 1, driver.now < failedAt + 120 { driver.tick() }
        #expect(driver.baselines == 2)
        #expect(driver.now - failedAt >= 30)
    }

    @Test("three failed calibrations for one signature stop the trying")
    func repeatedFailuresStop() {
        var driver = Driver()
        driver.baselineOK = false
        driver.send(.mode(isIceBar: true))
        driver.ticks(400)
        #expect(driver.baselines == 3)
        #expect(driver.machine.phase == .shown(.unstableLayout))
        #expect(driver.lastStatus == .shown(.unstableLayout))

        // A new signature may be tried again.
        driver.baselineOK = true
        driver.settle(Self.sample(Self.signature(frontmostPID: 11)))
        #expect(driver.machine.phase == .resting(length: 736))
    }

    @Test("the remembered lengths are bounded")
    func cacheIsBounded() {
        var driver = Driver()
        let parameters = IceBarHidingParameters.standard
        for pid in 0..<Int32(parameters.maxCachedLengths + 2) {
            driver.now += 60
            driver.settle(Self.sample(Self.signature(frontmostPID: 100 + pid)))
            #expect(driver.machine.phase == .resting(length: 736))
        }
        #expect(driver.machine.cachedLengthCount <= parameters.maxCachedLengths)
    }

    // MARK: - Status

    @Test("every status but off has its own line for the layout pane")
    func statusMessages() {
        #expect(IceBarHidingStatus.off.message == nil)
        let statuses: [IceBarHidingStatus] = [
            .checking, .active,
            .shown(.longMenu), .shown(.menuUnreadable), .shown(.noMembers), .shown(.cannotAssess),
            .shown(.noCleanLength(.noBand)), .shown(.unstableLayout), .shown(.iconLeftOfDivider),
        ]
        let messages = statuses.compactMap(\.message)
        #expect(messages.count == statuses.count)
        #expect(Set(messages).count == statuses.count)
        #expect(messages.allSatisfy { !$0.isEmpty })
    }
}
