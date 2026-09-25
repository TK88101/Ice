import Darwin

/// P0-6: "relaunch only after a discovery-confirmed reap; a teardown reap
/// failure is a safety stop needing attention." One discovery attempt's
/// worth of decision; the stage's own bounded retry loop (real
/// discovery, real timing) feeds it.
public enum C1ReapCheck {
    /// `listedPIDs`: every pid a fresh discovery pass listed, or `nil`
    /// when the pass itself failed (inconclusive, never confirmed --
    /// section 2's "confirms none of their items is listed" needs a read
    /// that actually succeeded).
    public static func confirmed(listedPIDs: Set<pid_t>?, helperPIDs: Set<pid_t>) -> Bool {
        guard let listedPIDs else { return false }
        return listedPIDs.isDisjoint(with: helperPIDs)
    }
}
