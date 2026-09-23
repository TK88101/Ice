/// The identity Ice compares an item against across passes, replacing the
/// live `windowID` handle that macOS 27 no longer hands out (plan section 0,
/// "What `windowID` does in Ice today"; D1, D3). A key depends only on the
/// process that owns the item -- never on any other process running at the
/// same time -- so a process's own key cannot move when a sibling of the same
/// bundle quits, a third one launches, or that sibling's own read fails.

/// Trims leading and trailing whitespace from an AX-read string.
///
/// A free function rather than `String.trimmingCharacters(in:)` because
/// IceCore imports nothing, including Foundation (plan section 4, "standard
/// library only"); `Character.isWhitespace` is the stdlib's own answer to the
/// same question.
public enum IdentifierText {
    public static func trimmed(_ s: String) -> String {
        var chars = Substring(s)
        while let first = chars.first, first.isWhitespace {
            chars.removeFirst()
        }
        while let last = chars.last, last.isWhitespace {
            chars.removeLast()
        }
        return String(chars)
    }
}

/// Resolves the namespace half of a key from whatever the adapter could learn
/// about the owning process (plan section 2, "key").
public enum ItemNamespace {
    /// Bundle id, then localized name, then executable name, then
    /// `"pid:<n>"` -- the first candidate that is neither `nil` nor empty.
    /// Nothing here is trimmed: these are process-identity strings, not
    /// user-facing AX attributes, so `ItemKeying`'s whitespace handling does
    /// not apply to them.
    public static func resolve(_ p: ProcessInfoRecord) -> String {
        for candidate in [p.bundleID, p.localizedName, p.executableName] {
            if let candidate, !candidate.isEmpty {
                return candidate
            }
        }
        return "pid:\(p.pid)"
    }
}

/// How far a key can be trusted to still mean the same item next pass.
public enum IdentityBasis: Equatable, Sendable {
    /// A non-empty `AXIdentifier`, unique within its process.
    case declared
    /// An empty `AXIdentifier`, unique within its process (nothing else
    /// shares "").
    case unnamed
    /// Shared its identifier with another item in the same process; carries
    /// a child index instead. Never names a detector target (D14, D15's
    /// contract lives with the caller, but the basis is how a caller can
    /// tell).
    case positional
}

/// Ice's stable identity for one status item (plan section 2, "key" and
/// "tag"). Always pid-qualified (D3): unlike a bare identifier, `encoded` and
/// `tagTitle` cannot be confused between two different items even when one
/// item's identifier happens to look like another's full tag.
public struct ItemKey: Hashable, Sendable {
    public let namespace: String
    public let identifier: String
    public let pid: Int32
    public let childIndex: Int?

    public init(namespace: String, identifier: String, pid: Int32, childIndex: Int?) {
        self.namespace = namespace
        self.identifier = identifier
        self.pid = pid
        self.childIndex = childIndex
    }

    /// `<namespace length>:<namespace><identifier length>:<identifier>/p<pid>[c<childIndex>]`.
    /// Length-prefixing `namespace` and `identifier` is what makes decoding
    /// exact: without it, an identifier containing `"/p12"` could be misread
    /// as the boundary between identifier and pid. `length` is the string's
    /// character count (grapheme clusters), matching `String.count` on the
    /// decoding side.
    public var encoded: String {
        var result = "\(namespace.count):\(namespace)\(identifier.count):\(identifier)/p\(pid)"
        if let childIndex {
            result += "c\(childIndex)"
        }
        return result
    }

    /// The exact inverse of `encoded`. `nil` on anything malformed --
    /// truncated length prefixes, a non-numeric pid or child index, or
    /// trailing characters after a well-formed key -- rather than guessing at
    /// a partial parse.
    public static func decode(_ s: String) -> ItemKey? {
        var remainder = Substring(s)

        guard let namespace = readLengthPrefixed(&remainder) else { return nil }
        guard let identifier = readLengthPrefixed(&remainder) else { return nil }

        guard remainder.hasPrefix("/p") else { return nil }
        remainder.removeFirst(2)

        guard let pidValue = readDigits(&remainder), let pid = Int32(pidValue) else { return nil }

        var childIndex: Int?
        if remainder.hasPrefix("c") {
            remainder.removeFirst()
            guard let indexValue = readDigits(&remainder), let index = Int(indexValue) else { return nil }
            childIndex = index
        }
        guard remainder.isEmpty else { return nil }

        return ItemKey(namespace: namespace, identifier: identifier, pid: pid, childIndex: childIndex)
    }

    /// The title half of Ice's existing `MenuBarItemTag` (plan section 2,
    /// "tag"). For the reader's own process the identifier alone, equal to
    /// today's control-item tags (D9) -- Ice's own items are recognised by
    /// identifier and never need a pid or child index to disambiguate them
    /// from themselves.
    public func tagTitle(isSelf: Bool) -> String {
        guard !isSelf else { return identifier }
        var title = "\(identifier)/p\(pid)"
        if let childIndex {
            title += "c\(childIndex)"
        }
        return title
    }

