import IceCore
import MenuBarDetectorFeed
import MenuBarDiscovery

/// Item 8: "same bound for the keyed discovery reads used by the
/// untemplated watch and preflight." Races the wrapped discovery pass
/// against a timer; whichever finishes first wins. A caller that already
/// treats a `nil` result as a failure (every call site in this probe
/// does) cannot tell a genuine failure from a timeout, and does not need
/// to -- both mean "this read cannot be trusted."
public final class TimedDiscoverer: Discovering, @unchecked Sendable {
    /// Same bound as `TimedAXReader.boundSeconds`, for the same reason.
    public static let boundSeconds = 1.0

    private let wrapped: any Discovering
    private let bound: Double

    public init(wrapping discoverer: any Discovering, bound: Double = TimedDiscoverer.boundSeconds) {
        self.wrapped = discoverer
        self.bound = bound
    }

    public func discover(previous: DiscoveredItemSet?) async -> DiscoveryResult? {
        await withTaskGroup(of: DiscoveryResult?.self) { group in
            group.addTask { await self.wrapped.discover(previous: previous) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(self.bound * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            return await group.next() ?? nil
        }
    }
}
