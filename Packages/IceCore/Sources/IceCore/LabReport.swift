/// The lines of Ice's lab report (plan 2026-10-07-icebar-preference-hiding,
/// S4 design D1): JSON, one object per line, numbered, so the lab runner's
/// tool (`lab-tool.py`) can tell a complete report from a damaged one. Items
/// are named by bundle id and Accessibility identifier, never by title.

/// A JSON value and its text. IceCore imports nothing, so it writes its own;
/// object keys are sorted, which makes a line a stable thing to test.
public indirect enum LabJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([LabJSON])
    case object([String: LabJSON])

    public var text: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return Self.text(of: value)
        case .string(let value): return Self.quoted(value)
        case .array(let values): return "[" + values.map(\.text).joined(separator: ",") + "]"
        case .object(let fields):
            return "{" + fields.keys.sorted().map { Self.quoted($0) + ":" + (fields[$0] ?? .null).text }.joined(separator: ",") + "}"
        }
    }

    /// The largest magnitude written as a whole number; beyond it a `Double`
    /// no longer holds every integer.
    private static let wholeLimit = 9_007_199_254_740_992.0

    private static func text(of value: Double) -> String {
        guard value.isFinite else { return "null" }
        if value == value.rounded(), abs(value) < wholeLimit {
            return String(Int64(value))
        }
        return "\(value)"
    }

    private static func quoted(_ value: String) -> String {
        var text = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case _ where scalar.value < 0x20:
                let hex = String(scalar.value, radix: 16)
                text += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: text.unicodeScalars.append(scalar)
            }
        }
        return text + "\""
    }

    static func optional(_ value: Double?) -> LabJSON { value.map(LabJSON.number) ?? .null }
    static func optional(_ value: String?) -> LabJSON { value.map(LabJSON.string) ?? .null }
    static func optional(_ value: Bool?) -> LabJSON { value.map(LabJSON.bool) ?? .null }
    static func frame(_ rect: BarRect?) -> LabJSON {
        rect.map { .array([$0.minX, $0.minY, $0.width, $0.height].map(LabJSON.number)) } ?? .null
    }
}

/// An item by what the runner knows it by.
public struct LabReportItem: Equatable, Sendable {
    public let namespace: String
    public let identifier: String

    public init(namespace: String, identifier: String) {
        self.namespace = namespace
        self.identifier = identifier
    }

    public init(_ key: ItemKey) {
        self.init(namespace: key.namespace, identifier: key.identifier)
    }

    /// A roster member: by the key it was read with, else (the read no
    /// longer has it) by the key it was last read with, else by its tag. The
    /// roster event and the snapshot both name members this way, so a member
    /// keeps its name while it goes stale and until it is dropped.
    public init(member: PreferenceHidingMember, lastKey: ItemKey?) {
        self.init(namespace: member.tag.namespace, identifier: (member.key ?? lastKey)?.identifier ?? member.tag.title)
    }

    var json: LabJSON {
        .object(["namespace": .string(namespace), "identifier": .string(identifier)])
    }
}

/// One roster entry.
public struct LabReportMember: Equatable, Sendable {
    public let namespace: String
    /// The tag's title for a member the read no longer has (it has no key).
    public let identifier: String
    public let pid: Int32?
    /// `LabReportNames.condition`.
    public let condition: String
    public let pressable: Bool
    public let frame: BarRect?

    public init(namespace: String, identifier: String, pid: Int32?, condition: String, pressable: Bool, frame: BarRect?) {
        self.namespace = namespace
        self.identifier = identifier
        self.pid = pid
        self.condition = condition
        self.pressable = pressable
        self.frame = frame
    }

    var json: LabJSON {
        .object([
            "namespace": .string(namespace), "identifier": .string(identifier),
            "pid": .optional(pid.map(Double.init)), "condition": .string(condition),
            "pressable": .bool(pressable), "frame": .frame(frame),
        ])
    }
}

/// One IceBar cell.
public struct LabReportCell: Equatable, Sendable {
    public let namespace: String
    public let identifier: String
    /// `MenuBarItemManager.isIceBarCellDisabled`.
    public let disabled: Bool

    public init(namespace: String, identifier: String, disabled: Bool) {
        self.namespace = namespace
        self.identifier = identifier
        self.disabled = disabled
    }

    var json: LabJSON {
        .object(["namespace": .string(namespace), "identifier": .string(identifier), "disabled": .bool(disabled)])
    }
}

/// One member's check at the rest's last observation.
public struct LabReportCheck: Equatable, Sendable {
    public let namespace: String
    public let identifier: String
    /// `VerificationSummary.name(of:)`.
    public let outcome: String

    public init(namespace: String, identifier: String, outcome: String) {
        self.namespace = namespace
        self.identifier = identifier
        self.outcome = outcome
    }

    var json: LabJSON {
        .object(["namespace": .string(namespace), "identifier": .string(identifier), "outcome": .string(outcome)])
    }
}

