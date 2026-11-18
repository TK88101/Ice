import CoreGraphics
import IceCore
import Testing
@testable import MenuBarCover

/// Plan 2026-11-15-cover, T2: the controller against a fake bar.
final class FakeReader: CoverBarReading {
    var slotsByDisplay = [UInt32: [CoverSlot]?]()
    /// What a hit at a display-local x answers.
    var hit: (Double, UInt32) -> CoverHit = { _, _ in .silent }
    var hitCalls = 0

    func slots(of bar: CoverBar) -> [CoverSlot]? { slotsByDisplay[bar.displayID] ?? [] }

    func owners(at xs: [Double], of bar: CoverBar) -> [CoverHit] {
        hitCalls += xs.count
        return xs.map { hit($0, bar.displayID) }
    }
}

final class FakeCapturer: CoverCapturing {
    var calls = 0
    var signature = "desktop"
    var opaque = false
    /// The gray of the strip below the bar.
    var gray: UInt8 = 40
    /// The image calls return nothing.
    var fails = false
    /// Every capture differs from the one before it (a wallpaper that moves).
    var moves = false
    private var moved: UInt8 = 0

    static func image(width: Int, gray: UInt8, patch: Range<Int>? = nil, patchGray: UInt8 = 0) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: 2, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: CGFloat(gray) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 2))
        if let patch {
            context.setFillColor(CGColor(gray: CGFloat(patchGray) / 255, alpha: 1))
            context.fill(CGRect(x: patch.lowerBound, y: 0, width: patch.count, height: 2))
        }
        return context.makeImage()!
    }

    func strips(of bar: CoverBar) -> CoverStrips? {
        calls += 2
        guard !fails else { return nil }
        let width = Int(bar.frame.width * bar.scale)
        if moves { moved = moved == 200 ? 0 : moved + 40 }
        let below = moves ? moved : gray
        return CoverStrips(below: Self.image(width: width, gray: below), onScreen: Self.image(width: width, gray: opaque ? 200 : below))
    }

    func underStripSignature(of bar: CoverBar) -> String { signature }
}

final class FakePresenter: CoverPresenting {
    var shown = [UInt32: [ClosedRange<Double>]]()
    var log = [String]()
    var ignoring = Set<UInt32>()
    /// Hit tests left to fail after the panels were told to ignore mouse events.
    var closedPolls = 0
    var pollsToOpen = 2

    /// Whether a hit at that point of a bar is stopped by a panel, as the window server stops it.
    func blocks(_ x: Double, _ display: UInt32) -> Bool {
        guard shown[display]?.contains(where: { $0.contains(x) }) == true else { return false }
        guard ignoring.contains(display) else { return true }
        guard closedPolls > 0 else { return false }
        closedPolls -= 1
        return true
    }

    func show(blocks: [ClosedRange<Double>], strip: CGImage, bar: CoverBar) {
        shown[bar.displayID] = blocks
        log.append("show \(bar.displayID)")
    }

    func remove(displayID: UInt32?) {
        if let displayID { shown[displayID] = nil } else { shown = [:] }
        log.append("remove \(displayID.map(String.init) ?? "all")")
    }

    func setIgnoresMouseEvents(_ ignores: Bool, displayID: UInt32) {
        log.append("ignores \(ignores) \(displayID)")
        if ignores {
            ignoring.insert(displayID)
            closedPolls = pollsToOpen
        } else {
            ignoring.remove(displayID)
        }
    }
}

final class Rig {
    let reader = FakeReader()
    let capturer = FakeCapturer()
    let presenter = FakePresenter()
    var now = 100.0
    var canCapture = true
    var key = "space1"
    var bars = [CoverBar(displayID: 7, frame: CGRect(x: -1314, y: 0, width: 1314, height: 30), scale: 2, notch: nil)]
    var timers = [(at: Double, run: () -> Void)]()
    /// When set, a pass's body waits until `flush()`.
    var holdsPasses = false
    var held = [() -> Void]()
    var reports = [(reports: [CoverBarReport], generation: Int)]()
    var diagnoses = [CoverBarDiagnosis]()
    var captures = [CoverCaptureFact]()
    var paused = 0.0
    /// Owners whose apps answer no hit test, and owners whose hit test fails.
    var silentOwners = Set<Int32>()
    var failingOwners = Set<Int32>()
    lazy var controller: CoverController = {
        let controller = CoverController(
            reader: reader, capturer: capturer, presenter: presenter,
            environment: .init(
                bars: { [unowned self] in self.bars }, backgroundKey: { [unowned self] _ in self.key },
                canCapture: { [unowned self] in self.canCapture }, now: { [unowned self] in self.now },
                background: { [unowned self] body in if self.holdsPasses { self.held.append(body) } else { body() } },
                main: { $0() }, mainSync: { $0() },
                after: { [unowned self] delay, body in self.timers.append((self.now + delay, body)) },
                pause: { [unowned self] seconds in self.paused += seconds }
            )
        )
        controller.onReport = { [unowned self] reports, generation in self.reports.append((reports, generation)) }
        controller.onDiagnosis = { [unowned self] in self.diagnoses.append($0) }
        controller.onCapture = { [unowned self] in self.captures.append($0) }
        return controller
    }()

