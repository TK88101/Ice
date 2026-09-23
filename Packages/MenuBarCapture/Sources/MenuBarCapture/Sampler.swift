import Foundation
import IceCore

/// One bracketed observation: capture, AX read, capture.
///
/// A partial bracket is worth nothing to the decision layer -- IceCore's
/// samples are trusted completely or not admitted at all (plan section 4;
/// deviation 4 of the ledger).
public struct Sampler: Sendable {
    private let capturer: any StripCapturing
    private let axReader: any MenuBarAXReading
    private let now: @Sendable () -> Double

    public init(
        capturer: any StripCapturing,
        axReader: any MenuBarAXReading,
        now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.capturer = capturer
        self.axReader = axReader
        self.now = now
    }

    /// `items` maps a caller-chosen id to the pid that owns it (the targets
    /// and references of one observation).
    ///
    /// `nil` if the capture or the read failed at any step of the bracket.
    public func sample(items: [String: pid_t]) -> ObservationSample? {
        guard let before = capturer.capture() else { return nil }
        guard let snapshot = axReader.read(items: items) else { return nil }
        guard let after = capturer.capture() else { return nil }
        return ObservationSample(
            time: now(),
            before: before,
            after: after,
            agentFrames: snapshot.agentFrames,
            itemFrames: snapshot.itemFrames
        )
    }
}