/// One of Ice's control items as the last discovery set read it.
public struct LabReportControlItem: Equatable, Sendable {
    public let frame: BarRect?
    /// On the bar, where a boundary or an icon may be read from it.
    public let usable: Bool

    public init(frame: BarRect?, usable: Bool) {
        self.frame = frame
        self.usable = usable
    }

    var json: LabJSON {
        .object(["frame": .frame(frame), "usable": .bool(usable)])
    }
}

/// What the hiding machine contributes to a snapshot.
public struct LabReportMachineFacts: Equatable, Sendable {
    public let phase: String
    /// `IceBarHidingStatus.logSummary`.
    public let status: String
    public let lengthSet: Bool
    public let lengthApplied: Bool
    public let checks: [ItemKey: SectionItemCheck]
    public let chevronListed: Bool?
}

extension IceBarHidingMachine {
    public var labFacts: LabReportMachineFacts {
        var checks = [ItemKey: SectionItemCheck]()
        if case .resting(let rest) = phase {
            checks = rest.checks
        }
        return LabReportMachineFacts(
            phase: LabReportNames.phase(phase), status: status.logSummary, lengthSet: lengthSet,
            lengthApplied: lengthApplied, checks: checks, chevronListed: chevronListed
        )
    }
}

/// Everything the runner judges a scenario by, read at one moment.
public struct LabReportSnapshot: Equatable, Sendable {
    public let phase: String
    public let status: String
    public let lengthSet: Bool
    public let lengthApplied: Bool
    /// The hidden control item's own value; `nil` at standard length, and
    /// always `nil` while lengths are held.
    public let calibratedHiddenLength: Double?
    public let isIceBarOffered: Bool
    public let isIceBarPresented: Bool
    public let isInteracting: Bool
    public let roster: [LabReportMember]
    public let blockers: [LabReportItem]
    public let cells: [LabReportCell]
    public let cacheVisible: [LabReportItem]
    public let cacheHidden: [LabReportItem]
    public let cacheAlwaysHidden: [LabReportItem]
    /// `nil`: the icon is right of its hidden divider.
    public let iconPlacement: String?
    public let hiddenBoundaryUsable: Bool
    public let icon: LabReportControlItem?
    public let hiddenDivider: LabReportControlItem?
    public let alwaysHiddenDivider: LabReportControlItem?
    /// `LabReportNames.completeness` of the last discovery set.
    public let completeness: String?
    /// How many discovery passes have completed.
    public let pass: Int
    public let checks: [LabReportCheck]
    public let chevronListed: Bool?

    public init(
        phase: String, status: String, lengthSet: Bool, lengthApplied: Bool, calibratedHiddenLength: Double?,
        isIceBarOffered: Bool, isIceBarPresented: Bool, isInteracting: Bool, roster: [LabReportMember],
        blockers: [LabReportItem], cells: [LabReportCell], cacheVisible: [LabReportItem], cacheHidden: [LabReportItem],
        cacheAlwaysHidden: [LabReportItem], iconPlacement: String?, hiddenBoundaryUsable: Bool,
        icon: LabReportControlItem?, hiddenDivider: LabReportControlItem?, alwaysHiddenDivider: LabReportControlItem?,
        completeness: String?, pass: Int, checks: [LabReportCheck], chevronListed: Bool?
    ) {
        self.phase = phase
        self.status = status
        self.lengthSet = lengthSet
        self.lengthApplied = lengthApplied
        self.calibratedHiddenLength = calibratedHiddenLength
        self.isIceBarOffered = isIceBarOffered
        self.isIceBarPresented = isIceBarPresented
        self.isInteracting = isInteracting
        self.roster = roster
        self.blockers = blockers
        self.cells = cells
        self.cacheVisible = cacheVisible
        self.cacheHidden = cacheHidden
        self.cacheAlwaysHidden = cacheAlwaysHidden
        self.iconPlacement = iconPlacement
        self.hiddenBoundaryUsable = hiddenBoundaryUsable
        self.icon = icon
        self.hiddenDivider = hiddenDivider
        self.alwaysHiddenDivider = alwaysHiddenDivider
        self.completeness = completeness
        self.pass = pass
        self.checks = checks
        self.chevronListed = chevronListed
    }

    /// The snapshot's keys, in the order of the properties above: the
    /// runner's tool keeps the same list (`test-lab.sh` compares them).
    public static let keys = [
        "phase", "status", "lengthSet", "lengthApplied", "calibratedHiddenLength", "isIceBarOffered",
        "isIceBarPresented", "isInteracting", "roster", "blockers", "cells", "cacheVisible", "cacheHidden",
        "cacheAlwaysHidden", "iconPlacement", "hiddenBoundaryUsable", "icon", "hiddenDivider",
        "alwaysHiddenDivider", "completeness", "pass", "checks", "chevronListed",
    ]

