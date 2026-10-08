import Testing
@testable import IceCore

/// When Ice hides the chosen items on macOS 27, what it says of them, and the
/// few ways it puts them back (plan 2026-10-07-icebar-preference-hiding, S3
/// and its T3b design). The machine never touches the bar: these tests feed
/// it events and read its commands.
@Suite("IceBarHidingMachine")
struct IceBarHidingMachineTests {
    // MARK: - Fixtures

    static let clean = SectionItemCheck.checked(.hidden(folded: false))
    static let folded = SectionItemCheck.checked(.hidden(folded: true))
    static let drawn = SectionItemCheck.checked(.stillDrawn)

    static func key(_ pid: Int32) -> ItemKey {
        ItemKey(namespace: "com.example.app\(pid)", identifier: "item", pid: pid, childIndex: nil)
    }

    static func member(_ pid: Int32, _ condition: PreferenceHidingMemberCondition = .ready) -> PreferenceHidingMember {
        PreferenceHidingMember(tag: key(pid).tagKey(isSelf: false), key: key(pid), condition: condition)
    }

    static func roster(_ members: [PreferenceHidingMember] = [member(1), member(2)]) -> PreferenceHidingMembership {
        PreferenceHidingMembership(members: members, blockers: [])
    }

    static func signature(
        items: [String] = ["v1", "m1", "m2"],
        members: [String] = ["m1", "m2"],
        frontmostPID: Int32 = 10,
        menuMaxX: Double? = 400,
        displayID: UInt32 = 1,
        spaceID: UInt64 = 7
    ) -> LayoutSignature {
        fixtureSignature(items: items, members: members, frontmostPID: frontmostPID, menuMaxX: menuMaxX, displayID: displayID, spaceID: spaceID)
    }

    static func sample(
        _ signature: LayoutSignature = signature(),
        preconditions: PreferenceHidingPreconditionResult = .ok,
        membership: PreferenceHidingMembership = roster(),
        interacting: Bool = false,
        dragging: Bool = false,
        boundaryUsable: Bool = true
    ) -> IceBarHidingSample {
        IceBarHidingSample(
            signature: signature, preconditions: preconditions, membership: membership,
            isInteracting: interacting, isDragging: dragging, boundaryUsable: boundaryUsable
        )
    }

    /// Every precondition failing in turn (D-c a, b, c).
    static let blocks: [PreferenceHidingPreconditionResult] = [
        .blocked([.iceIconNotRightOfDivider(.iconLeftOfDivider)]),
        .blocked([.iceIconNotRightOfDivider(.iconUnreadable)]),
        .blocked([.discoveryIncomplete(.incomplete(failedPIDs: [5]))]),
        .blocked([.discoveryIncomplete(.permissionDenied)]),
        .blocked([.positionalItemsLeftOfDivider([PreferenceHidingBlocker(key: key(9), tag: key(9).tagKey(isSelf: false), name: nil)])]),
    ]

    /// A band: members folded below `lo`, absent to `hi`, drawn above. T0's by default.
    static func band(_ lo: Double = 632, _ hi: Double = 840) -> @Sendable (Double) -> SectionItemCheck {
        { length in
            if length < lo { return folded }
            if length > hi { return drawn }
            return clean
        }
    }

    /// Feeds the machine and plays the bar: it keeps the length the commands
    /// set, and answers baselines and observations from a world.
    struct Driver {
        var machine = IceBarHidingMachine()
        var now = 0.0
        var length: Double?
        var log = [IceBarHidingCommand]()
        /// The lengths observed, each with the bar's length at that moment.
        var observed = [(asked: Double, barLength: Double?)]()
        var baselines = 0
        /// What each member's check says at a length.
        var world: (Double) -> SectionItemCheck = IceBarHidingMachineTests.band()
        var baselineOK = true
        var chevron: Bool? = false
        /// When false, baselines and observations are left unanswered.
        var answers = true
        var members = IceBarHidingMachineTests.roster()