    func flush() {
        let bodies = held
        held = []
        bodies.forEach { $0() }
    }

    func advance(_ seconds: Double) {
        now += seconds
        let due = timers.filter { $0.at <= now }
        timers.removeAll { $0.at <= now }
        due.forEach { $0.run() }
    }

    func slot(_ owner: Int32, _ minX: Double, _ width: Double) -> CoverSlot {
        CoverSlot(owner: owner, minX: minX, maxX: minX + width)
    }

    /// Two members and a visible item; every slot is hit as its owner, unless a panel stops the hit.
    func standardBar() {
        bar([slot(1, 500, 38), slot(2, 538, 38), slot(20, 600, 40)])
    }

    func bar(_ slots: [CoverSlot]) {
        reader.slotsByDisplay[7] = slots
        reader.hit = { [unowned self] x, display in
            // A panel that takes mouse events, empty bar and a silent owner all answer nothing.
            guard !self.presenter.blocks(x, display), let owner = slots.first(where: { $0.minX <= x && x < $0.maxX })?.owner,
                  !self.silentOwners.contains(owner)
            else {
                return .silent
            }
            return self.failingOwners.contains(owner) ? .failed : .owner(owner)
        }
    }

    /// A member whose app answers nothing (3), one that answers (1), a visible item (20); both members coverable.
    func mixedBar() {
        silentOwners = [3]
        bar([slot(3, 440, 28), slot(1, 500, 38), slot(20, 600, 40)])
    }

    /// The first pass and two more, a second apart: what a silent member needs to stand.
    func threePasses(_ coverable: Set<Int32>) {
        start(coverable)
        for _ in 0..<2 {
            advance(1)
            controller.tick()
        }
    }

    /// On, and past the settle before the first read.
    func start(_ coverable: Set<Int32> = [1, 2]) {
        controller.sync(active: true, coverable: coverable)
        advance(CoverController.activationSettle)
    }

    /// On, with the first read at a whole second (101), so the ladder's steps fall on the ticks exactly.
    func startWhole(_ coverable: Set<Int32> = [1, 2]) {
        controller.sync(active: true, coverable: coverable)
        now = 101
        advance(0)
    }

    /// Ticks a second apart for `seconds`.
    func run(seconds: Int) {
        for _ in 0..<seconds {
            advance(1)
            controller.tick()
        }
    }
}

@Suite("CoverController")
struct CoverControllerTests {
    @Test("members drawn on a bar get one panel over them, after one capture of two image calls")
    func covers() {
        let rig = Rig()
        rig.standardBar()
        rig.start()
        #expect(rig.presenter.shown[7] == [496...580])
        #expect(rig.capturer.calls == 2)
        #expect(rig.reports.last?.reports.first?.covered.count == 2)
    }