    var fields: [String: LabJSON] {
        [
            "phase": .string(phase), "status": .string(status), "lengthSet": .bool(lengthSet),
            "lengthApplied": .bool(lengthApplied), "calibratedHiddenLength": .optional(calibratedHiddenLength),
            "isIceBarOffered": .bool(isIceBarOffered), "isIceBarPresented": .bool(isIceBarPresented),
            "isInteracting": .bool(isInteracting), "roster": .array(roster.map(\.json)),
            "blockers": .array(blockers.map(\.json)), "cells": .array(cells.map(\.json)),
            "cacheVisible": .array(cacheVisible.map(\.json)), "cacheHidden": .array(cacheHidden.map(\.json)),
            "cacheAlwaysHidden": .array(cacheAlwaysHidden.map(\.json)), "iconPlacement": .optional(iconPlacement),
            "hiddenBoundaryUsable": .bool(hiddenBoundaryUsable), "icon": icon?.json ?? .null,
            "hiddenDivider": hiddenDivider?.json ?? .null, "alwaysHiddenDivider": alwaysHiddenDivider?.json ?? .null,
            "completeness": .optional(completeness), "pass": .number(Double(pass)),
            "checks": .array(checks.map(\.json)), "chevronListed": .optional(chevronListed),
        ]
    }
}

/// One line of the report.
public enum LabReportEvent: Equatable, Sendable {
    case start(pid: Int32, bundleID: String?, holdLength: Bool)
    /// Each status the machine reports, at the moment it does.
    case status(String)
    /// Each length the machine decides, and what became of it.
    case length(LabReportLength, decided: Double?)
    /// Each roster the item manager publishes: the members.
    case roster([LabReportItem])
    case press(namespace: String, identifier: String, answer: String)
    case bar(action: String, answer: String)
    /// A line of standard input that is no command.
    case unknownCommand
    case snapshot(LabReportSnapshot)

    var name: String {
        switch self {
        case .start: "start"
        case .status: "status"
        case .length: "length"
        case .roster: "roster"
        case .press: "press"
        case .bar: "bar"
        case .unknownCommand: "unknownCommand"
        case .snapshot: "snapshot"
        }
    }

    /// The event's own fields, without the line's `event`, `seq` and `t`.
    var fields: [String: LabJSON] {
        switch self {
        case .start(let pid, let bundleID, let holdLength):
            return [
                "marker": .string(LabReportRule.marker), "pid": .number(Double(pid)),
                "bundleID": .optional(bundleID), "holdLength": .bool(holdLength),
            ]
        case .status(let status):
            return ["status": .string(status)]
        case .length(let length, let decided):
            return ["decided": .optional(decided), "applied": .optional(length.applied), "held": .bool(length.held)]
        case .roster(let members):
            return ["members": .array(members.map(\.json))]
        case .press(let namespace, let identifier, let answer):
            return ["namespace": .string(namespace), "identifier": .string(identifier), "answer": .string(answer)]
        case .bar(let action, let answer):
            return ["action": .string(action), "answer": .string(answer)]
        case .unknownCommand:
            return [:]
        case .snapshot(let snapshot):
            return snapshot.fields
        }
    }
}

/// Numbers the report's lines from 1, in the order they are written.
public struct LabReportWriter: Equatable, Sendable {
    private var seq = 0

    public init() {}

    /// The next line, without its newline. `seconds` is since the report began.
    public mutating func line(_ event: LabReportEvent, at seconds: Double) -> String {
        seq += 1
        var fields = event.fields
        fields["event"] = .string(event.name)
        fields["seq"] = .number(Double(seq))
        fields["t"] = .number(seconds)
        return LabJSON.object(fields).text
    }
}

/// The names the report uses for IceCore's cases. Explicit switches: a new
/// case fails to compile here instead of reaching the runner unnamed.
public enum LabReportNames {
    public static func phase(_ phase: IceBarHidingMachine.Phase) -> String {
        switch phase {
        case .off: "off"
        case .blocked: "blocked"
        case .quiet: "quiet"
        case .baselining: "baselining"
        case .calibrating: "calibrating"
        case .settling: "settling"
        case .resting: "resting"
        }
    }

    public static func condition(_ condition: PreferenceHidingMemberCondition) -> String {
        switch condition {
        case .ready: "ready"
        case .stacked: "stacked"
        case .stale(.ambiguousOrUnreadable): "stale:ambiguousOrUnreadable"
        case .stale(.missingFromRead): "stale:missingFromRead"
        case .stale(.parked): "stale:parked"
        case .stale(.noFrame): "stale:noFrame"
        }
    }

    public static func completeness(_ completeness: Completeness?) -> String? {
        switch completeness {
        case nil: nil
        case .complete: "complete"
        case .incomplete(let failed): "incomplete:\(failed.count)"
        case .permissionDenied: "permissionDenied"
        }
    }
}
