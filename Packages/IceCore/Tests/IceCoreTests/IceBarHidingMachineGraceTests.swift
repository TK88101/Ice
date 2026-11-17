import Testing
@testable import IceCore

/// A complete pass that could not read Ice's own icon or divider says nothing
/// of the bar: at a length, hiding at once, it is set aside for a bounded
/// grace instead of retiring the length (plan 2026-11-17-transient-pass-grace).
@Suite("IceBarHidingMachine grace")
struct IceBarHidingMachineGraceTests {
    typealias Base = IceBarHidingMachineTests

    static let grace = IceBarHidingParameters.unverified.transientGrace

    /// The pass the owner's log showed four times on 2026-11-17: six items
    /// fewer, Ice's icon unreadable, the own read without its divider.
    static let unreadable = Base.sample(
        Base.signature(items: ["v1"], members: ["m1", "m2"]),
        preconditions: .blocked([.iceIconNotRightOfDivider(.iconUnreadable), .ownReadNotOk(.identifiersMissing)])
    )

    /// Hiding at once, resting at its length.
    static func resting() -> Base.Driver {
        var driver = Base.atOnce()
        driver.tick(seconds: 0.1)
        return driver
    }

    static func graceToken(_ commands: [IceBarHidingCommand]) -> Int? {
        commands.lazy.compactMap { if case .armGrace(let token, _) = $0 { token } else { nil } }.first
    }

    @Test("an unreadable pass keeps the length, asks for a pass at once and arms the grace")
    func unreadablePassKeepsLength() {
        var driver = Self.resting()
        let commands = driver.tick(Self.unreadable)

        #expect(!commands.contains(.setLength(nil)))
        #expect(commands.contains(.reread))
        #expect(Self.graceToken(commands) != nil)
        #expect(commands.contains { if case .armGrace(_, let after) = $0 { after == Self.grace } else { false } })
        #expect(driver.length == 736)
        #expect(driver.machine.lengthApplied)
    }

    @Test("while the grace runs the state says the read was transient, never blocked")
    func stateNamesTheTransientRead() {
        var driver = Self.resting()
        driver.tick(Self.unreadable)

        guard case .requestedNotVerified(let reasons) = driver.state else {
            Issue.record("the state is \(String(describing: driver.state))")
            return
        }
        #expect(reasons.contains(.transientRead))
    }

    @Test("more unreadable passes neither retire nor arm the grace again")
    func repeatedUnreadableArmsOnce() {
        var driver = Self.resting()
        driver.tick(Self.unreadable)
        let mark = driver.log.count
        driver.run(Self.unreadable, ticks: 3)

        #expect(!driver.since(mark).contains(.setLength(nil)))
        #expect(Self.graceToken(driver.since(mark)) == nil)
        #expect(!driver.since(mark).contains(.reread))
    }

    @Test("a readable pass with the bar as before ends the grace: nothing retired, the unreadable pass left no trace")
    func recoveryKeepsLength() {
        var driver = Self.resting()
        driver.tick(Self.unreadable)
        let mark = driver.log.count
        driver.tick()

        #expect(!driver.since(mark).contains(.setLength(nil)))
        #expect(driver.length == 736)
        guard case .requestedNotVerified(let reasons) = driver.state else {
            Issue.record("the state is \(String(describing: driver.state))")
            return
        }
        #expect(!reasons.contains(.transientRead))
    }

    @Test("the grace ending with no readable pass retires the length, once")
    func expiryRetiresOnce() {
        var driver = Self.resting()
        guard let token = Self.graceToken(driver.tick(Self.unreadable)) else {
            Issue.record("no grace armed")
            return
        }
        driver.now += Self.grace
        let first = driver.send(.graceExpired(token: token))
        let second = driver.send(.graceExpired(token: token))

        #expect(first.first == .setLength(nil))
        #expect(!second.contains(.setLength(nil)))
        #expect(driver.length == nil)
        #expect(driver.state == .blocked(reasons: Self.unreadable.preconditions.reasons), "the pass set aside is what stands")
    }

    @Test("a grace that ended by a readable pass ignores its late expiry")
    func staleExpiryIgnored() {
        var driver = Self.resting()
        guard let token = Self.graceToken(driver.tick(Self.unreadable)) else {
            Issue.record("no grace armed")
            return
        }
        driver.tick()
        let commands = driver.send(.graceExpired(token: token))

        #expect(!commands.contains(.setLength(nil)))
        #expect(driver.length == 736)
    }

