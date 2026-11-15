import Testing
@testable import IceCore

/// The machine on macOS 27.2 (plan 2026-11-15-blind-at-length): it rests
/// through blind passes, and stays at standard length while the coordinator
/// holds the bar for a press or a re-read (D3, D4). Hiding at once, as Ice
/// runs.
@Suite("IceBarHidingMachine, holds and blind rests")
struct IceBarHidingMachineHoldTests {
    typealias Base = IceBarHidingMachineTests

    static func sample(
        _ signature: LayoutSignature = Base.signature(),
        preconditions: PreferenceHidingPreconditionResult = .ok,
        held: Bool = false,
        boundaryUsable: Bool = true
    ) -> IceBarHidingSample {
        IceBarHidingSample(
            signature: signature, preconditions: preconditions, membership: Base.roster(),
            isInteracting: false, isDragging: false, boundaryUsable: boundaryUsable, isHeld: held
        )
    }

    /// Resting at the length, hiding at once.
    static func resting() -> Base.Driver {
        var driver = Base.atOnce()
        driver.tick(seconds: 0.1)
        return driver
    }

    @Test("27.2 at rest: a minute of blind passes (preconditions ok, the same signature, no usable boundary) gives no command")
    func blindRestIsQuiet() {
        var driver = Self.resting()
        let mark = driver.log.count
        for _ in 0..<12 {
            driver.tick(Self.sample(boundaryUsable: false), seconds: 5)
        }
        #expect(driver.since(mark).isEmpty)
        #expect(driver.length == 736)
        #expect(driver.machine.lengthApplied)
    }

    @Test("what 1.1.2 did there: the same pass read as a failed own read retires the length")
    func blockedRetires() {
        var driver = Self.resting()
        let commands = driver.tick(Self.sample(preconditions: .blocked([.ownReadNotOk(.identifiersMissing)]), boundaryUsable: false), seconds: 5)
        #expect(commands.first == .setLength(nil))
    }

    @Test("a hold retires the length and the machine stays at standard length while it lasts")
    func holdRetiresAndStays() {
        var driver = Self.resting()
        let commands = driver.tick(Self.sample(held: true))
        #expect(commands.first == .setLength(nil))
        #expect(!driver.machine.lengthApplied)
        let mark = driver.log.count
        for _ in 0..<10 {
            driver.tick(Self.sample(held: true))
        }
        #expect(driver.since(mark).isEmpty, "held with a usable boundary: still nothing is hidden")
        #expect(driver.length == nil)
    }

    @Test("the hold over, the first sample with a usable boundary hides again")
    func hidesAfterHold() {
        var driver = Self.resting()
        driver.tick(Self.sample(held: true))
        let commands = driver.tick(Self.sample(), seconds: 0.1)
        #expect(commands.first == .setLength(736))
        #expect(driver.machine.lengthApplied)
    }

    @Test("the hold over but no pass has read the bar at standard length yet: nothing is hidden until one has")
    func waitsForBoundaryAfterHold() {
        var driver = Self.resting()
        driver.tick(Self.sample(held: true, boundaryUsable: false))
        let waiting = driver.tick(Self.sample(boundaryUsable: false), seconds: 0.1)
        #expect(waiting.isEmpty)
        #expect(driver.length == nil)
        let commands = driver.tick(Self.sample(), seconds: 1)
        #expect(commands.first == .setLength(736))
    }

    @Test("a hold while a precondition fails keeps the standard length and hides nothing when it ends")
    func holdOverBlocked() {
        var driver = Self.resting()
        let blocked = PreferenceHidingPreconditionResult.blocked([.iceIconNotRightOfDivider(.iconUnreadable)])
        driver.tick(Self.sample(preconditions: blocked, held: true))
        #expect(driver.length == nil)
        let after = driver.tick(Self.sample(preconditions: blocked))
        #expect(!after.contains(.setLength(736)))
        #expect(driver.length == nil)
    }

    @Test("a hold before any length was applied changes no length")
    func holdBeforeLength() {
        var driver = Base.atOnce()
        let commands = driver.tick(Self.sample(held: true), seconds: 0.1)
        #expect(!commands.contains { if case .setLength = $0 { true } else { false } })
        #expect(driver.length == nil)
    }
}
