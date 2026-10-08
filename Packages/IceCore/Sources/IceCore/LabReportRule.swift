/// Ice's lab report mode (plan 2026-10-07-icebar-preference-hiding, S4 design
/// D1): a whole, normal launch that also writes what Ice holds -- its roster,
/// its state, each length it sets -- to standard output for the lab matrix's
/// runner, and takes that runner's commands. Nothing outside Ice can read
/// those, and a stand-in that recomputed them would not be Ice's.
///
/// The mode names items by bundle id and Accessibility identifier, takes
/// commands, and one of its arguments is a deliberate fault, so it is off
/// unless asked for at launch and refuses any identity that is not a
/// disposable lab one.

/// One report launch's settings.
public struct LabReportPlan: Equatable, Sendable {
    /// The fault of scenario 11: each length the machine decides is reported
    /// and not applied, so Ice believes it hid and nothing moved.
    public let holdLength: Bool

    public init(holdLength: Bool) {
        self.holdLength = holdLength
    }
}

public enum LabReportRefusal: Equatable, Sendable {
    /// The mode runs only under `LabReportRule.labBundleIDPrefix`.
    case notLabIdentity(String?)
    /// A launch argument that is neither `YES` nor `NO`.
    case badArgument(name: String, value: String)
}

public enum LabReportLaunch: Equatable, Sendable {
    case normal
    case refused(LabReportRefusal)
    case report(LabReportPlan)
}

/// What becomes of a length the machine decided.
public struct LabReportLength: Equatable, Sendable {
    /// What the hidden control item is given; `nil` is the standard length.
    public let applied: Double?
    /// The decided length was withheld (`LabReportPlan.holdLength`).
    public let held: Bool

    public init(applied: Double?, held: Bool) {
        self.applied = applied
        self.held = held
    }
}

/// A command of the lab runner, one per line of standard input.
public enum LabReportCommand: Equatable, Sendable {
    /// What a click on Ice's icon does when the IceBar is offered.
    case barOpen
    case barClose
    /// What a click on that member's IceBar cell does.
    case press(namespace: String, identifier: String)

    /// Exactly `bar open`, `bar close` or `press <namespace> <identifier>`;
    /// anything else is no command.
    public static func parse(_ line: String) -> LabReportCommand? {
        let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        switch words.first {
        case "bar" where words.count == 2 && words[1] == "open": return .barOpen
        case "bar" where words.count == 2 && words[1] == "close": return .barClose
        case "press" where words.count == 3: return .press(namespace: words[1], identifier: words[2])
        default: return nil
        }
    }
}

public enum LabReportPressRefusal: String, Equatable, Sendable {
    /// Ice does not rest at a length: there is no IceBar to click in.
    case notOffered
    case noCell
    /// Several cells carry that key: a click would be on one of them.
    case ambiguous
    /// The cell takes no click (a stale member, or a press that failed).
    case disabled
}

public enum LabReportPressTarget: Equatable, Sendable {
    /// The index of the cell in the list given.
    case cell(Int)
    case refused(LabReportPressRefusal)
}

public enum LabReportRule {
    /// `-IceLabReport YES` turns the mode on.
    public static let reportArgument = "IceLabReport"
    /// `-IceLabHoldLength YES` adds the fault; only read in report mode.
    public static let holdLengthArgument = "IceLabHoldLength"
    /// The lab runner's own disposable identities (`run-lab.sh` makes one per
    /// scenario run); an allowlist, as `LabTraceRule.labBundleIDPrefix` is,
    /// and another one, so neither mode runs under the other's identities.
    public static let labBundleIDPrefix = "com.icespike4.lab."
    /// The first line a report writes carries this, and the runner refuses a
    /// build whose binary lacks it. Longer than 15 bytes, so Swift stores it.
    public static let marker = "IceLabReport-start-v1"

    /// - Parameters:
    ///   - report: the value of `-IceLabReport` in the launch arguments only
    ///     (never a stored default), `nil` when absent.
    ///   - holdLength: the value of `-IceLabHoldLength`, likewise.
    ///   - bundleID: the running bundle's identifier.
    public static func launch(report: String?, holdLength: String?, bundleID: String?) -> LabReportLaunch {
        guard let report else { return .normal }
        guard let isOn = LabLaunchArguments.flag(report) else {
            return .refused(.badArgument(name: reportArgument, value: report))
        }
        guard isOn else { return .normal }
        guard let bundleID, LabLaunchArguments.isLabIdentity(bundleID, prefix: labBundleIDPrefix) else {
            return .refused(.notLabIdentity(bundleID))
        }
        let holdLengthValue = holdLength ?? "NO"
        guard let holds = LabLaunchArguments.flag(holdLengthValue) else {
            return .refused(.badArgument(name: holdLengthArgument, value: holdLengthValue))
        }
        return .report(LabReportPlan(holdLength: holds))
    }

    /// What the hidden control item is given for a length the machine
    /// decided. Outside report mode (`plan == nil`) and without the fault,
    /// the length itself. With the fault a length is withheld; retiring one
    /// (`nil`) withholds nothing.
    public static func appliedLength(_ decided: Double?, plan: LabReportPlan?) -> LabReportLength {
        guard let plan, plan.holdLength, decided != nil else {
            return LabReportLength(applied: decided, held: false)
        }
        return LabReportLength(applied: nil, held: true)
    }

    /// The one cell a press is for: as a click, it needs an offered IceBar
    /// and a cell that takes clicks.
    public static func pressTarget(
        namespace: String,
        identifier: String,
        cells: [LabReportCell],
        isIceBarOffered: Bool
    ) -> LabReportPressTarget {
        guard isIceBarOffered else { return .refused(.notOffered) }
        let matches = cells.indices.filter { cells[$0].namespace == namespace && cells[$0].identifier == identifier }
        guard let index = matches.first else { return .refused(.noCell) }
        guard matches.count == 1 else { return .refused(.ambiguous) }
        return cells[index].disabled ? .refused(.disabled) : .cell(index)
    }
}

/// How the lab modes read their launch arguments (`LabTraceRule`,
/// `LabReportRule`): one place for the gate that keeps either mode off a
/// real identity.
enum LabLaunchArguments {
    /// A prefix and at least one character after it.
    static func isLabIdentity(_ bundleID: String, prefix: String) -> Bool {
        bundleID.hasPrefix(prefix) && bundleID.count > prefix.count
    }

    /// Exactly `YES` or `NO`, as `defaults` writes them; anything else is not
    /// guessed at.
    static func flag(_ value: String) -> Bool? {
        switch value {
        case "YES": true
        case "NO": false
        default: nil
        }
    }
}
