/// Ice's trace mode (plan 2026-10-07-icebar-preference-hiding, S1): Ice's own
/// sources create its control items exactly as a launch in IceBar mode with
/// uncalibrated dividers does, and log the status-item defaults at five points
/// of that lifecycle, so where the icon's seed is lost (P2) is read from Ice
/// itself rather than from a stand-in whose lifecycle differs (P3).
///
/// Since T2a (S2 design) it also reads where those items and the other status
/// items sit: one discovery pass before the control items exist, two after.
///
/// The mode adds three status items for a few seconds and writes the defaults
/// of whatever identity it runs under, so it is off unless asked for at launch
/// and refuses any identity that is not a disposable lab one.

/// The points of a control item's creation at which the trace reads its
/// defaults, in the order the lifecycle reaches them (`ControlItem`'s
/// `StatusItemStorage.init`, then one main-queue turn later).
public enum LabTracePoint: String, CaseIterable, Sendable {
    case beforeSeed
    case afterSeed
    case afterStatusItem
    case afterAutosaveName
    case afterMainQueueTurn
}

/// The only things a trace launch starts (S1, "the bootstrap, exactly").
/// Everything else a launch starts -- `AppState.performSetup`, the settings'
/// and the menu bar manager's setup, migration, the item manager, the hiding
/// coordinator, HID taps -- is not started.
public enum LabTraceStep: String, Sendable {
    /// `AppState`'s construction starts permission polling; stopped at once,
    /// as the normal setup does.
    case stopPermissionChecks
    /// `useIceBar`, `showIceIcon` and `enableAlwaysHiddenSection`, set on the
    /// settings models only: their persistence subscribers are installed by
    /// their `performSetup`, which is not called.
    case setSettingsInMemory
    /// A discovery pass before any control item exists: how many other
    /// items are on the bar, so the placement oracle can tell whether Ice's
    /// items pushed one off it (plan S2 design, T2a). Read only. Repeated up
    /// to `LabTracePlan.baselineAttempts` times until one is complete: a
    /// process's first pass is often not.
    case readBaseline
    /// `MenuBarSection.performSetup(with:)` on the three sections, which
    /// creates the control items.
    case setUpSections
}

/// What the trace reads off the bar once the control items have settled, in
/// order (plan S2 design, T2a). Both read only.
public enum LabTraceReading: String, Sendable {
    /// Ice's own extras by Accessibility, and each control item's window.
    case ownExtras
    /// Ice's own discovery pass (`MenuBarItem.discoverItems`), run
    /// `LabTracePlan.discoveryPasses` times: every placement verdict comes
    /// from one pass's set, and passes that disagree make the run
    /// indeterminate. The item manager itself is still not started.
    case discover
}

/// One trace run's settings. The always-hidden section runs both ways: off is
/// T7's state, where P2 was seen (setup removes that control item again); on
/// keeps three items on the bar.
public struct LabTracePlan: Equatable, Sendable {
    public let alwaysHiddenSection: Bool

    public init(alwaysHiddenSection: Bool) {
        self.alwaysHiddenSection = alwaysHiddenSection
    }

    /// IceBar mode, so the hidden divider sits at standard length by the real
    /// path (`calibratedLength ?? standard`), not by an override.
    public var useIceBar: Bool { true }
    public var showIceIcon: Bool { true }

    public static let steps: [LabTraceStep] = [.stopPermissionChecks, .setSettingsInMemory, .readBaseline, .setUpSections]

    public static let readings: [LabTraceReading] = [.ownExtras, .discover]

    /// How long after the control items are created the bar is read: past
    /// the main-queue turns that add, remove and size them.
    public static let settleSeconds = 3.0
    public static let discoveryPasses = 2
    public static let baselineAttempts = 2
    public static let discoveryGapSeconds = 1.0

    /// The trace quits by itself after this long, whatever it has read.
    public static let capSeconds = 20.0
}

public enum LabTraceRefusal: Equatable, Sendable {
    /// The trace writes this identity's defaults and MenuBarAgent's record of
    /// it, so it runs only under `LabTraceRule.labBundleIDPrefix`.
    case notLabIdentity(String?)
    /// A launch argument that is neither `YES` nor `NO`.
    case badArgument(name: String, value: String)
}

public enum LabTraceLaunch: Equatable, Sendable {
    case normal
    case refused(LabTraceRefusal)
    case trace(LabTracePlan)
}

public enum LabTraceRule {
    /// `-IceLabTrace YES` turns the mode on.
    public static let traceArgument = "IceLabTrace"
    /// `-IceLabTraceAlwaysHidden YES` runs it with the always-hidden section.
    public static let alwaysHiddenArgument = "IceLabTraceAlwaysHidden"
    /// The trace's own disposable identities (`run-trace.sh` makes one per
    /// run); an allowlist, so a fork's or a renamed release identity can never
    /// be traced by mistake, nor the other experiments' identities
    /// (`com.icespike4.target`, `.protected`, T7's `.ice`), whose defaults and
    /// MenuBarAgent records those experiments rely on.
    public static let labBundleIDPrefix = "com.icespike4.trace."

    /// - Parameters:
    ///   - trace: the value of `-IceLabTrace` in the launch arguments only
    ///     (never a stored default), `nil` when absent.
    ///   - alwaysHidden: the value of `-IceLabTraceAlwaysHidden`, likewise.
    ///   - bundleID: the running bundle's identifier.
    public static func launch(trace: String?, alwaysHidden: String?, bundleID: String?) -> LabTraceLaunch {
        guard let trace else { return .normal }
        guard let isOn = LabLaunchArguments.flag(trace) else {
            return .refused(.badArgument(name: traceArgument, value: trace))
        }
        guard isOn else { return .normal }
        guard let bundleID, LabLaunchArguments.isLabIdentity(bundleID, prefix: labBundleIDPrefix) else {
            return .refused(.notLabIdentity(bundleID))
        }
        let alwaysHiddenValue = alwaysHidden ?? "NO"
        guard let alwaysHiddenSection = LabLaunchArguments.flag(alwaysHiddenValue) else {
            return .refused(.badArgument(name: alwaysHiddenArgument, value: alwaysHiddenValue))
        }
        return .trace(LabTracePlan(alwaysHiddenSection: alwaysHiddenSection))
    }
}
