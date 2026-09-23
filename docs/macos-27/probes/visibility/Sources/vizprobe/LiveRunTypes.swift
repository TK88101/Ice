// Shared types for the live protocol of plan section 6 (T14). Kept apart
// from `LiveRun` itself so the bundle ids -- the one thing that must never
// silently drift from build.sh -- have a single, obvious home.
import Foundation

/// Where build.sh put the three helper bundles.
struct HelperApps {
    let target: URL
    let reference: URL
    let twin: URL
}

enum HelperRole {
    /// Reused from probes/safewidth's own swhelper on purpose: T13's DoD is
    /// that no new bundle id appears in the menu bar settings for the target
    /// or the reference (Opus P2-13).
    static let target = "com.icespike4.target"
    static let reference = "com.icespike4.protected"
    /// New on purpose -- it exists only for the ambiguity control of plan
    /// step 6.1(6c): launched, observed once, quit within the same run.
    /// The twin runs under the protected helper's id on purpose: a third id
    /// would register a new, permanent entry in the menu bar settings.
    static let twin = reference
    static let allBundleIDs = [target, reference]
}

/// A step's own verdict: continue, or the reason the whole run stops here.
/// The plan's stop rule (section 6, last paragraph) is "no retry within the
/// run" -- so every step returns this instead of throwing, and the caller
/// never loops back into a step that already failed.
enum StepResult {
    case ok
    case abort(String)
}
