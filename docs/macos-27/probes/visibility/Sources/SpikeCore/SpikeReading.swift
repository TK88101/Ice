// T0: what one length's brackets showed, and the outcome the band is built
// from. Fail closed: a length is clean only when every source agrees.

public enum ChevronRead: String, Equatable, Sendable, Codable {
    case present
    case absent
    case notEvaluable
}

/// One bracket (capture, AX read, capture) after the oracle.
public struct StepObservation: Equatable, Sendable {
    /// An on-bar `MenuBarAgent` frame of the chevron width was listed.
    public var axChevron: Bool
    /// The oracle's chevron sighting per capture.
    public var pixelChevron: [ChevronRead]
    /// Members the oracle identified (drawn, full) in either capture.
    public var membersSeen: [String]
    /// Visible helpers not drawn where AX puts them.
    public var visibleMissing: [String]
    /// The oracle could not tell two helpers apart.
    public var ambiguous: Bool

    public init(axChevron: Bool, pixelChevron: [ChevronRead], membersSeen: [String], visibleMissing: [String], ambiguous: Bool) {
        self.axChevron = axChevron
        self.pixelChevron = pixelChevron
        self.membersSeen = membersSeen
        self.visibleMissing = visibleMissing
        self.ambiguous = ambiguous
    }
}

public enum StepOutcome: Equatable, Sendable, Codable {
    case hiddenClean
    case folded(drawn: [String])
    case drawn([String])
    case unknown(String)

    public var isClean: Bool { self == .hiddenClean }
}

public struct StepRecord: Equatable, Sendable, Codable {
    public let length: Double
    public let outcome: StepOutcome

    public init(length: Double, outcome: StepOutcome) {
        self.length = length
        self.outcome = outcome
    }
}

public enum SpikeRules {
    /// `brackets`: every bracket taken at the length; `controlPassed`: the
    /// restore control after the collapse showed every member again.
    public static func outcome(_ brackets: [StepObservation], controlPassed: Bool) -> StepOutcome {
        guard controlPassed else { return .unknown("restore control") }
        guard !brackets.isEmpty else { return .unknown("no bracket") }
        if let missing = brackets.flatMap(\.visibleMissing).first { return .unknown("visible helper not drawn: \(missing)") }
        if brackets.contains(where: { $0.pixelChevron.contains(.notEvaluable) }) { return .unknown("chevron not evaluable") }
        if brackets.contains(where: \.ambiguous) { return .unknown("ambiguous") }
        let drawn = Array(Set(brackets.flatMap(\.membersSeen))).sorted()
        let folded = brackets.contains { $0.axChevron || $0.pixelChevron.contains(.present) }
        if folded { return .folded(drawn: drawn) }
        return drawn.isEmpty ? .hiddenClean : .drawn(drawn)
    }
}
