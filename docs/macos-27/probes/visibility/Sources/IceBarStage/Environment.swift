// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, section 4): every
// live seam one `vizprobe icebar-step` process needs, so a test can drive the
// real step orchestration on a fake bar. `vizprobe` builds the one live
// `IceBarEnvironment`; nothing here imports AppKit or Accessibility.
import C2Core
import Darwin
import IceBarOracle
import IceBarRunCore
import IceCore
import MenuBarCapture

/// One launched vzhelper.
public protocol IceBarHelper: AnyObject {
    var pid: pid_t { get }
    var isRunning: Bool { get }
    func send(_ line: String)
    /// vzhelper's `up` reply arrived within `timeout` seconds.
    func awaitUp(timeout: Double) -> Bool
    func quit(timeout: Double)
}

public protocol IceBarHelperLaunching {
    /// `nil` on any launch failure.
    func launch(app: String, bundleID: String, arguments: [String]) -> IceBarHelper?
}

/// The Menus helper of C2 (calibrated by `C2MenuCalibration` live).
public protocol IceBarMenus {
    /// `nil` on success, else why it could not be calibrated.
    func launchAndCalibrate(_ width: C2MenuWidth) -> String?
    func stillInPlace() -> Bool
    func quit()
}

public protocol IceBarWindowListing {
    /// Every window the window server lists, off-screen ones included.
    func windows() -> [WindowEntry]
}

public protocol IceBarClock {
    func now() -> Double
    /// Returns at or after `time`, never before.
    func sleep(until time: Double)
}

public protocol IceBarEvidence: AnyObject {
    func record(_ kind: String, _ fields: [String: Any])
    func keep(_ image: StripImage, label: String)
}

/// An owner of an item on the bar right now (the roster guard).
public struct BarOwner: Equatable {
    public let bundleID: String
    public let pid: pid_t

    public init(bundleID: String, pid: pid_t) {
        self.bundleID = bundleID
        self.pid = pid
    }
}

public struct IceBarEnvironment {
    public var capturer: any StripCapturing
    public var axReader: any MenuBarAXReading
    public var windows: any IceBarWindowListing
    public var launcher: any IceBarHelperLaunching
    public var menus: any IceBarMenus
    public var clock: any IceBarClock
    public var evidence: any IceBarEvidence
    public var geometry: BarGeometry
    public var barOwners: () -> [BarOwner]
    /// Deletes a helper bundle's preference domain; `true` on success.
    public var forgetDomain: (String) -> Bool
    /// The domain's keys; `nil` when it could not be read.
    public var domainKeys: (String) -> [String]?

    public init(capturer: any StripCapturing, axReader: any MenuBarAXReading, windows: any IceBarWindowListing,
                launcher: any IceBarHelperLaunching, menus: any IceBarMenus, clock: any IceBarClock,
                evidence: any IceBarEvidence, geometry: BarGeometry, barOwners: @escaping () -> [BarOwner],
                forgetDomain: @escaping (String) -> Bool, domainKeys: @escaping (String) -> [String]?) {
        self.capturer = capturer
        self.axReader = axReader
        self.windows = windows
        self.launcher = launcher
        self.menus = menus
        self.clock = clock
        self.evidence = evidence
        self.geometry = geometry
        self.barOwners = barOwners
        self.forgetDomain = forgetDomain
        self.domainKeys = domainKeys
    }
}

/// The oracle's templates: per glyph id, at the bar's scale, and the K1 chevron.
public struct StageTemplates {
    public let helpers: [String: OracleTemplate]
    public let chevron: OracleTemplate?

    public init(helpers: [String: OracleTemplate], chevron: OracleTemplate?) {
        self.helpers = helpers
        self.chevron = chevron
    }
}

public enum StepKind: Equatable {
    case s0
    /// One S-adv sweep, up and down.
    case sAdvSweep(SAdvVariant)
    /// S-adv's rest state with `«` up: the live (b) control's episodes.
    case sAdvChevron(SAdvVariant)
    /// One cycle per length, each retried up to three times when inconclusive.
    case s1Bracket([Double])
    /// Five cycles at the band's midpoint.
    case s1Confirm(Double)
}

public struct StepPlan {
    public let kind: StepKind
    public let members: Int
    public let menu: C2MenuWidth
    public let colouredMembers: Bool
    /// The `Glyph.allCases` names (`Roster.entries`).
    public let glyphOrder: [String]
    public let helperLifetimeSeconds: Int

    public init(kind: StepKind, members: Int, menu: C2MenuWidth, colouredMembers: Bool, glyphOrder: [String], helperLifetimeSeconds: Int) {
        self.kind = kind
        self.members = members
        self.menu = menu
        self.colouredMembers = colouredMembers
        self.glyphOrder = glyphOrder
        self.helperLifetimeSeconds = helperLifetimeSeconds
    }
}

public enum StepStatus: String, Codable, Equatable {
    case completed, inconclusive, noGo, safetyStop
}

public struct ReportPoint: Codable, Equatable {
    public let length: Double
    /// `C2Reading`'s name (`C2Reading(name:)` reads it back).
    public let reading: String
}

public struct ReportB: Codable, Equatable {
    public let episode: Int
    public let axChevron: Bool
    public let pixels: ChevronSighting

    public var observation: BObservation { BObservation(episode: episode, axChevron: axChevron, pixels: pixels) }
}

public struct S0Report: Codable, Equatable {
    public let outcome: S0Outcome
    public let c3: C3Outcome
    public let section8: Section8Outcome
}

/// What one step process hands its sequencer (`result.json`).
public struct StepReport: Codable, Equatable {
    public var status: StepStatus
    public var reason: String?
    public var roster: [RosterEntry] = []
    public var points: [ReportPoint] = []
    public var cycles: [CycleRecord] = []
    public var s0: S0Report?
    public var sweep: RepeatResult?
    public var chevronObservations: [ReportB] = []

    public init(status: StepStatus, reason: String? = nil) {
        self.status = status
        self.reason = reason
    }
}
