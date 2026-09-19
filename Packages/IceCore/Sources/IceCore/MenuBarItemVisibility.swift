/// Decides, from what a capture of the menu bar shows, whether a given item is
/// drawn — and refuses to decide whenever the capture cannot carry the answer.
///
/// Ice needs this to know whether hiding worked. Accessibility cannot tell it:
/// an overflowed item keeps a frame on the bar, and the frame it reports depends
/// on the path the layout took to get there, so the same pixels come with three
/// different answers (docs/macos-27/FINDINGS.md, "Refuted"). Pixels decide.
///
/// The type holds no pixels of its own. An adapter in the app captures the bar,
/// matches each item's cached image against it, and hands the results in as
/// plain values; everything here is a rule about what those results are allowed
/// to mean. The rules are deliberately fail-closed, because each one names a
/// wrong conclusion that was actually drawn during the 2026-09-18 measurements:
/// a mid-capture Space switch made fifteen items read as lost at once, a clock
/// and a chat badge redrew themselves in place, and a translucent bar over a
/// changed window made a present item match badly.
public struct MenuBarItemVisibility: Equatable, Sendable {
    /// The largest template mismatch still counted as a match. Above it, the
    /// reading is evidence of neither presence nor absence.
    public let maxMismatch: Double

    public init(maxMismatch: Double) {
        precondition(maxMismatch.isFinite && maxMismatch >= 0, "maxMismatch must be finite and non-negative")
        self.maxMismatch = maxMismatch
    }

    /// What one capture says about one item.
    public func verdict(for sighting: ItemSighting, captureStable: Bool) -> Visibility {
        guard captureStable else {
            return .unverifiable(.captureUnstable)
        }
        switch sighting.match {
        case .unique(let x, let mismatch):
            // A match is a match whatever the item has done to its own look;
            // only its *absence* depends on the template still being current.
            guard mismatch <= maxMismatch else {
                return .unverifiable(.weakMatch)
            }
            // Pixels cannot say who drew a pattern, so the item's own frame gets
            // a veto — never a vote: it can refuse a match, and it is not
            // consulted when nothing matched.
            return sighting.placement == .consistent ? .drawn(x: x) : .unverifiable(.contradictsAccessibility)
        case .ambiguous:
            return .unverifiable(.ambiguousMatch)
        case .absent:
            return sighting.appearance == .asBaselined ? .notDrawn : .unverifiable(.appearanceChanged)
        }
    }

    /// Whether the named item has been hidden, and whether the system fold went
    /// up with it.
    ///
    /// The fold matters on macOS 27: squeezing an item off the bar *is* the
    /// system's own fold, so an item that vanished with no fold vanished some
    /// other way. Reporting one as the other would hide the difference between
    /// the two mechanisms, which is the whole question.
    public func hiding(of id: String, in reading: StripReading) -> Hiding {
        guard reading.captureStable else {
            return .unverifiable(.captureUnstable)
        }
        guard let sighting = reading.sightings.first(where: { $0.id == id }) else {
            // Nobody looked for it. Saying "hidden" here is the one failure that
            // would let an item disappear unnoticed.
            return .unverifiable(.notObserved)
        }
        switch verdict(for: sighting, captureStable: reading.captureStable) {
        case .drawn:
            return .stillDrawn
        case .unverifiable(let reason):
            return .unverifiable(reason)
        case .notDrawn:
            // "The fold went up with it" cannot be told when it was already up,
            // and templates are not cut from such a baseline in the first place.
            switch reading.foldAtBaseline {
            case .present: return .unverifiable(.foldAlreadyUp)
            case .unreadable: return .unverifiable(.foldUnreadable)
            case .absent: break
            }
            switch reading.fold {
            case .present: return .hidden(folded: true)
            case .absent: return .hidden(folded: false)
            case .unreadable: return .unverifiable(.foldUnreadable)
            }
        }
    }
}

