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

    static func image(width: Int, gray: UInt8) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: 2, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: CGFloat(gray) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 2))
        return context.makeImage()!
    }

    func strips(of bar: CoverBar) -> CoverStrips? {
        calls += 2
        let width = Int(bar.frame.width * bar.scale)
        return CoverStrips(below: Self.image(width: width, gray: 40), onScreen: Self.image(width: width, gray: opaque ? 200 : 40))
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
        #expect(rig.reports.last?.reports.first?.verified.count == 2)
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
        #expect(rig.reports.last?.reports.first?.verified.contains(stale) == false)
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
        rig.advance(CoverController.refreshEvery + 1)
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
        #expect(rig.reports.last?.reports.first?.verified == [rig.slot(3, 440, 28), rig.slot(1, 500, 38)])
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
}
