/// Plain values an AX adapter hands in after walking one process's
/// `AXExtrasMenuBar` (plan section 4.1.1). Nothing here talks to
/// Accessibility itself -- `LiveExtrasReader` in `MenuBarDiscovery` does the
/// walk and produces these; everything downstream in IceCore is a pure
/// function of them, which is what makes it testable without a menu bar, a
/// display, or a running app.
///
/// A read never collapses "nothing here" and "the read failed" into the same
/// shape: every attribute carries its own `AXError` name alongside whatever
/// value it managed to read, so `ReadClassifier` can tell a process that
/// genuinely has no extras apart from one whose read timed out or was
/// refused (docs/plans/2026-09-23-ax-discovery.md section 4.1.2).

/// One rectangle as Accessibility reported it. Named apart from any graphics
/// framework's rect type because IceCore may not import one (this package is
/// standard library only) -- `minY` grows downward, matching `AXFrame` and
/// `CGRect`, so a caller converting from a live read never has to flip an
/// axis.
public struct BarRect: Equatable, Hashable, Sendable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    public var maxX: Double { minX + width }
    public var midX: Double { minX + width / 2 }
}

/// The bar's own extent, in the coordinate space of one display. Kept
/// separate from `BarRect` (an item's frame) so a caller can never pass one
/// where the other is meant: `PositionRule.position(of:in:obstacles:)` takes
/// exactly one of each.
public struct BarBounds: Equatable, Sendable {
    public let minX: Double
    public let maxX: Double
    public let minY: Double
    public let barHeight: Double

    public init(minX: Double, maxX: Double, minY: Double, barHeight: Double) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.barHeight = barHeight
    }
}

/// One Accessibility attribute read: what it produced, and what it cost to
/// find out. `error` is the `AXError` case name, `"success"` when the call
/// simply worked -- a `String` rather than a typed error so this file need
/// not import ApplicationServices to spell the real enum (IceCore imports
/// nothing; `MenuBarDiscovery`'s `AXErrorNames` is what actually names the
/// codes). `value` and `error` are independent: a failed read can still be
/// asked what it produced (usually `nil`), and a successful one is not
/// assumed to have produced anything in particular.
public struct AttributeRead<Value: Equatable & Sendable>: Equatable, Sendable {
    public let value: Value?
    public let error: String

    public init(value: Value?, error: String) {
        self.value = value
        self.error = error
    }
}

/// One child of a process's `AXExtrasMenuBar` -- an "extra" (plan section 2).
/// `childIndex` is the position it was read at, kept because it is the only
/// thing that still distinguishes two items whose declared identifiers are
/// equal (D3; `ItemKeying.assign`).
public struct ExtrasRecord: Equatable, Sendable {
    public let childIndex: Int
    public let role: AttributeRead<String>
    public let identifier: AttributeRead<String>
    public let title: AttributeRead<String>
    public let description: AttributeRead<String>
    public let help: AttributeRead<String>
    public let frame: AttributeRead<BarRect>

    public init(
        childIndex: Int,
        role: AttributeRead<String>,
        identifier: AttributeRead<String>,
        title: AttributeRead<String>,
        description: AttributeRead<String>,
        help: AttributeRead<String>,
        frame: AttributeRead<BarRect>
    ) {
        self.childIndex = childIndex
        self.role = role
        self.identifier = identifier
        self.title = title
        self.description = description
        self.help = help
        self.frame = frame
    }
}

/// What the adapter could learn about the process being read, independent of
/// its menu bar extras. `pid` is `Int32` rather than `pid_t` so this file
/// need not import Darwin to spell that type (IceCore imports nothing);
/// `Int32` is layout-compatible with `pid_t` on Darwin. `isSelf` marks Ice's
/// own process, which `ItemKey.tagTitle` and `TagCollision.split` both treat
/// specially (D9; plan section 4.1.3).
public struct ProcessInfoRecord: Equatable, Hashable, Sendable {
    public let pid: Int32
    public let bundleID: String?
    public let localizedName: String?
    public let executableName: String?
    public let launchTime: Double?
    public let isSelf: Bool

    public init(pid: Int32, bundleID: String?, localizedName: String?, executableName: String?, launchTime: Double?, isSelf: Bool) {
        self.pid = pid
        self.bundleID = bundleID
        self.localizedName = localizedName
        self.executableName = executableName
        self.launchTime = launchTime
        self.isSelf = isSelf
    }
}

/// Everything one process's read produced, unclassified. `extrasError` and
/// `extrasElapsed` describe the `AXExtrasMenuBar` read itself;
/// `childrenError` and `childrenElapsed` describe the children read, `nil`
/// when the extras-bar read never got far enough to attempt it. `records`
/// holds whatever children were read -- `ReadClassifier.outcome` is the pure
/// function that turns this into a `ReadOutcome` a caller can act on.
///
/// `walkInterrupted` and `childCount` say what the walk actually *did*, which
/// used to be only implied: before `AttributeWalkPolicy` tolerated any
/// attribute error, a stop always left `notAttempted` on one of
/// role/identifier/frame, and the classifier failed the record on that alone.
/// Now that one identifier error is tolerated, that implication is gone, so the
/// two facts are carried instead (2026-09-25 plan, axis C) -- and they are two,
/// not one, because "the policy stopped" and "how many children there were" are
/// different questions with different failure modes.
public struct RawRead: Equatable, Sendable {
    public let process: ProcessInfoRecord
    public let extrasError: String
    public let extrasElapsed: Double
    public let childrenError: String?
    public let childrenElapsed: Double?
    public let records: [ExtrasRecord]
    /// `true` the moment the walk policy said stop -- asked *before* whether
    /// another attribute or child remained, so it is a policy-event flag and
    /// not a "work was skipped" flag. A stop on the very last attribute of the
    /// very last child sets it too.
    public let walkInterrupted: Bool
    /// The size of the children snapshot the walk was handed, beside the
    /// `records` it actually produced. `0` whenever the children read produced
    /// no snapshot at all, which is unambiguous because `childrenError` already
    /// fails such a read before anything reads `childCount`.
    public let childCount: Int

    /// No defaults, deliberately: the compiler is what guarantees every
    /// construction site states what its walk did rather than inheriting a
    /// plausible-looking `false`.
    public init(
        process: ProcessInfoRecord,
        extrasError: String,
        extrasElapsed: Double,
        childrenError: String?,
        childrenElapsed: Double?,
        records: [ExtrasRecord],
        walkInterrupted: Bool,
        childCount: Int
    ) {
        self.process = process
        self.extrasError = extrasError
        self.extrasElapsed = extrasElapsed
        self.childrenError = childrenError
        self.childrenElapsed = childrenElapsed
        self.records = records
        self.walkInterrupted = walkInterrupted
        self.childCount = childCount
    }
}