    @Test("the panel follows the members when they move, without another capture")
    func follows() {
        let rig = Rig()
        rig.standardBar()
        rig.start()
        rig.bar([rig.slot(1, 452, 38), rig.slot(2, 490, 38), rig.slot(20, 552, 40)])
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.presenter.shown[7] == [448...532])
        #expect(rig.capturer.calls == 2)
        #expect(rig.presenter.log.contains("ignores true 7") && rig.presenter.log.last != "ignores true 7")
    }

    @Test("a candidate whose place now holds another item gets no panel (a stale window)")
    func staleSlot() {
        let rig = Rig()
        rig.standardBar()
        let stale = rig.slot(2, 610, 38)
        rig.reader.slotsByDisplay[7] = (rig.reader.slotsByDisplay[7] ?? []).map { $0 + [stale] }
        rig.start()
        #expect(rig.presenter.shown[7] == [496...580])
        #expect(rig.reports.last?.reports.first?.covered.contains(stale) == false)
    }

    @Test("going off removes every panel before it returns, and a read that ends later changes nothing")
    func offFirst() {
        let rig = Rig()
        rig.standardBar()
        rig.start()
        rig.holdsPasses = true
        rig.advance(1)
        rig.controller.tick()
        let generation = rig.controller.generation
        rig.controller.sync(active: false, coverable: [])
        #expect(rig.presenter.shown.isEmpty)
        #expect(rig.controller.generation == generation + 1)
        #expect(rig.reports.last?.reports.isEmpty == true)
        rig.flush()
        #expect(rig.presenter.shown.isEmpty)
    }

    @Test("nothing is read or shown before the layout has settled after the length is applied")
    func settles() {
        let rig = Rig()
        rig.standardBar()
        rig.controller.sync(active: true, coverable: [1, 2])
        #expect(rig.presenter.shown.isEmpty && rig.reader.hitCalls == 0)
        rig.advance(CoverController.activationSettle)
        #expect(rig.presenter.shown[7] == [496...580])
    }

    @Test("the periodic verification waits until the panels let the hit test through, and the panels stay")
    func reverifiesUnderPanels() {
        let rig = Rig()
        rig.standardBar()
        rig.start()
        let events = rig.reports.count
        rig.advance(CoverController.reverifyEvery + 1)
        rig.controller.tick()
        #expect(rig.presenter.shown[7] == [496...580])
        #expect(rig.reports.count == events)
        #expect(rig.presenter.log.suffix(3).contains("ignores true 7") && rig.presenter.log.last == "show 7")
        #expect(rig.paused > 0)
        #expect(rig.presenter.ignoring.isEmpty)
    }

    @Test("no member drawn, no panel and no capture")
    func nothingDrawn() {
        let rig = Rig()
        rig.reader.slotsByDisplay[7] = [rig.slot(20, 600, 40)]
        rig.start()
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.presenter.shown.isEmpty)
        #expect(rig.capturer.calls == 0)
    }

    @Test("a bar that is not transparent is not covered, and says so")
    func opaqueBar() {
        let rig = Rig()
        rig.standardBar()
        rig.capturer.opaque = true
        rig.start()
        #expect(rig.presenter.shown.isEmpty)
        #expect(rig.controller.notice == .barNotTransparent(displayID: 7))
    }

    @Test("without Screen Recording there is no cover, and it says so")
    func noPermission() {
        let rig = Rig()
        rig.standardBar()
        rig.canCapture = false
        rig.start()
        #expect(rig.presenter.shown.isEmpty)
        #expect(rig.capturer.calls == 0)
        #expect(rig.controller.notice == .noScreenRecording)
    }

    @Test("a tree that cannot be read keeps the last blocks")
    func unreadableKeeps() {
        let rig = Rig()
        rig.standardBar()
        rig.start()
        rig.reader.slotsByDisplay[7] = .some(nil)
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.presenter.shown[7] == [496...580])
    }

    @Test("a changed background key or window under the strip takes one new capture; the budget makes a second change wait 12 s")
    func recaptures() {
        let rig = Rig()
        rig.standardBar()
        rig.start()
        rig.advance(13)
        rig.key = "space2"
        rig.controller.tick()
        #expect(rig.capturer.calls == 4)
        rig.advance(1)
        rig.capturer.signature = "a window under the bar"
        rig.controller.tick()
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.capturer.calls == 4)
        #expect(rig.presenter.shown[7] == [496...580])
        rig.advance(11)
        #expect(rig.capturer.calls == 6)
    }

    @Test("after 30 minutes the background is taken again")
    func refreshes() {
        let rig = Rig()
        rig.standardBar()
        rig.start()
        rig.advance(CoverBackgroundTrust.refreshEvery + 1)
        rig.controller.tick()
        #expect(rig.capturer.calls == 4)
    }

    @Test("an active-display change keeps the panels while they are verified again, and removes them if that takes over half a second")
    func activeDisplayChange() {
        let rig = Rig()
        rig.standardBar()
        rig.start()
        rig.controller.activeDisplayChanged()
        #expect(rig.presenter.shown[7] == [496...580])
        rig.advance(1)
        #expect(rig.presenter.shown[7] == [496...580])

        rig.holdsPasses = true
        rig.controller.activeDisplayChanged()
        rig.advance(0.6)
        #expect(rig.presenter.shown.isEmpty)
        rig.holdsPasses = false
        rig.flush()
        #expect(rig.presenter.shown[7] == [496...580])
    }

    // MARK: Amendment B: a member whose app answers no hit test

    @Test("a member whose app answers no hit test gets its panel on the third pass, and is not tested again under it")
    func silentStands() {
        let rig = Rig()
        rig.mixedBar()
        rig.start([1, 3])
        #expect(rig.presenter.shown[7] == [496...542])
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.presenter.shown[7] == [496...542])
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.presenter.shown[7] == [436...472, 496...542])
        #expect(rig.reports.last?.reports.first?.silent == [rig.slot(3, 440, 28)])
        #expect(rig.reports.last?.reports.first?.covered == [rig.slot(3, 440, 28), rig.slot(1, 500, 38)])
        let calls = rig.reader.hitCalls
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.reader.hitCalls == calls)
        #expect(rig.presenter.shown[7] == [436...472, 496...542])
    }

    @Test("the periodic test of a bar with an answering member waits on that member, not the fixed time, and the silent member stays")
    func silentReverified() {
        let rig = Rig()
        rig.mixedBar()
        rig.threePasses([1, 3])
        let paused = rig.paused
        rig.advance(CoverController.reverifyEvery + 1)
        rig.controller.tick()
        #expect(rig.paused - paused < CoverController.openPoll * Double(CoverController.openPolls) / 2)
        #expect(rig.presenter.shown[7] == [436...472, 496...542])
        #expect(rig.presenter.ignoring.isEmpty)
    }

    @Test("a slot of another item that comes to overlap a silent member takes its panel away on the next tick, the candidates unchanged")
    func silentOverlapped() {
        let rig = Rig()
        rig.mixedBar()
        rig.threePasses([1, 3])
        rig.bar([rig.slot(3, 440, 28), rig.slot(21, 450, 30), rig.slot(1, 500, 38), rig.slot(20, 600, 40)])
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.presenter.shown[7] == [496...542])
        #expect(rig.reports.last?.reports.first?.silent.isEmpty == true)
    }

    @Test("an active-display change keeps a silent member's panel while the read is unchanged, and takes it at once when its frame moved")
    func silentAcrossDisplayChange() {
        let rig = Rig()
        rig.mixedBar()
        rig.threePasses([1, 3])
        rig.controller.activeDisplayChanged()
        #expect(rig.presenter.shown[7] == [436...472, 496...542])
        rig.bar([rig.slot(3, 445, 28), rig.slot(1, 500, 38), rig.slot(20, 600, 40)])
        rig.controller.activeDisplayChanged()
        #expect(rig.presenter.shown[7] == [496...542])
    }

    @Test("a bar whose panels cover only silent members waits the fixed time before the periodic test, once, and the panel stays")
    func silentOnlyBar() {
        let rig = Rig()
        rig.silentOwners = [3]
        rig.bar([rig.slot(3, 440, 28), rig.slot(20, 600, 40)])
        rig.threePasses([3])
        #expect(rig.presenter.shown[7] == [436...472])
        let paused = rig.paused
        rig.advance(CoverController.reverifyEvery + 1)
        rig.controller.tick()
        #expect(abs(rig.paused - paused - CoverController.openPoll * Double(CoverController.openPolls)) < 1e-9)
        #expect(rig.presenter.shown[7] == [436...472])
        #expect(rig.presenter.ignoring.isEmpty)
    }

    @Test("a member whose hit test fails, rather than answering nothing, never gets a panel")
    func failedNeverStands() {
        let rig = Rig()
        rig.failingOwners = [3]
        rig.bar([rig.slot(3, 440, 28), rig.slot(1, 500, 38), rig.slot(20, 600, 40)])
        rig.threePasses([1, 3])
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.presenter.shown[7] == [496...542])
    }

    @Test("going off forgets the silent members: after the length is applied again they need three passes anew")
    func silentForgottenWhenOff() {
        let rig = Rig()
        rig.mixedBar()
        rig.threePasses([1, 3])
        rig.controller.sync(active: false, coverable: [])
        rig.start([1, 3])
        #expect(rig.presenter.shown[7] == [496...542])
    }

    @Test("a display that goes takes its panels with it")
    func displayGone() {
        let rig = Rig()
        rig.standardBar()
        rig.start()
        rig.bars = []
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.presenter.shown.isEmpty)
    }

    // MARK: - Plan 2026-11-18-cover-stale-and-lost, D1 and D6

    @Test("a strip taken at a dim moment is replaced 12 s later with no signal, and the one after is compared at 12 s and 60 s")
    func dimStripIsReplaced() {
        let rig = Rig()
        rig.standardBar()
        // The desktop is dim when the first capture is taken, and normal a moment later; nothing says so.
        rig.capturer.gray = 20
        rig.startWhole()
        rig.capturer.gray = 40
        #expect(rig.captures.map(\.reason) == [.size])
        rig.run(seconds: 11)
        #expect(rig.captures.count == 1)
        rig.run(seconds: 1)
        #expect(rig.captures.map(\.reason) == [.size, .confirm])
        #expect(rig.captures.last?.equal == false)
        #expect(rig.captures.last?.unequalRun == 1)
        #expect(rig.captures.last?.luma == CoverPixels.luma(FakeCapturer.image(width: 10, gray: 40)))
        rig.run(seconds: 12)
        #expect(rig.captures.last?.equal == true)
        #expect(rig.captures.last?.step == 1)
        rig.run(seconds: 47)
        #expect(rig.captures.count == 3)
        rig.run(seconds: 1)
        #expect(rig.captures.count == 4)
        #expect(rig.captures.last?.step == 2)
        // Confirmed: nothing more before the refresh.
        rig.run(seconds: 600)
        #expect(rig.captures.count == 4)
        #expect(rig.capturer.calls == 8)
    }

    @Test("a background that keeps moving is compared four times 12 s apart, then 300 s later; stale signals bring no 12 s step back and do not put that one off")
    func movingBackground() {
        let rig = Rig()
        rig.standardBar()
        rig.capturer.moves = true
        rig.startWhole()
        rig.run(seconds: 48)
        #expect(rig.captures.map(\.reason) == [.size, .confirm, .confirm, .confirm, .confirm])
        #expect(rig.captures.last?.unequalRun == 4)
        // A window moves under the bar every 12 s for four minutes.
        var confirmedAt = [Double]()
        for second in 1...300 {
            if second % 12 == 0, second <= 240 { rig.capturer.signature = "window \(second)" }
            let before = rig.captures.filter { $0.reason == .confirm }.count
            rig.advance(1)
            rig.controller.tick()
            if rig.captures.filter({ $0.reason == .confirm }).count > before { confirmedAt.append(rig.now) }
        }
        #expect(rig.captures.filter { $0.reason == .stale }.count == 20)
        #expect(confirmedAt == [449], "300 s after the fourth unequal comparison at 149")
        #expect(rig.captures.last?.unequalRun == 5)
        #expect(rig.capturer.calls == rig.captures.count * 2)
    }

    @Test("a bar with a candidate and no block is granted no capture; a step that fell due meanwhile is taken when a block is up again")
    func noBlockNoCapture() {
        let rig = Rig()
        rig.standardBar()
        rig.startWhole()
        #expect(rig.captures.count == 1)
        // The members are listed, and another item answers where they lie: candidates, no block.
        rig.reader.hit = { _, _ in .owner(20) }
        rig.controller.activeDisplayChanged()
        #expect(rig.presenter.shown[7] == nil)
        rig.run(seconds: 30)
        #expect(rig.captures.count == 1)
        rig.standardBar()
        rig.run(seconds: 2)
        #expect(rig.captures.map(\.reason) == [.size, .confirm])
        #expect(rig.presenter.shown[7] == [496...580])
    }

    @Test("a capture that returns nothing is tried again at 12, 12, 60 and 300 s, and the image held stays")
    func failedCaptureBacksOff() {
        let rig = Rig()
        rig.standardBar()
        rig.startWhole()
        rig.capturer.fails = true
        var failedAfter = [Double]()
        for _ in 0..<420 {
            rig.advance(1)
            rig.controller.tick()
            if rig.captures.count - 1 > failedAfter.count { failedAfter.append(rig.now - 101) }
        }
        #expect(failedAfter == [12, 24, 36, 96, 396])
        #expect(rig.captures.dropFirst().allSatisfy { $0.failed && $0.reason == .confirm })
        #expect(rig.presenter.shown[7] == [496...580], "the image held is still shown")
    }

    @Test("with no image at all a failing capture does not spin: one attempt per retry step, and the panels come when it works")
    func failedFirstCaptureDoesNotSpin() {
        let rig = Rig()
        rig.standardBar()
        rig.capturer.fails = true
        rig.startWhole()
        #expect(rig.capturer.calls == 2)
        rig.run(seconds: 11)
        #expect(rig.capturer.calls == 2)
        rig.run(seconds: 1)
        #expect(rig.capturer.calls == 4)
        rig.run(seconds: 12)
        #expect(rig.capturer.calls == 6)
        // The budget would allow a session from 137 on; the rule says 60 s.
        rig.run(seconds: 59)
        #expect(rig.capturer.calls == 6)
        rig.run(seconds: 1)
        #expect(rig.capturer.calls == 8)
        #expect(rig.presenter.shown[7] == nil)
        rig.capturer.fails = false
        rig.run(seconds: 300)
        #expect(rig.presenter.shown[7] == [496...580])
        #expect(rig.captures.last?.failed == false)
    }

    @Test("the pass that first reads a tree with no hosted slot (Mission Control) takes no capture though one was granted; the held image stays")
    func noCaptureInAnEmptyRead() {
        let rig = Rig()
        rig.standardBar()
        rig.startWhole()
        rig.run(seconds: 11)
        #expect(rig.captures.count == 1)
        // Mission Control opens in the second the confirmation is due: the desktop dims, the tree lists the agent's slots only.
        rig.capturer.signature = "mission control"
        rig.capturer.gray = 20
        rig.reader.slotsByDisplay[7] = [rig.slot(99, 500, 20)]
        rig.run(seconds: 1)
        #expect(rig.captures.count == 1)
        #expect(rig.capturer.calls == 2, "no image call in that pass")
        #expect(rig.presenter.shown[7] == nil)
        // It closes: the members are back under the image held, and the confirmation owed is taken at the budget's next slot.
        rig.capturer.signature = "desktop"
        rig.capturer.gray = 40
        rig.standardBar()
        rig.run(seconds: 1)
        #expect(rig.presenter.shown[7] == [496...580])
        #expect(rig.captures.count == 1)
        rig.run(seconds: 12)
        #expect(rig.captures.count == 2)
        // The windows under the strip changed meanwhile, so the capture owed is a signal's; it finds the strip as it was.
        #expect(rig.captures.last?.reason == .stale)
        #expect(rig.captures.last?.equal == true)
        #expect(rig.captures.last?.luma == CoverPixels.luma(FakeCapturer.image(width: 10, gray: 40)))
        rig.run(seconds: 12)
        #expect(rig.captures.last?.reason == .confirm)
        #expect(rig.captures.last?.step == 1)
    }

    @Test("one capture that does not show the bar transparent, with a transparent image held, takes no panel down; a second in a row is believed")
    func opaqueMomentIsDoubtedOnce() {
        let rig = Rig()
        rig.standardBar()
        rig.startWhole()
        // Mission Control closes over the bar while a capture is taken (2026-11-18, 19:14:28: the panels went for 11 s).
        rig.capturer.opaque = true
        rig.capturer.signature = "mission control closing"
        rig.run(seconds: 12)
        #expect(rig.captures.count == 2)
        #expect(rig.captures.last?.transparent == false)
        #expect(rig.captures.last?.ignored == true)
        #expect(rig.presenter.shown[7] == [496...580])
        #expect(rig.controller.notice == nil)
        rig.capturer.opaque = false
        rig.run(seconds: 12)
        #expect(rig.captures.count == 3)
        #expect(rig.captures.last?.transparent == true)
        #expect(rig.captures.last?.ignored == false)
        #expect(rig.presenter.shown[7] == [496...580])

        // A bar that has become opaque for good: believed at the second capture.
        rig.capturer.opaque = true
        rig.capturer.signature = "a setting changed"
        rig.run(seconds: 12)
        #expect(rig.captures.last?.ignored == true)
        #expect(rig.presenter.shown[7] == [496...580])
        rig.run(seconds: 12)
        #expect(rig.captures.last?.ignored == false)
        #expect(rig.presenter.shown[7] == nil)
        #expect(rig.controller.notice == .barNotTransparent(displayID: 7))
    }

    @Test("two displays owing a confirmation never exceed four image calls a second or a session per 12 s")
    func twoDisplaysShareTheBudget() {
        let rig = Rig()
        rig.bars.append(CoverBar(displayID: 9, frame: CGRect(x: 1728, y: 0, width: 1920, height: 30), scale: 1, notch: nil))
        rig.standardBar()
        rig.reader.slotsByDisplay[9] = [rig.slot(1, 500, 38), rig.slot(2, 538, 38), rig.slot(20, 600, 40)]
        rig.startWhole()
        var calls = [(at: rig.now, total: rig.capturer.calls)]
        for _ in 0..<120 {
            rig.advance(1)
            rig.controller.tick()
            if calls.last?.total != rig.capturer.calls { calls.append((rig.now, rig.capturer.calls)) }
        }
        #expect(calls.first?.total == 4)
        // Every burst is at most four calls, and bursts are 12 s or more apart.
        #expect(zip(calls, calls.dropFirst()).allSatisfy { $1.total - $0.total <= 4 && $1.at - $0.at >= 12 })
        #expect(Set(rig.captures.map(\.displayID)) == [7, 9])
        #expect(rig.captures.filter { $0.displayID == 9 }.contains { $0.reason == .confirm })
        #expect(rig.captures.filter { $0.displayID == 9 }.last?.step == 2)
    }

    // MARK: - Plan 2026-11-18-cover-stale-and-lost, D2 and D3

    @Test("a bar that lists the members' slots while none of their pids is coverable says so, once")
    func diagnosisNoCandidate() {
        let rig = Rig()
        rig.standardBar()
        rig.start([9])
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.diagnoses == [
            CoverBarDiagnosis(displayID: 7, readable: true, coverable: 1, slots: 3, owners: 3, candidates: 0, covered: 0, silent: 0, failed: 0, other: 0, hasNotch: false),
        ])
    }

    @Test("a candidate left uncovered is counted by what its hit test answered")
    func diagnosisAnswers() {
        let rig = Rig()
        rig.silentOwners = [3]
        rig.failingOwners = [2]
        // 1 answers, 2 fails, 3 answers nothing, 4 lies under another item's window (20 answers there).
        rig.bar([rig.slot(1, 400, 30), rig.slot(2, 440, 30), rig.slot(3, 480, 30), rig.slot(20, 600, 40)])
        rig.reader.slotsByDisplay[7] = [rig.slot(1, 400, 30), rig.slot(2, 440, 30), rig.slot(3, 480, 30), rig.slot(4, 600, 40), rig.slot(20, 600, 40)]
        rig.start([1, 2, 3, 4])
        #expect(rig.diagnoses.last == CoverBarDiagnosis(
            displayID: 7, readable: true, coverable: 4, slots: 5, owners: 5, candidates: 4, covered: 1, silent: 1, failed: 1, other: 1, hasNotch: false
        ))
    }

    @Test("a tree whose every slot has one owner is told apart from one that cannot be read")
    func diagnosisEmptyAndUnreadable() {
        let rig = Rig()
        rig.standardBar()
        rig.start()
        // Mission Control's emptiness: the agent's own slots only.
        rig.reader.slotsByDisplay[7] = [rig.slot(99, 500, 20), rig.slot(99, 540, 20)]
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.diagnoses.last == CoverBarDiagnosis(
            displayID: 7, readable: true, coverable: 2, slots: 2, owners: 1, candidates: 0, covered: 0, silent: 0, failed: 0, other: 0, hasNotch: false
        ))
        rig.reader.slotsByDisplay[7] = .some(nil)
        rig.advance(1)
        rig.controller.tick()
        #expect(rig.diagnoses.last?.readable == false)
        #expect(rig.diagnoses.last?.coverable == 2)
    }

    @Test("hit answers that flicker while the same slots stay uncovered are one diagnosis, not one a second")
    func diagnosisIgnoresFlicker() {
        let rig = Rig()
        rig.failingOwners = [2]
        rig.standardBar()
        rig.start()
        #expect(rig.diagnoses.count == 1)
        #expect(rig.diagnoses.last?.failed == 1)
        for second in 0..<6 {
            // Member 2 fails one second and answers nothing the next; it never stands, and stays uncovered.
            rig.failingOwners = second % 2 == 0 ? [] : [2]
            rig.silentOwners = second % 2 == 0 ? [2] : []
            rig.run(seconds: 1)
        }
        #expect(rig.diagnoses.count == 1)
        rig.failingOwners = []
        rig.silentOwners = []
        rig.run(seconds: 1)
        #expect(rig.diagnoses.count == 2, "covered: the coverage changed")
        #expect(rig.diagnoses.last?.covered == 2)
    }

    @Test("a display that went and came back is diagnosed afresh, the same diagnosis included")
    func diagnosisAfterDisplayReturns() {
        let rig = Rig()
        rig.standardBar()
        rig.start([9])
        #expect(rig.diagnoses.count == 1)
        let bars = rig.bars
        rig.bars = []
        rig.run(seconds: 1)
        rig.bars = bars
        rig.run(seconds: 1)
        #expect(rig.diagnoses.count == 2)
        #expect(rig.diagnoses.first == rig.diagnoses.last)
    }

    @Test("a diagnosis that did not change is not said again; going off forgets it")
    func diagnosisOnChange() {
        let rig = Rig()
        rig.standardBar()
        rig.start()
        let first = rig.diagnoses.count
        #expect(first == 1)
        for _ in 0..<3 {
            rig.advance(1)
            rig.controller.tick()
        }
        #expect(rig.diagnoses.count == first)
        rig.controller.sync(active: false, coverable: [])
        rig.start()
        #expect(rig.diagnoses.count == first + 1)
    }

    @Test("a capture says how bright the strip is, whether it equals the one held, and whether the bar is transparent")
    func captureFacts() {
        let rig = Rig()
        rig.standardBar()
        rig.start()
        #expect(rig.captures.count == 1)
        #expect(rig.captures.first?.displayID == 7)
        #expect(rig.captures.first?.equal == nil)
        #expect(rig.captures.first?.transparent == true)
        // The fake's gray is converted on drawing: the strip's own brightness is the measure.
        #expect(rig.captures.first?.luma == CoverPixels.luma(FakeCapturer.image(width: 10, gray: 40)))

        // A dim strip, as the owner's Sidecar bar on 2026-11-18.
        rig.capturer.gray = 20
        rig.key = "space2"
        rig.advance(13)
        rig.controller.tick()
        #expect(rig.captures.count == 2)
        #expect(rig.captures.last?.equal == false)
        #expect(rig.captures.last?.luma == CoverPixels.luma(FakeCapturer.image(width: 10, gray: 20)))
        #expect((rig.captures.last?.luma ?? 1) < (rig.captures.first?.luma ?? 0))

        rig.key = "space3"
        rig.advance(13)
        rig.controller.tick()
        #expect(rig.captures.last?.equal == true)
        #expect(rig.captures.last?.failed == false)
    }

    @Test("a capture that returns nothing is said to have failed")
    func captureFailure() {
        let rig = Rig()
        rig.standardBar()
        rig.capturer.fails = true
        rig.start()
        #expect(rig.captures.first == CoverCaptureFact(
            displayID: 7, luma: nil, equal: nil, transparent: false, failed: true, reason: .size, step: 0, unequalRun: 0
        ))
        #expect(rig.presenter.shown[7] == nil)
    }
}

