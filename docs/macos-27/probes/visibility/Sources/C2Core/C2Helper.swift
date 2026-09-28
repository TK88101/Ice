// T2 (docs/plans/2026-09-28-c2-protocol.md sections 2-3): the new vzhelper
// roles' pure parts. vzhelper parses with these; the stage calibrates the
// frontmost-menu width with `C2MenuWidth.adjust` against AX title spans read
// in the isolated account (nothing is calibrated on the owner's bar).

public enum C2HelperRole: Equatable, Sendable {
    /// An extra hidden-section item, 2...4 (the Target is item 1).
    case hidden(Int)
    /// The frontmost app whose own menu titles set the menu width.
    case menus

    public static let hiddenRange = 2...4

    public static func parse(_ name: String) -> C2HelperRole? {
        if name == "menus" { return .menus }
        let prefix = "hidden-"
        guard name.hasPrefix(prefix), let index = Int(name.dropFirst(prefix.count)), hiddenRange.contains(index) else { return nil }
        return .hidden(index)
    }

    public var identifier: String {
        switch self {
        case .hidden(let index): "vz-hidden-\(index)"
        case .menus: "vz-menus"
        }
    }
}

/// `menus <n>`: the Menus helper shows exactly n title menus.
public enum C2MenusCommand {
    public static let maxMenus = 40

    public static func parse(_ line: String) -> Int? {
        let words = line.split(separator: " ")
        guard words.count == 2, words[0] == "menus", let count = Int(words[1]), (0...maxMenus).contains(count) else { return nil }
        return count
    }
}

public enum C2MenuWidth: String, Equatable, Sendable, CaseIterable {
    case short
    case mid
    case long

    public enum Adjustment: Equatable, Sendable {
        case more
        case fewer
        case done
    }

    /// Where the frontmost app's last title must end (section 3).
    public static let shortMaxEnd = 400.0
    public static let midRange = 700.0...770.0
    public static let longMinEnd = 1000.0

    /// `lastTitleEnd`: the right edge of the last title menu, `nil` when
    /// there is none.
    public func adjust(lastTitleEnd: Double?) -> Adjustment {
        switch self {
        case .short:
            guard let end = lastTitleEnd else { return .done }
            return end <= Self.shortMaxEnd ? .done : .fewer
        case .mid:
            guard let end = lastTitleEnd else { return .more }
            if end < Self.midRange.lowerBound { return .more }
            return end > Self.midRange.upperBound ? .fewer : .done
        case .long:
            guard let end = lastTitleEnd else { return .more }
            return end >= Self.longMinEnd ? .done : .more
        }
    }
}

/// Finds the menu count whose last title lands in `width`'s class: one step
/// per AX read of the Menus helper's own titles. Monotonic -- a direction
/// change means no count fits, which fails rather than oscillating; so does
/// leaving 0...`C2MenusCommand.maxMenus`.
public struct C2MenuCalibration: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case send(Int)
        case done(Int)
        case failed(String)
    }

    public let width: C2MenuWidth
    public private(set) var count = 1
    private var direction: C2MenuWidth.Adjustment?

    public init(width: C2MenuWidth) {
        self.width = width
    }

    public mutating func next(lastTitleEnd: Double?) -> Step {
        let adjustment = width.adjust(lastTitleEnd: lastTitleEnd)
        guard adjustment != .done else { return .done(count) }
        let failure = Step.failed("no menu count puts the last title in \(width.rawValue)")
        guard direction == nil || direction == adjustment else { return failure }
        direction = adjustment
        count += adjustment == .more ? 1 : -1
        guard (0...C2MenusCommand.maxMenus).contains(count) else { return failure }
        return .send(count)
    }
}
