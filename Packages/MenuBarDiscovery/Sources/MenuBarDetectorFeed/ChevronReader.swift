import Foundation
import IceCore
import MenuBarCapture

/// Whether `MenuBarAgent` lists the system's `«` on the bar (plan
/// 2026-10-03-icebar-build, D1 and section 9.3), by Accessibility alone: no
/// capture, so reading it does not summon the capture indicator. The width
/// rule is the frozen detector's (`FoldWitness.isChevron`).
public struct ChevronReader: Sendable {
    private let reader: any MenuBarAXReading
    private let barHeight: Double
    private let parameters: DetectorParameters

    /// Reads run here, never on the caller's thread or the cooperative pool.
    private static let queue = DispatchQueue(label: "com.icereverse.MenuBarDetectorFeed.ChevronReader")

    public init(reader: any MenuBarAXReading, barHeight: Double, parameters: DetectorParameters = .preRegistered) {
        self.reader = reader
        self.barHeight = barHeight
        self.parameters = parameters
    }

    /// `nil` when the agent could not be read.
    func read() -> Bool? {
        // An empty agent cannot happen on a real bar (it owns the clock), so
        // it is unreadable, as in `FoldSample`.
        guard let frames = reader.read(items: [:])?.agentFrames, !frames.isEmpty else { return nil }
        guard frames.allSatisfy({ $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite }) else { return nil }
        return frames.contains { frame in
            frame.minY >= 0 && frame.minY < barHeight && FoldWitness.isChevron(frame, parameters: parameters)
        }
    }

    /// `read()` on a queue of its own: an Accessibility read may block.
    public func chevronListed() async -> Bool? {
        await withCheckedContinuation { continuation in
            Self.queue.async { continuation.resume(returning: read()) }
        }
    }
}
