// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q10-Q13): who is
// launched with which glyph (the roster-to-glyph manifest), where they must sit
// (the placement gate), and their window-server bounds (deviation 2 C3).
import IceBarOracle
import IceCore

public enum HelperRole: String, Codable, Sendable {
    case member, visible
}

/// One glyph helper: its id is its glyph's name (one helper, one glyph).
public struct RosterEntry: Equatable, Codable, Sendable {
    public let id: String
    public let role: HelperRole
    public let coloured: Bool
    public let bundleID: String
    /// The build.sh bundle it is launched from.
    public let app: String
    /// AX identifier and autosave name.
    public let identifier: String
}

public enum RosterError: Error, Equatable {
    case memberCount(Int)
    /// The glyph list is not the 19 the corpus validated.
    case glyphOrder
}

public enum Roster {
    /// Instrument plan D1: the corpus's references.
    public static let visibleGlyphs = ["reference", "alt", "target"]
    public static let glyphCount = 19
    public static let maxMembers = 16
    /// build.sh's bundles: members under the target's id, everything else under the protected id (no new id).
    public static let memberBundleID = "com.icespike4.target"
    public static let otherBundleID = "com.icespike4.protected"
    public static let bundleIDs = [memberBundleID, otherBundleID]
    public static let memberApp = "Target.app"
    public static let otherApp = "Protected.app"
    public static let spacerApp = otherApp
    public static let menusApp = "Menus.app"

    /// `glyphOrder`: `Glyph.allCases` names; members are the first `members` non-visible ones.
    public static func entries(glyphOrder: [String], members: Int, colouredMembers: Bool) throws(RosterError) -> [RosterEntry] {
        guard glyphOrder.count == glyphCount, Set(glyphOrder).count == glyphCount, Set(visibleGlyphs).isSubset(of: glyphOrder) else {
            throw .glyphOrder
        }
        guard (1...maxMembers).contains(members) else { throw .memberCount(members) }
        let memberIDs = glyphOrder.filter { !visibleGlyphs.contains($0) }.prefix(members)
        let visible = visibleGlyphs.map { entry($0, .visible, coloured: false) }
        return visible + memberIDs.map { entry($0, .member, coloured: colouredMembers) }
    }

    static func entry(_ glyph: String, _ role: HelperRole, coloured: Bool) -> RosterEntry {
        let member = role == .member
        return RosterEntry(id: glyph, role: role, coloured: coloured, bundleID: member ? memberBundleID : otherBundleID,
                           app: member ? memberApp : otherApp, identifier: "vz-icebar-\(glyph)")
    }

    public static func arguments(_ entry: RosterEntry, lifetimeSeconds: Int) -> [String] {
        ["--items", "1", "--identifiers", entry.identifier, "--glyphs", entry.id]
            + (entry.coloured ? ["--coloured"] : [])
            + ["--autosave", entry.identifier, "--lifetime", "\(lifetimeSeconds)"]
    }

    public static func spacerArguments(lifetimeSeconds: Int) -> [String] {
        ["--role", "spacer", "--autosave", "vz-icebar-spacer", "--lifetime", "\(lifetimeSeconds)"]
    }

    public static func menusArguments(lifetimeSeconds: Int) -> [String] {
        ["--role", "menus", "--lifetime", "\(lifetimeSeconds)"]
    }
}

public enum PlacementOutcome: Equatable, Sendable {
    case placed
    case missing(String)
    case offBar(String)
    case outOfOrder(String)
}

public enum PlacementCheck {
    /// Q11: members | spacer | visible helpers, left to right, all on the bar.
    public static func evaluate(frames: [String: ItemFrame], members: [String], spacer: String, visible: [String], barHeightPt: Double) -> PlacementOutcome {
        for id in members + [spacer] + visible {
            guard let frame = frames[id] else { return .missing(id) }
            guard OnBar.contains(minY: frame.minY, heightPt: barHeightPt) else { return .offBar(id) }
        }
        guard let spacerFrame = frames[spacer] else { return .missing(spacer) }
        if let late = members.first(where: { (frames[$0].map { $0.minX + $0.width } ?? .infinity) > spacerFrame.minX }) { return .outOfOrder(late) }
        let spacerEnd = spacerFrame.minX + spacerFrame.width
        if let early = visible.first(where: { (frames[$0]?.minX ?? -.infinity) < spacerEnd }) { return .outOfOrder(early) }
        return .placed
    }
}

/// One window-server list entry (`CGWindowListCopyWindowInfo`), reduced.
public struct WindowEntry: Equatable, Sendable {
    public let pid: Int32
    public let layer: Int
    public let bounds: WindowBounds

    public init(pid: Int32, layer: Int, bounds: WindowBounds) {
        self.pid = pid
        self.layer = layer
        self.bounds = bounds
    }
}

public enum StatusWindows {
    /// `kCGStatusWindowLevel`.
    public static let statusLayer = 25

    /// Q12: a helper's bounds are its one status-level window; none or several: not listed.
    public static func bounds(helpers: [String: Int32], windows: [WindowEntry]) -> [String: WindowBounds] {
        var result = [String: WindowBounds]()
        for (id, pid) in helpers {
            let own = windows.filter { $0.pid == pid && $0.layer == statusLayer }
            if own.count == 1 { result[id] = own[0].bounds }
        }
        return result
    }
}

/// One capture's C3 inputs: the roster, which of it is visible, its listed
/// bounds, and the visible helpers' AX frames of the same sample.
public struct C3Capture: Equatable, Sendable {
    public let roster: [String]
    public let visible: [String]
    public let bounds: [String: WindowBounds]
    public let visibleFrames: [String: ItemFrame]

    public init(roster: [String], visible: [String], bounds: [String: WindowBounds], visibleFrames: [String: ItemFrame]) {
        self.roster = roster
        self.visible = visible
        self.bounds = bounds
        self.visibleFrames = visibleFrames
    }
}

public enum C3Outcome: Codable, Equatable, Sendable {
    case holds
    case notListed(String)
    case mismatch(String)
}

public enum C3Check {
    public static let tolerancePt = 1.0

    /// Q13: every helper listed in every capture; every visible helper's bounds
    /// within 1 pt of its AX frame on x, y, width and height.
    public static func evaluate(_ captures: [C3Capture]) -> C3Outcome {
        guard !captures.isEmpty else { return .notListed("no capture") }
        for capture in captures {
            if let absent = capture.roster.first(where: { capture.bounds[$0] == nil }) { return .notListed(absent) }
        }
        for capture in captures {
            for id in capture.visible {
                guard let frame = capture.visibleFrames[id], let b = capture.bounds[id], matches(b, frame) else { return .mismatch(id) }
            }
        }
        return .holds
    }

    static func matches(_ b: WindowBounds, _ f: ItemFrame) -> Bool {
        abs(b.x - f.minX) <= tolerancePt && abs(b.y - f.minY) <= tolerancePt
            && abs(b.width - f.width) <= tolerancePt && abs(b.height - f.height) <= tolerancePt
    }
}
