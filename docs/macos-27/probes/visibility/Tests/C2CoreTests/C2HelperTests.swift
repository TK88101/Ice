// T2 (docs/plans/2026-09-28-c2-protocol.md sections 2-3): the new helper
// roles' pure parts -- role names, the menus command, and the frontmost-menu
// width calibration.
import C2Core
import Testing

@Suite("C2Helper")
struct C2HelperTests {
    @Test("hidden roles 2-4 parse; anything else is not a C2 role")
    func hiddenRoles() {
        #expect(C2HelperRole.parse("hidden-2") == .hidden(2))
        #expect(C2HelperRole.parse("hidden-4") == .hidden(4))
        #expect(C2HelperRole.parse("hidden-1") == nil)
        #expect(C2HelperRole.parse("hidden-5") == nil)
        #expect(C2HelperRole.parse("hidden-x") == nil)
        #expect(C2HelperRole.parse("menus") == .menus)
        #expect(C2HelperRole.parse("target") == nil)
    }

    @Test("identifiers are vz-<role>")
    func identifiers() {
        #expect(C2HelperRole.hidden(3).identifier == "vz-hidden-3")
        #expect(C2HelperRole.menus.identifier == "vz-menus")
    }

    @Test("menus <n> parses within 0...40; anything else is refused")
    func menusCommand() {
        #expect(C2MenusCommand.parse("menus 0") == 0)
        #expect(C2MenusCommand.parse("menus 40") == 40)
        #expect(C2MenusCommand.parse("menus 41") == nil)
        #expect(C2MenusCommand.parse("menus -1") == nil)
        #expect(C2MenusCommand.parse("menus") == nil)
        #expect(C2MenusCommand.parse("menus 3 4") == nil)
        #expect(C2MenusCommand.parse("length 3") == nil)
    }

    @Test("width classes parse by name")
    func widthNames() {
        #expect(C2MenuWidth(rawValue: "short") == .short)
        #expect(C2MenuWidth(rawValue: "mid") == .mid)
        #expect(C2MenuWidth(rawValue: "long") == .long)
        #expect(C2MenuWidth(rawValue: "wide") == nil)
    }

    @Test("calibration: short wants the last title ending at most 400")
    func calibrateShort() {
        #expect(C2MenuWidth.short.adjust(lastTitleEnd: 365) == .done)
        #expect(C2MenuWidth.short.adjust(lastTitleEnd: 401) == .fewer)
    }

    @Test("calibration: mid wants 700...770")
    func calibrateMid() {
        #expect(C2MenuWidth.mid.adjust(lastTitleEnd: 650) == .more)
        #expect(C2MenuWidth.mid.adjust(lastTitleEnd: 700) == .done)
        #expect(C2MenuWidth.mid.adjust(lastTitleEnd: 770) == .done)
        #expect(C2MenuWidth.mid.adjust(lastTitleEnd: 771) == .fewer)
    }

    @Test("calibration: long wants at least 1000")
    func calibrateLong() {
        #expect(C2MenuWidth.long.adjust(lastTitleEnd: 999) == .more)
        #expect(C2MenuWidth.long.adjust(lastTitleEnd: 1000) == .done)
    }

    @Test("calibration without any title span: more")
    func calibrateNoTitles() {
        #expect(C2MenuWidth.mid.adjust(lastTitleEnd: nil) == .more)
        #expect(C2MenuWidth.short.adjust(lastTitleEnd: nil) == .done)
    }
}

@Suite("C2MenuCalibration")
struct C2MenuCalibrationTests {
    @Test("starts at one menu; more until the class is reached, then done at that count")
    func climbsToMid() {
        var calibration = C2MenuCalibration(width: .mid)
        #expect(calibration.count == 1)
        #expect(calibration.next(lastTitleEnd: 105) == .send(2))
        #expect(calibration.next(lastTitleEnd: 165) == .send(3))
        #expect(calibration.next(lastTitleEnd: 720) == .done(3))
    }

    @Test("fewer steps down; short with no title at all is done at once")
    func stepsDown() {
        var calibration = C2MenuCalibration(width: .short)
        #expect(calibration.next(lastTitleEnd: 450) == .send(0))
        #expect(calibration.next(lastTitleEnd: nil) == .done(0))
    }

    @Test("overshooting a window both ways fails instead of oscillating")
    func oscillationFails() {
        var calibration = C2MenuCalibration(width: .mid)
        #expect(calibration.next(lastTitleEnd: 690) == .send(2))
        #expect(calibration.next(lastTitleEnd: 790) == .failed("no menu count puts the last title in mid"))
        var down = C2MenuCalibration(width: .mid)
        #expect(down.next(lastTitleEnd: 790) == .send(0))
        #expect(down.next(lastTitleEnd: 690) == .failed("no menu count puts the last title in mid"))
    }

    @Test("out of range, or past the step budget, fails")
    func boundsFail() {
        var low = C2MenuCalibration(width: .short)
        #expect(low.next(lastTitleEnd: 450) == .send(0))
        #expect(low.next(lastTitleEnd: 450) == .failed("no menu count puts the last title in short"))
        var high = C2MenuCalibration(width: .long)
        var last: C2MenuCalibration.Step = .send(1)
        for _ in 0..<C2MenusCommand.maxMenus { last = high.next(lastTitleEnd: 10) }
        #expect(last == .failed("no menu count puts the last title in long"))
    }
}