        @discardableResult
        mutating func send(_ event: IceBarHidingEvent) -> [IceBarHidingCommand] {
            let (next, commands) = machine.step(event, now: now)
            machine = next
            log += commands
            for command in commands {
                switch command {
                case .setLength(let value):
                    length = value
                case .takeBaseline(let token, _, _):
                    baselines += 1
                    if answers { send(.baseline(token: token, ok: baselineOK)) }
                case .observe(let token, let asked):
                    observed.append((asked, length))
                    if answers { send(.observed(token: token, checks: checks(at: asked), chevronListed: chevron)) }
                case .report:
                    break
                }
            }
            return commands
        }

        func checks(at length: Double) -> [ItemKey: SectionItemCheck] {
            Dictionary(uniqueKeysWithValues: members.members.compactMap(\.key).map { ($0, world(length)) })
        }

        @discardableResult
        mutating func tick(_ sample: IceBarHidingSample? = nil, seconds: Double = 1) -> [IceBarHidingCommand] {
            now += seconds
            return send(.sample(sample ?? IceBarHidingMachineTests.sample(membership: members)))
        }

        mutating func run(_ sample: IceBarHidingSample? = nil, ticks: Int) {
            for _ in 0..<ticks { tick(sample) }
        }

        /// IceBar mode on, then ticks enough for any calibration to end.
        mutating func settle(_ sample: IceBarHidingSample? = nil, ticks: Int = 60) {
            send(.mode(isIceBar: true))
            run(sample, ticks: ticks)
        }

        var reports: [IceBarHidingStatus] {
            log.compactMap { if case .report(let status) = $0 { status } else { nil } }
        }

        var state: PreferenceHidingState? {
            if case .state(let state) = machine.status { state } else { nil }
        }

        var restLength: Double? {
            if case .resting(let rest) = machine.phase { rest.length } else { nil }
        }

        /// Commands logged since `mark`.
        func since(_ mark: Int) -> [IceBarHidingCommand] { Array(log[mark...]) }
    }

    // MARK: - Mode

    @Test("off until IceBar mode is on; then getting ready, at standard length")
    func modeOn() {
        var driver = Driver()
        #expect(driver.machine.status == .off)
        let commands = driver.send(.mode(isIceBar: true))
        #expect(commands == [.report(.state(.requestedNotVerified(reasons: [.lengthNotApplied])))])
        #expect(!driver.machine.lengthApplied)
    }

    @Test("a sample before IceBar mode does nothing")
    func sampleWhileOff() {
        var driver = Driver()
        #expect(driver.tick().isEmpty)
    }

    @Test("leaving IceBar mode from a rest retires the length, then reports off")
    func modeOffFromRest() {
        var driver = Driver()
        driver.settle()
        #expect(driver.restLength != nil)
        #expect(driver.send(.mode(isIceBar: false)) == [.setLength(nil), .report(.off)])
        #expect(driver.machine.phase == .off)
    }

    @Test("a late answer after the mode was toggled matches no new request: tokens never restart")
    func tokensNeverRestart() {
        var driver = Driver()
        driver.answers = false
        driver.settle(ticks: 4)
        guard case .takeBaseline(let old, _, _)? = driver.log.last(where: { if case .takeBaseline = $0 { true } else { false } }) else {
            Issue.record("no baseline asked"); return
        }
        driver.send(.mode(isIceBar: false))
        driver.send(.mode(isIceBar: true))
        driver.now += 100
        driver.run(ticks: 4)
        guard case .baselining(let fresh) = driver.machine.phase else { Issue.record("not baselining"); return }
        #expect(fresh != old)
        #expect(driver.send(.baseline(token: old, ok: true)).isEmpty)
    }

    // MARK: - Reaching a rest