    @Test("a new grace's expiry is not answered by the old one's token")
    func oldTokenDoesNotEndNewGrace() {
        var driver = Self.resting()
        guard let old = Self.graceToken(driver.tick(Self.unreadable)) else {
            Issue.record("no grace armed")
            return
        }
        driver.tick()
        guard let new = Self.graceToken(driver.tick(Self.unreadable)) else {
            Issue.record("no second grace armed")
            return
        }
        #expect(old != new)
        #expect(!driver.send(.graceExpired(token: old)).contains(.setLength(nil)))
        #expect(driver.send(.graceExpired(token: new)).first == .setLength(nil))
    }

    @Test("a readable pass that differs structurally from the bar before the grace retires, as without one")
    func recoveryWithStructuralChangeRetires() {
        var driver = Self.resting()
        driver.tick(Self.unreadable)
        let added = Base.sample(Base.signature(items: ["v1", "x", "m1", "m2"]))

        #expect(driver.tick(added).first == .setLength(nil))
    }

    @Test("the reference stays the bar before the grace: a readable pass that reads what the unreadable one did still retires")
    func referenceIsNotTheUnreadablePass() {
        var driver = Self.resting()
        let other = Base.signature(items: ["v1", "x", "m1", "m2"])
        driver.tick(Base.sample(other, preconditions: Self.unreadable.preconditions))

        #expect(driver.tick(Base.sample(other)).first == .setLength(nil))
    }

    static let immediate: [PreferenceHidingPreconditionResult] = [
        .blocked([.discoveryIncomplete(.incomplete(failedPIDs: [5])), .ownReadNotOk(.identifiersMissing)]),
        .blocked([.iceIconNotRightOfDivider(.iconUnreadable), .discoveryIncomplete(.incomplete(failedPIDs: [5]))]),
        .blocked([.discoveryIncomplete(.permissionDenied)]),
        .blocked([.iceIconNotRightOfDivider(.iconLeftOfDivider)]),
        .blocked([.positionalItemsLeftOfDivider([
            PreferenceHidingBlocker(key: Base.key(9), tag: Base.key(9).tagKey(isSelf: false), name: nil),
        ])]),
    ]

    @Test("a pass blocked for any other reason retires at once, as today", arguments: immediate)
    func otherBlocksRetireAtOnce(preconditions: PreferenceHidingPreconditionResult) {
        var driver = Self.resting()
        let commands = driver.tick(Base.sample(preconditions: preconditions))

        #expect(commands.first == .setLength(nil))
        #expect(Self.graceToken(commands) == nil)
    }

    @Test("the same block during a grace retires at once")
    func otherBlockDuringGraceRetires() {
        var driver = Self.resting()
        driver.tick(Self.unreadable)
        let incomplete = Base.sample(preconditions: .blocked([.discoveryIncomplete(.incomplete(failedPIDs: [5]))]))

        #expect(driver.tick(incomplete).first == .setLength(nil))
    }

    @Test("a Command-drag during a grace gives the real divider back at once")
    func dragDuringGraceRetires() {
        var driver = Self.resting()
        driver.tick(Self.unreadable)

        #expect(driver.tick(Base.sample(dragging: true)).first == .setLength(nil))
    }

    @Test("while verifying, an unreadable pass retires at once, as today")
    func verifyingHasNoGrace() {
        var driver = Base.Driver()
        driver.settle()
        #expect(driver.restLength != nil)

        let commands = driver.tick(Self.unreadable)
        #expect(commands.first == .setLength(nil))
        #expect(Self.graceToken(commands) == nil)
    }

    @Test("at standard length an unreadable pass blocks, as today: there is no length to keep")
    func standardLengthBlocks() {
        var driver = Base.atOnce()
        let commands = driver.tick(Self.unreadable)

        #expect(Self.graceToken(commands) == nil)
        #expect(driver.length == nil)
        guard case .blocked = driver.state else {
            Issue.record("the state is \(String(describing: driver.state))")
            return
        }
    }

    @Test("IceBar mode off during a grace drops it: a late expiry does nothing")
    func modeOffDropsGrace() {
        var driver = Self.resting()
        guard let token = Self.graceToken(driver.tick(Self.unreadable)) else {
            Issue.record("no grace armed")
            return
        }
        driver.send(.mode(isIceBar: false))
        let mark = driver.log.count
        driver.send(.graceExpired(token: token))

        #expect(!driver.since(mark).contains(.setLength(nil)))
    }
}
