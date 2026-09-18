/// Decides whether the menu bar items need to be gathered again, and whether a
/// change of fortune is worth logging.
///
/// Gathering the items is expensive -- on macOS 26 it costs one synchronous
/// round trip to a helper service per menu bar item -- so a pass is skipped when
/// the window identifiers have not changed since the last one. Two rules make
/// that optimization safe, and both were violated by the version this type
/// replaces:
///
/// - A pass that failed must not record what it saw. Recording it claims the
///   observation was cached successfully, and the next pass is then skipped for
///   as long as the menu bar holds still. On macOS 27 the menu bar holds still
///   forever, because the window list is permanently empty.
/// - Validity must be tracked separately from the identifiers themselves. An
///   empty list is a perfectly ordinary value that compares equal to the initial
///   state, so "unchanged" cannot be allowed to mean "already handled".
public struct MenuBarItemCacheState: Equatable, Sendable {
    /// The identifier of a window backing a menu bar item.
    ///
    /// Spelled out rather than imported so this module stays free of the
    /// graphics frameworks; it is layout-compatible with `CGWindowID`.
    public typealias WindowID = UInt32

    /// Whether a failure is new information.
    public enum FailureReport: Equatable, Sendable {
        /// The first failure since the last success, or since the state was
        /// invalidated. Worth reporting.
        case report
        /// A repeat of a failure that has already been reported. Reporting it
        /// again on every pass would bury the log without adding anything.
        case alreadyReported
    }

    /// Whether a success is new information.
    public enum CommitReport: Equatable, Sendable {
        /// The previous pass had failed, so this one is a recovery. Without
        /// this, a persistent failure and a failure that healed itself produce
        /// identical logs.
        case recovered
        /// One ordinary success following another.
        case unremarkable
    }

    /// How the most recent pass ended.
    private enum Outcome: Equatable, Sendable {
        /// No pass has completed since the last invalidation. Distinct from
        /// `failed` so that the very first failure still counts as news.
        case pending
        case succeeded
        case failed
    }

    private var outcome = Outcome.pending
    private var cachedItemWindowIDs = [WindowID]()

    public init() {}

    /// Returns whether a pass should run for the given window identifiers.
    public func shouldCacheItems(for itemWindowIDs: [WindowID]) -> Bool {
        outcome != .succeeded || cachedItemWindowIDs != itemWindowIDs
    }

    /// Records a pass that produced a usable cache.
    @discardableResult
    public mutating func commit(for itemWindowIDs: [WindowID]) -> CommitReport {
        let report: CommitReport = outcome == .failed ? .recovered : .unremarkable
        cachedItemWindowIDs = itemWindowIDs
        outcome = .succeeded
        return report
    }

    /// Records a pass that did not produce a usable cache.
    ///
    /// Deliberately takes no identifiers: whatever a failed pass observed must
    /// not be treated as cached, or the next pass gets skipped.
    @discardableResult
    public mutating func recordFailure() -> FailureReport {
        let report: FailureReport = outcome == .failed ? .alreadyReported : .report
        cachedItemWindowIDs.removeAll()
        outcome = .failed
        return report
    }

    /// Discards the cached identifiers so the next pass runs even if the menu
    /// bar has not changed.
    ///
    /// Used when a pass succeeded but produced something incomplete. That is
    /// not a failure, so it leaves the failure reporting alone: a real failure
    /// afterwards is still news.
    public mutating func invalidate() {
        cachedItemWindowIDs.removeAll()
        outcome = .pending
    }
}
