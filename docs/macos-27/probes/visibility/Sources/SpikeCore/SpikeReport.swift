// T0: the results as the owner reads them -- band per k and menu, the click
// path, and the two stop rules of the plan's T0 row.
import C2Core

public struct ProfileResult: Equatable, Sendable, Codable {
    public let profile: SpikeProfile
    public let records: [StepRecord]
    public let band: Band?
    /// Why the profile could not be measured (launch, calibration, placement).
    public let problem: String?

    public init(profile: SpikeProfile, records: [StepRecord], band: Band?, problem: String?) {
        self.profile = profile
        self.records = records
        self.band = band
        self.problem = problem
    }
}

public struct PressTarget: Equatable, Sendable, Codable {
    public let profile: SpikeProfile
    public let length: Double

    public init(profile: SpikeProfile, length: Double) {
        self.profile = profile
        self.length = length
    }
}

public struct SpikeAResult: Equatable, Sendable, Codable {
    public let profiles: [ProfileResult]

    public init(profiles: [ProfileResult]) {
        self.profiles = profiles
    }

    public func band(members: Int, menu: C2MenuWidth) -> Band? {
        profiles.first { $0.profile == SpikeProfile(members: members, menu: menu) }?.band
    }

    /// The largest k with a band under `menu`.
    public func capacity(menu: C2MenuWidth) -> Int? {
        profiles.filter { $0.profile.menu == menu && $0.band != nil }.map(\.profile.members).max()
    }

    /// The plan's first stop rule: no band at k = 1 under any menu.
    public var noBandAtOne: Bool {
        !profiles.contains { $0.profile.members == 1 && $0.band != nil }
    }

    /// Spike B's profile and length: k = 1 short's midpoint, else mid's.
    public var pressTarget: PressTarget? {
        for menu in SpikeAPlan.standardMenus {
            if let band = band(members: 1, menu: menu) { return PressTarget(profile: SpikeProfile(members: 1, menu: menu), length: band.midpoint) }
        }
        return nil
    }

    private var menus: [C2MenuWidth] { profiles.map(\.profile.menu).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }

    static func menuName(_ menu: C2MenuWidth) -> String {
        switch menu {
        case .short: "短選單"
        case .mid: "中選單"
        case .long: "長選單"
        }
    }

    private func details(_ menu: C2MenuWidth) -> String {
        profiles.filter { $0.profile.menu == menu }.map { result in
            if let problem = result.problem { return "k=\(result.profile.members) 沒跑成：\(problem)" }
            if let band = result.band { return "k=\(result.profile.members) \(band.text)" }
            return "k=\(result.profile.members) 沒有區間"
        }.joined(separator: "，")
    }

    /// 藏得住幾個.
    public var hideLine: String {
        let menus = self.menus
        if menus.allSatisfy({ capacity(menu: $0) == nil }) {
            let parts = menus.map { "\(Self.menuName($0)) \(details($0))" }
            return "藏得住幾個：一個都藏不住（\(parts.joined(separator: "；"))）。"
        }
        let parts = menus.map { menu -> String in
            if let capacity = capacity(menu: menu) { return "\(Self.menuName(menu))下最多 \(capacity) 個（\(details(menu))）" }
            return "\(Self.menuName(menu))下一個都藏不住（\(details(menu))）"
        }
        return "藏得住幾個：\(parts.joined(separator: "；"))。"
    }
}

/// One AXPress on the pushed-off (or shown) member.
public struct PressTrial: Equatable, Sendable, Codable {
    /// The press call's `AXError` raw value once it returned; `nil` if it had not by the end of the trial.
    public let pressError: Int?
    /// Seconds from the press to the first sign of the menu; `nil` if none came.
    public let openedAfter: Double?
    /// Which signs came: `helper` (vzhelper's `menu open` line), `window` (a pop-up menu window of its pid).
    public let signals: [String]
    /// The menu was closed again (vzhelper's `menu close` line) before the next trial.
    public let closed: Bool

    public init(pressError: Int?, openedAfter: Double?, signals: [String], closed: Bool) {
        self.pressError = pressError
        self.openedAfter = openedAfter
        self.signals = signals
        self.closed = closed
    }
}

