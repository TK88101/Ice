import Foundation

/// T-prefs and the restore check (plan section 5): preferences dictionaries
/// as `PropertyListSerialization` gives them.
public enum PrefsCompare {
    /// Keys AppKit and SwiftUI write while the app runs (status item
    /// positions and visibility, window frames, split views). `SU*` is not
    /// here: Sparkle is meant to write nothing in this run.
    public static let runtimeAllowlist = ["NSStatusItem ", "NSWindow Frame ", "NSSplitView Subview Frames "]

    public static func expected(backup: [String: Any], setting values: [String: Bool]) -> [String: Any] {
        backup.merging(values.mapValues { $0 as Any }) { _, new in new }
    }

    /// Keys added, removed or changed, outside the allowed prefixes, sorted.
    public static func differingKeys(expected: [String: Any], actual: [String: Any], allowedPrefixes: [String]) -> [String] {
        Set(expected.keys).union(actual.keys).filter { key in
            !allowedPrefixes.contains { key.hasPrefix($0) } && !isEqual(expected[key], actual[key])
        }.sorted()
    }

    /// Plist values compared by value. `Data` that holds JSON is compared as
    /// parsed JSON, because Ice re-encodes its JSON settings at setup and the
    /// key order may change.
    public static func isEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case let (left as Data, right as Data):
            if left == right {
                return true
            }
            guard let parsedLeft = json(left), let parsedRight = json(right) else {
                return false
            }
            return (parsedLeft as AnyObject).isEqual(parsedRight)
        case let (left as [String: Any], right as [String: Any]):
            return left.count == right.count && left.allSatisfy { isEqual($0.value, right[$0.key]) }
        case let (left as [Any], right as [Any]):
            return left.count == right.count && zip(left, right).allSatisfy { isEqual($0, $1) }
        case let (left?, right?):
            return (left as AnyObject).isEqual(right)
        }
    }

    private static func json(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}