@Suite("CoverPixels")
struct CoverPixelsTests {
    /// A two-column strip of one colour, its 8-bit values given as they are in Display P3.
    static func displayP3(_ red: Int, _ green: Int, _ blue: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(colorSpace: space, components: [CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return context.makeImage()!
    }

    @Test("strips are compared as captured: a difference of one is not widened by a colour conversion (MEASURED, T5 run 7)")
    func comparedAsCaptured() {
        // The two pixels of run 7: the panel 24, the background 25 in green; converted to device RGB they read 15 and 18.
        let panel = Self.displayP3(91, 24, 106)
        #expect(CoverPixels.sameColumns(panel, Self.displayP3(91, 25, 106)) == [true, true])
        #expect(CoverPixels.sameColumns(panel, Self.displayP3(91, 27, 106)) == [false, false])
    }

    @Test("a bar that shows what lies below it is transparent; one that differs everywhere is not")
    func transparency() {
        let below = FakeCapturer.image(width: 100, gray: 40)
        #expect(CoverPixels.isTransparent(below: below, onScreen: FakeCapturer.image(width: 100, gray: 41), slots: [10...20], scale: 2))
        #expect(!CoverPixels.isTransparent(below: below, onScreen: FakeCapturer.image(width: 100, gray: 90), slots: [10...20], scale: 2))
        #expect(!CoverPixels.isTransparent(below: below, onScreen: FakeCapturer.image(width: 90, gray: 40), slots: [], scale: 2))
        #expect(!CoverPixels.isTransparent(below: below, onScreen: below, slots: [0...50], scale: 2))
    }

    @Test("two strips are one background when nearly every column is the same, the columns of the blocks too")
    func sameBackground() {
        let a = FakeCapturer.image(width: 400, gray: 40)
        #expect(CoverPixels.isSameBackground(a, FakeCapturer.image(width: 400, gray: 41), blocks: [10...40], scale: 2) == true)
        #expect(CoverPixels.isSameBackground(a, FakeCapturer.image(width: 400, gray: 20), blocks: [10...40], scale: 2) == false)
        // 1 % of the strip changed, all of it behind the block.
        let behind = FakeCapturer.image(width: 400, gray: 40, patch: 40..<44, patchGray: 200)
        #expect(CoverPixels.isSameBackground(a, behind, blocks: [18...24], scale: 2) == false)
        #expect(CoverPixels.isSameBackground(a, behind, blocks: [100...140], scale: 2) == true)
        #expect(CoverPixels.isSameBackground(a, behind, blocks: [], scale: 2) == true)
        #expect(CoverPixels.isSameBackground(a, FakeCapturer.image(width: 300, gray: 40), blocks: [], scale: 2) == nil)
    }

    @Test("a strip's brightness runs from 0 for black to 1 for white")
    func luma() {
        #expect(abs((CoverPixels.luma(FakeCapturer.image(width: 10, gray: 255)) ?? 0) - 1) < 0.01)
        #expect(abs((CoverPixels.luma(FakeCapturer.image(width: 10, gray: 0)) ?? 1) - 0) < 0.01)
    }
}
