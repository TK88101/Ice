import Darwin
import IceCore

/// One read of the extras a set of ids could produce, plus
/// `com.apple.MenuBarAgent`'s own.
public struct MenuBarAXSnapshot: Equatable, Sendable {
    public let itemFrames: [String: ItemFrame]
    public let agentFrames: [AgentFrame]

    public init(itemFrames: [String: ItemFrame], agentFrames: [AgentFrame]) {
        self.itemFrames = itemFrames
        self.agentFrames = agentFrames
    }
}

/// Reads `AXExtrasMenuBar` children's frames, read-only: no attribute here is
/// ever written, no action performed.
public protocol MenuBarAXReading: Sendable {
    /// `items` maps a caller-chosen id to the pid that owns it.
    ///
    /// `nil` means the read failed as a whole -- nothing here can be
    /// trusted, so the caller (`Sampler`) produces no sample at all. A
    /// successful read that found no frame for one of `items` is not a
    /// failure: that id is simply absent from `itemFrames`.
    func read(items: [String: pid_t]) -> MenuBarAXSnapshot?
}