    @Test("a quiet bar is baselined after the quiet period, never before")
    func quietPeriod() {
        var driver = Driver()
        driver.answers = false
        driver.send(.mode(isIceBar: true))
        driver.run(ticks: 2)
        #expect(driver.baselines == 0)
        driver.tick()
        #expect(driver.baselines == 1)
    }

    @Test("a first run walks the band, settles once at its midpoint and rests verified")
    func firstRunVerifies() {
        var driver = Driver()
        driver.settle()
        #expect(driver.restLength == 736)
        #expect(driver.length == 736)
        #expect(driver.state == .verifiedHidden)
        #expect(driver.machine.lengthApplied)
        // Every observation was taken at the length it asked for.
        #expect(driver.observed.allSatisfy { $0.asked == $0.barLength })
        // The walk's trials end back at standard length; only the last one stays.
        #expect(driver.observed.last?.asked == 736)
    }

    @Test("every trial of a walk is a jump from standard length (T0)")
    func trialsJumpFromRest() {
        var driver = Driver()
        driver.settle()
        var previous: Double? = nil
        for command in driver.log {
            guard case .setLength(let value) = command else { continue }
            if value != nil { #expect(previous == nil) }
            previous = value
        }
    }

    @Test("an empty roster is never baselined: nothing is left of the divider")
    func emptyRoster() {
        var driver = Driver()
        driver.members = Self.roster([])
        driver.settle(ticks: 20)
        #expect(driver.baselines == 0)
        #expect(driver.state == .requestedNotVerified(reasons: [.lengthNotApplied, .noMembers]))
        #expect(driver.length == nil)
    }

    @Test("the baseline is asked for the roster the machine sampled: its tags, and the ready members' keys")
    func baselineCarriesTheRoster() {
        var driver = Driver()
        driver.members = Self.roster([Self.member(1), Self.member(2, .stacked)])
        driver.answers = false
        driver.settle(ticks: 3)
        guard case .takeBaseline(_, let members, let ready)? = driver.log.last else { Issue.record("no baseline asked"); return }
        #expect(members == [Self.member(1).tag, Self.member(2).tag])
        #expect(ready == [Self.key(1)])
    }

    @Test("a drag or an item change while already quiet starts the quiet period again (Codex review, T3b round 1)", arguments: [
        sample(dragging: true), sample(signature(items: ["v1", "v2", "m1", "m2"])),
    ])
    func quietRestarts(interruption: IceBarHidingSample) {
        var driver = Driver()
        driver.answers = false
        driver.send(.mode(isIceBar: true))
        driver.run(Self.sample(boundaryUsable: false), ticks: 10)
        driver.tick(interruption)
        let after = interruption.isDragging ? Self.sample() : interruption
        driver.run(after, ticks: 2)
        #expect(driver.baselines == 0)
        driver.tick(after)
        #expect(driver.baselines == 1)
    }

    @Test("no baseline before a pass has placed the sections by the divider at standard length")
    func boundaryNotUsable() {
        var driver = Driver()
        driver.settle(Self.sample(boundaryUsable: false), ticks: 20)
        #expect(driver.baselines == 0)
        driver.tick()
        #expect(driver.baselines == 1)
    }

    @Test("no baseline while the pointer is in the bar or the IceBar is up")
    func interactionDelaysStart() {
        var driver = Driver()
        driver.settle(Self.sample(interacting: true), ticks: 20)
        #expect(driver.baselines == 0)
    }

    // MARK: - O1: hiding best effort when it cannot be verified (N4)

    @Test("a baseline that does not cover the members hides anyway, at the lab's first length, and says not verified")
    func uncoveredBaselineHidesBestEffort() {
        var driver = Driver()
        driver.baselineOK = false
        driver.world = { _ in .skipped(.noReference) }
        driver.settle()
        #expect(driver.restLength == IceBarHidingParameters.standard.calibration.defaultStart)
        #expect(driver.observed.count == 1, "no walk without a baseline")
        guard case .requestedNotVerified(let reasons)? = driver.state else { Issue.record("not 'not verified'"); return }
        #expect(reasons.contains(.noReference))
        #expect(!reasons.contains(.lengthNotApplied))
        #expect(driver.state?.countsAsLabSuccess == false)
    }

    @Test("a walk that finds no absent length hides best effort and says what it saw")
    func failedWalkHidesBestEffort() {
        var driver = Driver()
        driver.world = { _ in Self.folded }
        driver.settle(ticks: 120)
        #expect(driver.restLength == IceBarHidingParameters.standard.calibration.defaultStart)
        #expect(driver.state == .requestedNotVerified(reasons: [.foldSeen([Self.member(1).tag, Self.member(2).tag])]))
    }

    @Test("a walk that only ever sees the members drawn rests and says visible / failed, not hidden")
    func alwaysDrawnIsFailed() {
        var driver = Driver()
        driver.world = { _ in Self.drawn }
        driver.settle(ticks: 120)
        #expect(driver.restLength != nil)
        #expect(driver.state == .visibleFailed(drawn: [Self.member(1).tag, Self.member(2).tag]))
    }

    @Test("a check that cannot be read ends the walk at once, best effort, at the midpoint of what was seen absent")
    func unknownEndsTheWalkAtCleanMidpoint() {
        var driver = Driver()
        // 736 and 720 absent, then nothing readable.
        driver.world = { length in length >= 720 && length <= 736 ? Self.clean : .checked(.unverifiable(.captureUnstable)) }
        driver.settle()
        #expect(driver.restLength == 728)
    }

    @Test("stale and stacked members cap the state, they do not stop the walk for the others")
    func staleMembersDoNotStopTheWalk() {
        var driver = Driver()
        driver.members = Self.roster([Self.member(1), Self.member(2, .stacked), Self.member(3, .stale(.missingFromRead))])
        driver.world = Self.band()
        driver.settle()
        #expect(driver.restLength == 736)
        #expect(driver.observed.count > 1, "the walk ran")
        guard case .requestedNotVerified(let reasons)? = driver.state else { Issue.record("capped states are not verified"); return }
        #expect(reasons.contains(.stackedMembers([Self.member(2).tag])))
        #expect(reasons.contains(.staleMembers([Self.member(3).tag])))
    }

    // MARK: - The last verified length

    @Test("after a rest was retired, the last verified length is settled at first: one observation, no walk")
    func lastGoodIsTriedFirst() {
        var driver = Driver()
        driver.settle()
        let before = driver.observed.count
        driver.tick(Self.sample(dragging: true))
        driver.now += 100
        driver.run(ticks: 8)
        #expect(driver.restLength == 736)
        #expect(driver.observed.count == before + 1)
        #expect(driver.state == .verifiedHidden)
    }

    @Test("a last verified length that no longer hides starts a walk from that observation")
    func refusedLastGoodWalks() {
        var driver = Driver()
        driver.settle()
        driver.world = Self.band(800, 1000)
        driver.tick(Self.sample(dragging: true))
        driver.now += 100
        driver.run(ticks: 60)
        #expect(driver.restLength == 896)
        #expect(driver.state == .verifiedHidden)
    }

    // MARK: - D-e: layout changes (N1, N2)

    @Test("a frontmost app, menu width or Space change at rest keeps the length and drops to not verified", arguments: [
        (signature(frontmostPID: 11), PreferenceHidingLayoutChange.frontmostAppChanged),
        (signature(menuMaxX: 1400), .menuWidthChanged),
        (signature(menuMaxX: nil), .menuWidthChanged),
        (signature(spaceID: 8), .spaceChanged),
    ])
    func softChangeKeepsTheLength(changed: LayoutSignature, change: PreferenceHidingLayoutChange) {
        var driver = Driver()
        driver.settle()
        let mark = driver.log.count
        driver.tick(Self.sample(changed))
        #expect(driver.restLength == 736)
        #expect(driver.length == 736)
        #expect(driver.since(mark) == [.report(.state(.requestedNotVerified(reasons: [.layoutChangePending(change)])))])
    }

    @Test("the re-check after a soft change is one observation at the same length, after the quiet period, and verifies again")
    func softChangeIsRechecked() {
        var driver = Driver()
        driver.settle()
        let before = driver.observed.count
        let changed = Self.sample(Self.signature(frontmostPID: 11))
        driver.run(changed, ticks: 3)
        #expect(driver.observed.count == before)
        driver.tick(changed)
        #expect(driver.observed.count == before + 1)
        #expect(driver.observed.last?.asked == 736)
        #expect(driver.state == .verifiedHidden)
        #expect(!driver.log.dropFirst(driver.log.count - 3).contains(.setLength(nil)))
        driver.run(changed, ticks: 10)
        #expect(driver.observed.count == before + 1, "one re-check per change")
    }

    @Test("a re-check waits while the pointer is in the bar or the IceBar is up")
    func recheckWaitsForInteraction() {
        var driver = Driver()
        driver.settle()
        let before = driver.observed.count
        let changed = Self.signature(frontmostPID: 11)
        driver.run(Self.sample(changed, interacting: true), ticks: 10)
        #expect(driver.observed.count == before)
        #expect(driver.restLength == 736)
        driver.tick(Self.sample(changed))
        #expect(driver.observed.count == before + 1)
    }

    @Test("a soft change during a re-check restarts the wait: the answer under way is not taken for the new layout")
    func softChangeDuringRecheck() {
        var driver = Driver()
        driver.settle()
        driver.answers = false
        driver.run(Self.sample(Self.signature(frontmostPID: 11)), ticks: 4)
        guard case .observe(let token, _)? = driver.log.last else { Issue.record("no re-check asked"); return }
        driver.tick(Self.sample(Self.signature(frontmostPID: 12)))
        driver.send(.observed(token: token, checks: driver.checks(at: 736), chevronListed: false))
        #expect(driver.state == .requestedNotVerified(reasons: [.layoutChangePending(.frontmostAppChanged)]))
    }

    @Test("a soft change before any rest restarts the quiet period")
    func softChangeBeforeRest() {
        var driver = Driver()
        driver.answers = false
        driver.send(.mode(isIceBar: true))
        driver.run(ticks: 2)
        driver.tick(Self.sample(Self.signature(frontmostPID: 11)))
        driver.run(Self.sample(Self.signature(frontmostPID: 11)), ticks: 2)
        #expect(driver.baselines == 0)
        driver.tick(Self.sample(Self.signature(frontmostPID: 11)))
        #expect(driver.baselines == 1)
    }

    @Test("an item or display change at rest retires the length: the roster may be wrong and advances only at standard length", arguments: [
        signature(items: ["v1", "v2", "m1", "m2"]), signature(members: ["m1"]), signature(displayID: 2),
    ])
    func structuralChangeRetires(changed: LayoutSignature) {
        var driver = Driver()
        driver.settle()
        let mark = driver.log.count
        driver.tick(Self.sample(changed))
        #expect(driver.since(mark) == [.setLength(nil), .report(.state(.requestedNotVerified(reasons: [.lengthNotApplied])))])
        #expect(driver.length == nil)
    }

    @Test("a baseline too old to read is not re-taken by showing the section: the length stays, not verified")
    func staleBaselineNeverShows() {
        var driver = Driver()
        driver.settle()
        driver.world = { _ in .skipped(.baselineStale) }
        let mark = driver.log.count
        driver.run(Self.sample(Self.signature(frontmostPID: 11)), ticks: 40)
        #expect(!driver.since(mark).contains(.setLength(nil)))
        #expect(driver.restLength == 736)
        #expect(driver.state == .requestedNotVerified(reasons: [.membersUnchecked([Self.member(1).tag, Self.member(2).tag])]))
    }

    // MARK: - D-b: the chevron (N3)

    @Test("a listed chevron changes nothing: the length verifies, and the reading is recorded", arguments: [true, false, nil] as [Bool?])
    func chevronIsRecordedOnly(listed: Bool?) {
        var driver = Driver()
        driver.chevron = listed
        driver.settle()
        #expect(driver.restLength == 736)
        #expect(driver.state == .verifiedHidden)
        #expect(driver.machine.chevronListed == listed)
    }

    // MARK: - D-c: blocked, from every phase

    @Test("a failed precondition at rest retires the length first, then says blocked", arguments: blocks)
    func blockedFromRest(preconditions: PreferenceHidingPreconditionResult) {
        var driver = Driver()
        driver.settle()
        let commands = driver.tick(Self.sample(preconditions: preconditions))
        #expect(commands == [.setLength(nil), .report(.state(.blocked(reasons: preconditions.reasons)))])
        #expect(driver.machine.phase == .blocked)
        #expect(!driver.machine.lengthApplied)
    }

    @Test("a failed precondition during a trial or a settle retires that length first", arguments: [1, 2, 5, 9, 20])
    func blockedDuringCalibration(ticksIn: Int) {
        var driver = Driver()
        driver.answers = false
        driver.send(.mode(isIceBar: true))
        driver.run(ticks: 3)
        // Answer by hand so a trial can be left pending.
        for _ in 0..<ticksIn {
            for command in driver.log.suffix(2) {
                if case .takeBaseline(let token, _, _) = command { driver.send(.baseline(token: token, ok: true)) }
            }
            driver.tick()
            if driver.machine.lengthSet { break }
            if case .observe(let token, let asked)? = driver.log.last { driver.send(.observed(token: token, checks: driver.checks(at: asked), chevronListed: false)) }
        }
        let hadLength = driver.machine.lengthSet
        let commands = driver.tick(Self.sample(preconditions: Self.blocks[0]))
        #expect(commands.last == .report(.state(.blocked(reasons: Self.blocks[0].reasons))))
        #expect(commands.contains(.setLength(nil)) == hadLength)
        #expect(driver.length == nil)
        #expect(!driver.machine.lengthSet)
    }

    @Test("blocked before anything was applied changes no length at all")
    func blockedFromQuietChangesNothing() {
        var driver = Driver()
        driver.send(.mode(isIceBar: true))
        let commands = driver.tick(Self.sample(preconditions: Self.blocks[2]))
        #expect(commands == [.report(.state(.blocked(reasons: Self.blocks[2].reasons)))])
        driver.run(Self.sample(preconditions: Self.blocks[2]), ticks: 20)
        #expect(driver.baselines == 0)
        #expect(!driver.log.contains { if case .setLength = $0 { true } else { false } })
    }

    @Test("when the precondition holds again the machine waits out the quiet period and hides again")
    func blockedClears() {
        var driver = Driver()
        driver.settle()
        driver.tick(Self.sample(preconditions: Self.blocks[0]))
        driver.now += 100
        driver.tick()
        #expect(driver.machine.phase == .quiet(since: driver.now))
        #expect(driver.state == .requestedNotVerified(reasons: [.lengthNotApplied]))
        driver.run(ticks: 8)
        #expect(driver.restLength == 736)
        #expect(driver.state == .verifiedHidden)
    }

    @Test("blocked reasons that change are reported again; unchanged ones are not")
    func blockedReasonsAreReportedOnChange() {
        var driver = Driver()
        driver.send(.mode(isIceBar: true))
        driver.tick(Self.sample(preconditions: Self.blocks[0]))
        #expect(driver.tick(Self.sample(preconditions: Self.blocks[0])).isEmpty)
        #expect(driver.tick(Self.sample(preconditions: Self.blocks[1])) == [.report(.state(.blocked(reasons: Self.blocks[1].reasons)))])
    }

    // MARK: - Drags and interaction

    @Test("a Command-drag at rest gives the owner the real divider back")
    func dragRetires() {
        var driver = Driver()
        driver.settle()
        let commands = driver.tick(Self.sample(dragging: true))
        #expect(commands.first == .setLength(nil))
        #expect(driver.machine.phase == .quiet(since: driver.now))
    }

    @Test("the pointer entering the bar during a trial ends it at standard length; at rest it changes nothing")
    func interactionDuringCalibration() {
        var driver = Driver()
        driver.answers = false
        driver.send(.mode(isIceBar: true))
        driver.run(ticks: 3)
        if case .takeBaseline(let token, _, _)? = driver.log.last { driver.send(.baseline(token: token, ok: true)) }
        driver.tick()
        #expect(driver.machine.lengthSet)
        driver.tick(Self.sample(interacting: true))
        #expect(driver.length == nil)

        var resting = Driver()
        resting.settle()
        #expect(resting.tick(Self.sample(interacting: true)).isEmpty)
        #expect(resting.restLength == 736)
    }

    // MARK: - A member seen drawn at rest

    @Test("a re-check that sees a member drawn starts a new cycle, and that cycle may find a length again")
    func drawnRecheckRecycles() {
        var driver = Driver()
        driver.settle()
        driver.now += 100
        // 736 is now above the band: the members are drawn there.
        driver.world = Self.band(500, 700)
        let changed = Self.sample(Self.signature(frontmostPID: 11))
        driver.run(changed, ticks: 4)
        #expect(driver.length == nil, "the length was retired for a new cycle")
        driver.run(changed, ticks: 60)
        #expect(driver.restLength == 600)
        #expect(driver.state == .verifiedHidden)
    }

    @Test("with the members drawn whatever the length, cycles stop after the limit and the rest says visible / failed")
    func drawnRecheckIsBounded() {
        var driver = Driver()
        driver.settle()
        driver.world = { _ in Self.drawn }
        let limit = driver.machine.parameters.maxFailures
        var pid: Int32 = 11
        for _ in 0..<(limit + 3) {
            driver.now += 100
            pid += 1
            driver.run(Self.sample(Self.signature(frontmostPID: pid)), ticks: 120)
        }
        #expect(driver.baselines == 1 + limit)
        #expect(driver.restLength != nil)
        #expect(driver.state == .visibleFailed(drawn: [Self.member(1).tag, Self.member(2).tag]))
    }

    @Test("a drawn re-check too soon after the last cycle keeps the rest and says visible / failed")
    func drawnRecheckRespectsTheInterval() {
        var driver = Driver()
        driver.settle(ticks: 25)
        #expect(driver.restLength == 736)
        driver.world = { _ in Self.drawn }
        let mark = driver.log.count
        driver.run(Self.sample(Self.signature(frontmostPID: 11)), ticks: 5)
        #expect(!driver.since(mark).contains(.setLength(nil)))
        #expect(driver.state == .visibleFailed(drawn: [Self.member(1).tag, Self.member(2).tag]))
    }

    // MARK: - Late and foreign answers

    @Test("an answer for a request the machine no longer waits on is ignored")
    func staleAnswersAreIgnored() {
        var driver = Driver()
        driver.settle()
        let phase = driver.machine.phase
        #expect(driver.send(.observed(token: 1, checks: [:], chevronListed: true)).isEmpty)
        #expect(driver.send(.baseline(token: 1, ok: false)).isEmpty)
        #expect(driver.machine.phase == phase)
    }

    @Test("a status is reported once per change, and never before the length it speaks of was retired")
    func reportsOncePerChange() {
        var driver = Driver()
        driver.settle()
        driver.tick(Self.sample(preconditions: Self.blocks[0]))
        driver.run(Self.sample(preconditions: Self.blocks[0]), ticks: 5)
        let reports = driver.reports
        #expect(zip(reports, reports.dropFirst()).allSatisfy { $0 != $1 })
        #expect(reports.last == .state(.blocked(reasons: Self.blocks[0].reasons)))
    }
}