    /// The whole tag: this key's namespace and `tagTitle(isSelf:)`.
    public func tagKey(isSelf: Bool) -> TagKey {
        TagKey(namespace: namespace, title: tagTitle(isSelf: isSelf))
    }

    /// Reads a `"<count>:"` prefix followed by exactly `count` characters,
    /// consuming both from `remainder`.
    private static func readLengthPrefixed(_ remainder: inout Substring) -> String? {
        guard let lengthText = readDigits(&remainder), let length = Int(lengthText) else { return nil }
        guard remainder.first == ":" else { return nil }
        remainder.removeFirst()
        guard remainder.count >= length else { return nil }
        let value = String(remainder.prefix(length))
        remainder.removeFirst(length)
        return value
    }

    /// Consumes a run of ASCII digits from the front of `remainder`, or
    /// returns `nil` (leaving `remainder` untouched) when there is none.
    private static func readDigits(_ remainder: inout Substring) -> String? {
        var digits = ""
        var scanning = remainder
        while let c = scanning.first, c.isNumber {
            digits.append(c)
            scanning.removeFirst()
        }
        guard !digits.isEmpty else { return nil }
        remainder = scanning
        return digits
    }
}

/// One extra, keyed within its own process.
public struct KeyedRecord: Equatable, Sendable {
    public let record: ExtrasRecord
    public let key: ItemKey
    public let basis: IdentityBasis

    public init(record: ExtrasRecord, key: ItemKey, basis: IdentityBasis) {
        self.record = record
        self.key = key
        self.basis = basis
    }
}

/// Assigns keys to one process's extras -- and only that process's: nothing
/// here ever looks past `process` and `records` (plan section 4.1.3), which
/// is what guarantees a survivor's key cannot move when a sibling process
/// appears, quits, or fails to read.
public enum ItemKeying {
    /// Trims each record's `AXIdentifier` (or treats a missing value as
    /// `""`); identifiers unique within the process become `.declared`
    /// (non-empty) or `.unnamed` (empty), each with no child index. Every
    /// identifier shared by more than one record in this process becomes
    /// `.positional`, keyed by that record's own `childIndex` instead.
    public static func assign(process: ProcessInfoRecord, records: [ExtrasRecord]) -> [KeyedRecord] {
        let namespace = ItemNamespace.resolve(process)
        let identifiers = records.map { IdentifierText.trimmed($0.identifier.value ?? "") }

        var counts = [String: Int]()
        for identifier in identifiers { counts[identifier, default: 0] += 1 }

        return zip(records, identifiers).map { record, identifier in
            let basis: IdentityBasis
            let childIndex: Int?
            if counts[identifier] == 1 {
                basis = identifier.isEmpty ? .unnamed : .declared
                childIndex = nil
            } else {
                basis = .positional
                childIndex = record.childIndex
            }
            let key = ItemKey(namespace: namespace, identifier: identifier, pid: process.pid, childIndex: childIndex)
            return KeyedRecord(record: record, key: key, basis: basis)
        }
    }
}

/// Where two different items would end up naming the same tag despite being
/// keyed correctly within their own processes -- for example after
/// carry-over (plan section 4.1.3, "residual collision"). Grouping by
/// `(namespace, tagTitle)` rather than by `ItemKey` itself, because a key
/// already includes the pid and only a title collision is user-visible.
public enum TagCollision {
    /// Every item whose `(namespace, tagTitle)` is shared with another item
    /// in `items` is dropped into `collided`, both of them -- neither survives
    /// picking one arbitrarily. Everything else is `kept`, in its original
    /// order.
    public static func split(_ items: [KeyedRecord], isSelf: (Int32) -> Bool) -> (kept: [KeyedRecord], collided: [KeyedRecord]) {
        split(items, by: { $0.key.tagKey(isSelf: isSelf($0.key.pid)) })
    }

    /// The same rule over any item that can name its tag -- `ItemCatalog`
    /// applies it to its `DiscoveredItem`s, which know whether they are the
    /// reader's own, both after keying and after carry-over.
    public static func split<Item>(_ items: [Item], by tag: (Item) -> TagKey) -> (kept: [Item], collided: [Item]) {
        let identities = items.map(tag)

        var counts = [TagKey: Int]()
        for identity in identities { counts[identity, default: 0] += 1 }

        var kept = [Item]()
        var collided = [Item]()
        for (item, identity) in zip(items, identities) {
            if counts[identity] == 1 {
                kept.append(item)
            } else {
                collided.append(item)
            }
        }
        return (kept, collided)
    }
}