extension MenuBarItemVisibility {
    /// Whether the named item is back on the bar after whatever hid it was
    /// released.
    ///
    /// Releasing a mechanism is not the same as the bar recovering from it, and
    /// nothing here may report a recovery it did not see: every reading that
    /// cannot decide is `unverifiable`, never `restored`.
    public func restoration(of id: String, in reading: StripReading) -> Restoration {
        guard reading.captureStable else {
            return .unverifiable(.captureUnstable)
        }
        guard let sighting = reading.sightings.first(where: { $0.id == id }) else {
            return .unverifiable(.notObserved)
        }
        switch verdict(for: sighting, captureStable: reading.captureStable) {
        case .drawn(let x): return .restored(x: x)
        case .notDrawn: return .notRestored
        case .unverifiable(let reason): return .unverifiable(reason)
        }
    }
}

public enum Restoration: Equatable, Sendable {
    /// Drawn again. `x` is where, which need not be where it started: releasing
    /// one item's hiding can leave the others shifted.
    case restored(x: Double)
    case notRestored
    case unverifiable(Unverifiable)
}

/// One item's template match in one capture, as the adapter measured it.
public struct ItemSighting: Equatable, Sendable {
    public let id: String
    public let appearance: Appearance
    public let match: Match
    /// What the item's own Accessibility frame says about the match. Required:
    /// a default would be a fact nobody observed.
    public let placement: Placement

    public init(id: String, appearance: Appearance, match: Match, placement: Placement) {
        self.id = id
        self.appearance = appearance
        self.match = match
        self.placement = placement
    }
}

/// Whether the item still looks the way it did when its template was taken.
public enum Appearance: Equatable, Sendable {
    case asBaselined
    /// The item redrew itself in place — a clock ticking, a badge appearing.
    /// Its template is stale, so failing to find it proves nothing.
    case changedSinceBaseline
}

/// Where an item's template was found in the captured strip.
public enum Match: Equatable, Sendable {
    /// Found in exactly one place, with this mismatch score.
    case unique(x: Double, mismatch: Double)
    /// Found in more than one place: the template does not identify the item.
    case ambiguous(count: Int)
    /// Not found anywhere, the closest place scoring this badly.
    case absent(bestMismatch: Double)
}

public enum Visibility: Equatable, Sendable {
    case drawn(x: Double)
    case notDrawn
    case unverifiable(Unverifiable)
}

public enum Hiding: Equatable, Sendable {
    /// Gone from the bar. `folded` says whether the system fold went up with it.
    case hidden(folded: Bool)
    case stillDrawn
    case unverifiable(Unverifiable)
}

public enum Unverifiable: Equatable, Sendable {
    /// The bar moved while it was being captured.
    case captureUnstable
    /// The item redrew itself, so its template no longer describes it.
    case appearanceChanged
    /// The pixels matched, but the item's own Accessibility frame is not there.
    case contradictsAccessibility
    /// The fold was already up before the action, so nothing here can say
    /// whether it went up *with* the item.
    case foldAlreadyUp
    /// The template matched in several places.
    case ambiguousMatch
    /// The best match is too poor to mean either presence or absence.
    case weakMatch
    /// Whether the fold is up could not be read.
    case foldUnreadable
    /// The capture carries no reading for this item at all.
    case notObserved
}

/// One capture of the menu bar, reduced to what the rules need.
public struct StripReading: Equatable, Sendable {
    public let sightings: [ItemSighting]
    public let fold: Fold
    /// The fold before the action. Required, with no default: `.absent` would
    /// claim an observation nobody made.
    public let foldAtBaseline: Fold
    /// Whether this capture and the one before it agree about everything the
    /// experiment did not touch. A bar caught mid-animation agrees about nothing.
    public let captureStable: Bool

    public init(sightings: [ItemSighting], fold: Fold, foldAtBaseline: Fold, captureStable: Bool) {
        self.sightings = sightings
        self.fold = fold
        self.foldAtBaseline = foldAtBaseline
        self.captureStable = captureStable
    }
}

/// The system's overflow chevron, as the adapter could read it.
public enum Fold: Equatable, Sendable {
    case present
    case absent
    /// The chevron's own witness (a new `MenuBarAgent` item with ink drawn in
    /// its span) could not be established for this capture.
    case unreadable
}
