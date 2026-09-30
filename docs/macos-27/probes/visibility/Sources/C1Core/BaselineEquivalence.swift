/// Whether the system overflow fold is up, as C1's own readings state it
/// (mirrors the shape of IceCore's `Fold`, restated here because C1Core
/// imports nothing).
public enum FoldState: Equatable, Sendable {
    case present
    case absent
    case unreadable
}

/// Section 5: "Baseline-equivalent (the reset check and the teardown)."
public enum BaselineEquivalence {
    /// Section 5: "within 2 pt of its baseline x" -- owner items only. The
    /// reset check's three helpers are held to their exact baseline x
    /// instead (no stated tolerance for them, unlike the owner items'
    /// explicit "within 2 pt").
    public static let ownerTolerancePt = 2.0

    public struct Reading: Equatable, Sendable {
        public let id: String
        public let x: Double

        public init(id: String, x: Double) {
            self.id = id
            self.x = x
        }
    }

    public struct Input: Equatable, Sendable {
        public let templatedOwnerItems: [Reading]
        public let baselineTemplatedOwnerItems: [Reading]
        public let residualStripChanged: Bool
        public let indicatorFrame: BarFrame?
        public let baselineIndicatorFrame: BarFrame?
        public let fold: FoldState
        /// The reset check's own extra condition: Target, the spacer (at
        /// rest) and Protected at their baseline x. `nil` for a check that
        /// does not include them (section 5 states this trio only "for the
        /// reset check").
        public let helpers: [Reading]?
        public let baselineHelpers: [Reading]?

        public init(
            templatedOwnerItems: [Reading],
            baselineTemplatedOwnerItems: [Reading],
            residualStripChanged: Bool,
            indicatorFrame: BarFrame?,
            baselineIndicatorFrame: BarFrame?,
            fold: FoldState,
            helpers: [Reading]? = nil,
            baselineHelpers: [Reading]? = nil
        ) {
            self.templatedOwnerItems = templatedOwnerItems
            self.baselineTemplatedOwnerItems = baselineTemplatedOwnerItems
            self.residualStripChanged = residualStripChanged
            self.indicatorFrame = indicatorFrame
            self.baselineIndicatorFrame = baselineIndicatorFrame
            self.fold = fold
            self.helpers = helpers
            self.baselineHelpers = baselineHelpers
        }
    }

    public enum Failure: Hashable, Sendable {
        case ownerItemDrifted(String)
        case ownerItemMissing(String)
        case residualStripChanged
        case indicatorMissing
        case indicatorMoved
        /// The fold is not `.absent` -- present or unreadable both fail the
        /// same "fold absent" condition (section 5).
        case foldNotAbsent
        case helperDrifted(String)
        case helperMissing(String)
    }

    /// Every failure found, in the order section 5 lists its conditions.
    /// Empty means baseline-equivalent.
    public static func check(_ input: Input) -> [Failure] {
        var failures = [Failure]()

        let current = Dictionary(uniqueKeysWithValues: input.templatedOwnerItems.map { ($0.id, $0.x) })
        for baseline in input.baselineTemplatedOwnerItems {
            guard let x = current[baseline.id] else {
                failures.append(.ownerItemMissing(baseline.id))
                continue
            }
            if abs(x - baseline.x) > ownerTolerancePt {
                failures.append(.ownerItemDrifted(baseline.id))
            }
        }

        if input.residualStripChanged { failures.append(.residualStripChanged) }

        if let indicatorFrame = input.indicatorFrame {
            if indicatorFrame != input.baselineIndicatorFrame { failures.append(.indicatorMoved) }
        } else {
            failures.append(.indicatorMissing)
        }

        if input.fold != .absent { failures.append(.foldNotAbsent) }

        if let baselineHelpers = input.baselineHelpers {
            let currentHelpers = Dictionary(uniqueKeysWithValues: (input.helpers ?? []).map { ($0.id, $0.x) })
            for baseline in baselineHelpers {
                guard let x = currentHelpers[baseline.id] else {
                    failures.append(.helperMissing(baseline.id))
                    continue
                }
                if x != baseline.x {
                    failures.append(.helperDrifted(baseline.id))
                }
            }
        }

        return failures
    }
}
