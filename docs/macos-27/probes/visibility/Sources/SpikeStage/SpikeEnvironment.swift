// IceBar build plan T0 (docs/plans/2026-10-03-icebar-build.md, section 7
// note 1): what the spike stage needs beyond route C's `IceBarEnvironment`
// -- the AX press and the helper's reply lines -- plus its plan and result.
// Nothing here imports AppKit or Accessibility; `vizprobe` supplies the live
// implementations.
import Darwin
import IceBarRunCore
import SpikeCore

public protocol SpikePressing {
    /// Starts one `kAXPressAction` on the item of `pid` whose `AXIdentifier`
    /// is `identifier`, and returns at once: the call may not come back until
    /// the menu it opened is closed again.
    func beginPress(pid: pid_t, identifier: String)
    /// The last press call's result once it returned -- the `AXError` raw
    /// value and the seconds it took -- or `nil` while it is still pending.
    func pressResult() -> (error: Int, seconds: Double)?
}

/// A helper whose reply lines can be awaited by kind (vzhelper's `menu` line).
public protocol SpikeReplyReading: AnyObject {
    func awaitReply(_ kind: String, timeout: Double) -> [String: Any]?
}

public struct SpikeStagePlan {
    public var profiles: [SpikeProfile]
    public var lengths: SpikeLengths
    public var runB: Bool
    /// `Glyph.allCases` names (`Roster.entries`).
    public var glyphOrder: [String]
    public var helperLifetimeSeconds: Int

    /// Route C's cadence: the warm-up (the capture indicator settles) and the
    /// settle after a spacer write or a helper change.
    public static let cadence = CadenceParameters.preRegistered
    public static let bracketGap = 0.5
    public static let trialGap = 1.0

    public init(profiles: [SpikeProfile], lengths: SpikeLengths, runB: Bool, glyphOrder: [String], helperLifetimeSeconds: Int) {
        self.profiles = profiles
        self.lengths = lengths
        self.runB = runB
        self.glyphOrder = glyphOrder
        self.helperLifetimeSeconds = helperLifetimeSeconds
    }
}

public struct SpikeRunResult: Equatable {
    public let a: SpikeAResult
    public let b: SpikeBResult?
    /// Why spike B could not run to its trials (launch, calibration, not hidden at the length).
    public let bProblem: String?
    /// Whether spike B was asked for at all (`--no-b` skips it).
    public let runB: Bool

    public init(a: SpikeAResult, b: SpikeBResult?, bProblem: String?, runB: Bool) {
        self.a = a
        self.b = b
        self.bProblem = bProblem
        self.runB = runB
    }

    /// The owner's lines: 藏得住幾個, 點得開嗎, and the stop question if one applies.
    public var lines: [String] { SpikeVerdict.lines(a: a, b: b, bProblem: bProblem, runB: runB) }

    public var stopQuestion: String? { SpikeVerdict.stopQuestion(a: a, b: b, bProblem: bProblem, runB: runB) }
}
