// Settle detection: deciding, from a stream of captured signatures, whether the
// menu bar layout has stopped moving.

/// A snapshot of everything one capture measured, reduced to the pieces the
/// settle detector needs to compare between captures. Two signatures "match"
/// (see `matches`) when they describe the same layout within `tolerance`.
public struct Signature: Equatable, Sendable {
    public var markers: [String: MarkerResult]
    public var itemOffsets: [String: Double?]

    public init(markers: [String: MarkerResult], itemOffsets: [String: Double?]) {
        self.markers = markers
        self.itemOffsets = itemOffsets
    }

    /// True when `self` and `other` describe the same layout within `tolerance`:
    /// the same marker keys and item keys, every marker the same case (and, for
    /// `.unique`, both edges within tolerance; for `.ambiguous`, the same count
    /// with every span pairwise within tolerance, in order), and every item
    /// offset either both nil or both present and within tolerance.
    public func matches(_ other: Signature, tolerance: Double) -> Bool {
        guard Set(markers.keys) == Set(other.markers.keys) else { return false }
        guard Set(itemOffsets.keys) == Set(other.itemOffsets.keys) else { return false }

        for (key, value) in markers {
            guard let otherValue = other.markers[key] else { return false }
            guard Self.markersMatch(value, otherValue, tolerance: tolerance) else { return false }
        }

        for (key, value) in itemOffsets {
            guard let otherValue = other.itemOffsets[key] else { return false }
            guard Self.offsetsMatch(value, otherValue, tolerance: tolerance) else { return false }
        }

        return true
    }

    private static func markersMatch(_ a: MarkerResult, _ b: MarkerResult, tolerance: Double) -> Bool {
        switch (a, b) {
        case (.absent, .absent):
            return true
        case let (.unique(spanA), .unique(spanB)):
            return spansMatch(spanA, spanB, tolerance: tolerance)
        case let (.ambiguous(spansA), .ambiguous(spansB)):
            guard spansA.count == spansB.count else { return false }
            return zip(spansA, spansB).allSatisfy { spansMatch($0, $1, tolerance: tolerance) }
        default:
            return false
        }
    }

    private static func spansMatch(_ a: Span, _ b: Span, tolerance: Double) -> Bool {
        abs(a.lo - b.lo) <= tolerance && abs(a.hi - b.hi) <= tolerance
    }

    private static func offsetsMatch(_ a: Double?, _ b: Double?, tolerance: Double) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return abs(lhs - rhs) <= tolerance
        default:
            return false
        }
    }
}

/// Where a run of captures stands relative to settling.
public enum SettleState: Equatable, Sendable {
    /// The current run has not yet spanned `span` with at least two captures.
    case settling
    /// The current run has spanned `span` with at least two matching captures.
    case settled
    /// The current run is not settled and `time` is at least `timeout` seconds
    /// past `start`. This carries no memory of earlier runs: a run that
    /// restarts after an earlier run already reported `.settled` can still
    /// report `.timedOut` once the overall timeout has elapsed.
    case timedOut
}

/// Tracks a "run" of consecutive matching captures and reports whether the
/// layout has settled. A run is anchored to the signature that started it (its
/// *reference*): later captures are always compared against that fixed
/// reference, never against the immediately preceding capture, so a sequence of
/// small steps that each look fine next to their neighbour but drift away from
/// where the run started cannot be mistaken for having settled.
public struct SettleDetector: Sendable {
    private let span: Double
    private let tolerance: Double
    private let timeout: Double
    private let start: Double

    private var reference: Signature?
    private var runStart: Double = 0
    private var captureCount: Int = 0

    public init(span: Double, tolerance: Double, timeout: Double, start: Double) {
        self.span = span
        self.tolerance = tolerance
        self.timeout = timeout
        self.start = start
    }

    /// Feeds one more captured signature at `time`. The very first call always
    /// starts a run. Every later call either extends the current run (the
    /// signature matches its reference) or starts a new run at `time` (it does
    /// not). Returns `.settled` when the current run has at least two captures
    /// spanning at least `span` seconds; otherwise `.timedOut` once `time` is at
    /// least `timeout` seconds past `start`; otherwise `.settling`. `.settled`
    /// takes precedence when both conditions hold on the same call.
    public mutating func add(_ signature: Signature, at time: Double) -> SettleState {
        if let reference, signature.matches(reference, tolerance: tolerance) {
            captureCount += 1
        } else {
            reference = signature
            runStart = time
            captureCount = 1
        }

        if captureCount >= 2 && (time - runStart) >= span {
            return .settled
        }
        if (time - start) >= timeout {
            return .timedOut
        }
        return .settling
    }
}