public enum ClickPath: String, Equatable, Sendable, Codable {
    case pushedOff
    case showPressRehide
    case none
}

public struct SpikeBResult: Equatable, Sendable, Codable {
    public let length: Double
    public let pushedOff: [PressTrial]
    public let fallback: [PressTrial]

    public init(length: Double, pushedOff: [PressTrial], fallback: [PressTrial]) {
        self.length = length
        self.pushedOff = pushedOff
        self.fallback = fallback
    }
}

public enum SpikeBRules {
    public static let trials = 5
    public static let needed = 4
    /// The plan's D3: the menu must be on screen within a second.
    public static let openTimeout = 1.0
    /// `kCGPopUpMenuWindowLevel`: the layer a status item's menu window is listed at.
    public static let popUpMenuWindowLayer = 101

    public static func opened(_ trial: PressTrial) -> Bool {
        guard let after = trial.openedAfter else { return false }
        return after <= openTimeout
    }

    public static func openedCount(_ trials: [PressTrial]) -> Int { trials.filter(opened).count }

    public static func path(_ result: SpikeBResult) -> ClickPath {
        if openedCount(result.pushedOff) >= needed { return .pushedOff }
        if openedCount(result.fallback) >= needed { return .showPressRehide }
        return .none
    }

    /// 點得開嗎, for a spike B that ran its trials.
    public static func clickLine(_ result: SpikeBResult) -> String {
        let length = "\(Band.format(result.length)) pt"
        let off = (result.pushedOff.count, openedCount(result.pushedOff))
        let back = (result.fallback.count, openedCount(result.fallback))
        switch path(result) {
        case .pushedOff:
            return "點得開嗎：點得開。被擠出去的狀態下按 AXPress，\(off.0) 次有 \(off.1) 次在 1 秒內開了選單（\(length)）。"
        case .showPressRehide:
            return "點得開嗎：擠出去時點不開（\(off.0) 次 \(off.1) 次）；先顯示、再按、再藏回去這條路點得開，\(back.0) 次有 \(back.1) 次在 1 秒內開了選單（\(length)）。"
        case .none:
            let fallback = result.fallback.isEmpty ? "先顯示再按這條路沒試" : "先顯示再按這條路 \(back.0) 次 \(back.1) 次"
            return "點得開嗎：點不開。擠出去時 \(off.0) 次 \(off.1) 次；\(fallback)（\(length)）。"
        }
    }
}

/// The run's two lines and the stop question, from spike A, spike B (or why
/// it has no result: not asked for, no k = 1 band, or `bProblem`).
public enum SpikeVerdict {
    public static func clickLine(a: SpikeAResult, b: SpikeBResult?, bProblem: String?, runB: Bool) -> String {
        if let b { return SpikeBRules.clickLine(b) }
        if !runB { return "點得開嗎：沒測（這次用 --no-b 跳過 spike B）。" }
        if a.noBandAtOne { return "點得開嗎：沒測（spike A 在 k=1 找不到區間，spike B 沒跑）。" }
        return "點得開嗎：沒測成（\(bProblem ?? "原因不明")）。"
    }

    /// The plan's T0 stop rules, as one yes-or-no question; `nil` when T1 may follow.
    public static func stopQuestion(a: SpikeAResult, b: SpikeBResult?, bProblem: String?, runB: Bool) -> String? {
        if a.noBandAtOne { return "k=1 找不到藏得住的長度，要不要繼續做 IceBar？（是／否）" }
        guard runB else { return nil }
        guard let b else { return "spike B 沒跑完（\(bProblem ?? "原因不明")），要不要繼續做 IceBar？（是／否）" }
        if SpikeBRules.path(b) == .none { return "找不到可用的點擊方式，要不要繼續做 IceBar？（是／否）" }
        return nil
    }

    public static func lines(a: SpikeAResult, b: SpikeBResult?, bProblem: String?, runB: Bool) -> [String] {
        [a.hideLine, clickLine(a: a, b: b, bProblem: bProblem, runB: runB)]
            + (stopQuestion(a: a, b: b, bProblem: bProblem, runB: runB).map { [$0] } ?? [])
    }
}
