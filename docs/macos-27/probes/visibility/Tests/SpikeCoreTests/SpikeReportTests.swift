// T0: the report the owner reads -- band per k, click path, the stop rules.
import C2Core
import SpikeCore
import Testing

@Suite("T0: spike report")
struct SpikeReportTests {
    func result(_ bands: [(Int, C2MenuWidth, Band?)]) -> SpikeAResult {
        SpikeAResult(profiles: bands.map { ProfileResult(profile: SpikeProfile(members: $0.0, menu: $0.1), records: [], band: $0.2, problem: nil) })
    }

    @Test("capacity per menu is the largest k with a band")
    func capacity() {
        let a = result([(1, .short, Band(lo: 600, hi: 800, count: 13)), (1, .mid, nil), (2, .short, Band(lo: 640, hi: 800, count: 11)), (2, .mid, nil),
                        (4, .short, nil), (4, .mid, nil)])
        #expect(a.capacity(menu: .short) == 2)
        #expect(a.capacity(menu: .mid) == nil)
        #expect(a.band(members: 1, menu: .short) == Band(lo: 600, hi: 800, count: 13))
        #expect(!a.noBandAtOne)
    }

    @Test("no band at k = 1 in either menu: the stop rule fires")
    func stopRule() {
        #expect(result([(1, .short, nil), (1, .mid, nil)]).noBandAtOne)
        #expect(!result([(1, .short, nil), (1, .mid, Band(lo: 600, hi: 616, count: 2))]).noBandAtOne)
        #expect(result([]).noBandAtOne)
    }

    @Test("spike B's length is the k = 1 short midpoint, else mid's, else none")
    func pressLength() {
        #expect(result([(1, .short, Band(lo: 600, hi: 800, count: 13)), (1, .mid, Band(lo: 640, hi: 700, count: 4))]).pressTarget
            == PressTarget(profile: SpikeProfile(members: 1, menu: .short), length: 700))
        #expect(result([(1, .short, nil), (1, .mid, Band(lo: 640, hi: 700, count: 4))]).pressTarget
            == PressTarget(profile: SpikeProfile(members: 1, menu: .mid), length: 670))
        #expect(result([(1, .short, nil)]).pressTarget == nil)
    }

    @Test("the owner's first line says how many hide, per menu, in plain words")
    func hideLine() {
        let a = result([(1, .short, Band(lo: 600, hi: 800, count: 13)), (1, .mid, nil), (2, .short, Band(lo: 640, hi: 800, count: 11)), (2, .mid, nil)])
        #expect(a.hideLine == "藏得住幾個：短選單下最多 2 個（k=1 600-800 pt，k=2 640-800 pt）；中選單下一個都藏不住（k=1 沒有區間，k=2 沒有區間）。")
        #expect(result([(1, .short, nil), (1, .mid, nil)]).hideLine == "藏得住幾個：一個都藏不住（短選單 k=1 沒有區間；中選單 k=1 沒有區間）。")
    }

    @Test("a profile that could not run is named, not counted")
    func problem() {
        let a = SpikeAResult(profiles: [ProfileResult(profile: SpikeProfile(members: 1, menu: .short), records: [], band: nil, problem: "menus: calibration failed")])
        #expect(a.hideLine == "藏得住幾個：一個都藏不住（短選單 k=1 沒跑成：menus: calibration failed）。")
        #expect(a.noBandAtOne)
    }

    @Test("the click path needs 4 of 5 opened within 1 s; pushed-off beats the fallback")
    func clickPath() {
        let opened = PressTrial(pressError: 0, openedAfter: 0.3, signals: ["helper", "window"], closed: true)
        let slow = PressTrial(pressError: 0, openedAfter: 1.4, signals: ["helper"], closed: true)
        let never = PressTrial(pressError: nil, openedAfter: nil, signals: [], closed: false)
        #expect(SpikeBRules.opened(opened))
        #expect(!SpikeBRules.opened(slow))
        #expect(!SpikeBRules.opened(never))
        let direct = SpikeBResult(length: 700, pushedOff: [opened, opened, opened, opened, never], fallback: [])
        #expect(SpikeBRules.path(direct) == .pushedOff)
        let fallback = SpikeBResult(length: 700, pushedOff: [never, never, opened, never, never], fallback: [opened, opened, opened, opened, opened])
        #expect(SpikeBRules.path(fallback) == .showPressRehide)
        let none = SpikeBResult(length: 700, pushedOff: [never, never, never, never, never], fallback: [slow, never, never, never, never])
        #expect(SpikeBRules.path(none) == .none)
    }

    @Test("the owner's second line says whether a click opens the menu")
    func clickLine() {
        let opened = PressTrial(pressError: 0, openedAfter: 0.3, signals: ["helper"], closed: true)
        let never = PressTrial(pressError: nil, openedAfter: nil, signals: [], closed: false)
        #expect(SpikeBRules.clickLine(SpikeBResult(length: 700, pushedOff: [opened, opened, opened, opened, opened], fallback: []))
            == "點得開嗎：點得開。被擠出去的狀態下按 AXPress，5 次有 5 次在 1 秒內開了選單（700 pt）。")
        #expect(SpikeBRules.clickLine(SpikeBResult(length: 700, pushedOff: [never, never, never, never, never], fallback: [opened, opened, opened, opened, never]))
            == "點得開嗎：擠出去時點不開（5 次 0 次）；先顯示、再按、再藏回去這條路點得開，5 次有 4 次在 1 秒內開了選單（700 pt）。")
        #expect(SpikeBRules.clickLine(SpikeBResult(length: 700, pushedOff: [never, never, never, never, never], fallback: [never, never, never, never, never]))
            == "點得開嗎：點不開。擠出去時 5 次 0 次；先顯示再按這條路 5 次 0 次（700 pt）。")
        #expect(SpikeBRules.clickLine(nil) == "點得開嗎：沒測（spike A 在 k=1 找不到區間，spike B 沒跑）。")
    }

    @Test("the stop question is one sentence, yes or no, only when a stop rule fires")
    func stopQuestion() {
        let a = result([(1, .short, nil), (1, .mid, nil)])
        #expect(SpikeVerdict.stopQuestion(a: a, b: nil) == "k=1 找不到藏得住的長度，要不要繼續做 IceBar？（是／否）")
        let ok = result([(1, .short, Band(lo: 600, hi: 800, count: 13))])
        let never = PressTrial(pressError: nil, openedAfter: nil, signals: [], closed: false)
        let bNone = SpikeBResult(length: 700, pushedOff: Array(repeating: never, count: 5), fallback: Array(repeating: never, count: 5))
        #expect(SpikeVerdict.stopQuestion(a: ok, b: bNone) == "找不到可用的點擊方式，要不要繼續做 IceBar？（是／否）")
        let opened = PressTrial(pressError: 0, openedAfter: 0.2, signals: ["helper"], closed: true)
        let bOK = SpikeBResult(length: 700, pushedOff: Array(repeating: opened, count: 5), fallback: [])
        #expect(SpikeVerdict.stopQuestion(a: ok, b: bOK) == nil)
        #expect(SpikeVerdict.stopQuestion(a: ok, b: nil) == "spike B 沒跑完，要不要繼續做 IceBar？（是／否）")
    }
}
