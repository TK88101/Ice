/// D18: a pure reducer over one combined, de-duplicated stream of divider
/// and mode snapshots, deciding which verification jobs a transition
/// schedules. Nothing here runs a check or touches a queue -- that is
/// `HidingVerification`'s job (`MenuBarDetectorFeed`, outside IceCore); this
/// file only decides *that* a job is due and *what section set* it names.

/// One snapshot of everything `VerificationTrigger.reduce` needs to know,
/// timestamped implicitly by call order (D18: "the run-loop coalescing is
/// done by the reducer over timestamped snapshots").
public struct VerificationInputs: Equatable, Sendable {
    public let hiddenShown: Bool
    public let alwaysHiddenShown: Bool
    public let alwaysHiddenEnabled: Bool
    public let iceBarMode: Bool
    public let barHiddenBySystem: Bool

    public init(hiddenShown: Bool, alwaysHiddenShown: Bool, alwaysHiddenEnabled: Bool, iceBarMode: Bool, barHiddenBySystem: Bool) {
        self.hiddenShown = hiddenShown
        self.alwaysHiddenShown = alwaysHiddenShown
        self.alwaysHiddenEnabled = alwaysHiddenEnabled
        self.iceBarMode = iceBarMode
        self.barHiddenBySystem = barHiddenBySystem
    }
}

/// One unit of verification work `reduce` schedules.
public enum VerificationJob: Equatable, Sendable {
    /// A section newly shown: capture a fresh baseline for it (and every
    /// other currently-shown section, so one consolidated capture covers
    /// all of them).
    case prepare(Set<ItemSection>)
    /// A section newly hidden: check whether its items stopped being drawn.
    case verify(Set<ItemSection>)
    /// A mode that makes checking meaningless while the shown set is
    /// changing (IceBar re-assignment, the bar hidden by the system).
    case skip(Set<ItemSection>, CheckSkipReason)
}

public enum VerificationTrigger {
    /// Which sections currently count as "shown" -- always-hidden only
    /// counts while it is enabled (D18).
    public static func shownSections(_ i: VerificationInputs) -> Set<ItemSection> {
        var shown = Set<ItemSection>()
        if i.hiddenShown { shown.insert(.hidden) }
        if i.alwaysHiddenEnabled && i.alwaysHiddenShown { shown.insert(.alwaysHidden) }
        return shown
    }

    public static func reduce(previous: VerificationInputs?, current: VerificationInputs) -> [VerificationJob] {
        if let previous, previous == current { return [] }

        let currentShown = shownSections(current)

        guard let previous else {
            return currentShown.isEmpty ? [] : [.prepare(currentShown)]
        }

        let previousShown = shownSections(previous)

        if current.iceBarMode || current.barHiddenBySystem {
            let changed = previousShown.symmetricDifference(currentShown)
            guard !changed.isEmpty else { return [] }
            let reason: CheckSkipReason = current.iceBarMode ? .iceBarMode : .barHiddenBySystem
            return [.skip(changed, reason)]
        }

        let newlyHidden = previousShown.subtracting(currentShown)
        let newlyShown = currentShown.subtracting(previousShown)

        var jobs = [VerificationJob]()
        if !newlyHidden.isEmpty { jobs.append(.verify(newlyHidden)) }
        if !newlyShown.isEmpty { jobs.append(.prepare(currentShown)) }
        return jobs
    }
}
