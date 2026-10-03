// IceBar build plan T0 (docs/plans/2026-10-03-icebar-build.md, section 7
// note 1): spike A's profiles (k members x a menu width) and the spacer
// lengths it jumps to from rest. Pure.
import C2Core

public struct SpikeProfile: Equatable, Sendable, Codable {
    public let members: Int
    public let menu: C2MenuWidth

    public init(members: Int, menu: C2MenuWidth) {
        self.members = members
        self.menu = menu
    }

    public var name: String { "k\(members)-\(menu.rawValue)" }

    // `C2MenuWidth` is not Codable (and is another module's): the width is
    // written by its raw value.
    enum CodingKeys: String, CodingKey {
        case members
        case menu
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        members = try container.decode(Int.self, forKey: .members)
        let raw = try container.decode(String.self, forKey: .menu)
        guard let menu = C2MenuWidth(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .menu, in: container, debugDescription: "unknown menu width \(raw)")
        }
        self.menu = menu
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(members, forKey: .members)
        try container.encode(menu.rawValue, forKey: .menu)
    }
}

public enum SpikeAPlan {
    public static let standardMembers = [1, 2, 4, 8]
    /// `long` is excluded on purpose: a long frontmost menu makes the fold
    /// unreadable (FINDINGS, C2 sitting A), a known limit of the plan.
    public static let standardMenus: [C2MenuWidth] = [.short, .mid]

    /// k outermost, so the k = 1 verdict (the stop rule's) comes first.
    public static func profiles(members: [Int], menus: [C2MenuWidth]) -> [SpikeProfile] {
        members.flatMap { k in menus.map { SpikeProfile(members: k, menu: $0) } }
    }
}

/// The lengths of one sweep, inside vzhelper's `length` range (`C2Band`'s bounds).
public struct SpikeLengths: Equatable, Sendable, Codable {
    /// On C1's grid (600, 616, ..., 728, 840 are all on it), up to vzhelper's cap.
    public static let standard = SpikeLengths(from: 408, through: 1000, step: 16)!

    public let from: Double
    public let through: Double
    public let step: Double

    public init?(from: Double, through: Double, step: Double) {
        guard from >= C2Band.minimumLengthPt, through <= C2Band.maximumLengthPt, from <= through, step > 0 else { return nil }
        self.from = from
        self.through = through
        self.step = step
    }

    /// `from:through:step`.
    public init?(spec: String) {
        let parts = spec.split(separator: ":").map { Double($0) }
        guard parts.count == 3, let from = parts[0], let through = parts[1], let step = parts[2] else { return nil }
        self.init(from: from, through: through, step: step)
    }

    public var values: [Double] { Array(stride(from: from, through: through, by: step)) }
}
