import Testing
@testable import IceCore

/// A key must survive round-tripping through its encoded string (the form
/// Ice's existing `MenuBarItemTag` persists), must never depend on any
/// process but the one it names, and must tell apart an identifier that
/// merely *looks* like another item's full tag from that item itself.
@Suite("Identifier trimming and namespace resolution")
struct IdentifierAndNamespaceTests {
    @Test("IdentifierText trims leading and trailing whitespace characters only")
    func identifierTextTrims() {
        #expect(IdentifierText.trimmed("  hello  ") == "hello")
        #expect(IdentifierText.trimmed("\t\nhello\n\t") == "hello")
        #expect(IdentifierText.trimmed("hello") == "hello")
        #expect(IdentifierText.trimmed("   ") == "")
        #expect(IdentifierText.trimmed("") == "")
        #expect(IdentifierText.trimmed("  inner space  ") == "inner space")
    }

    @Test("namespace prefers bundle id, then localized name, then executable name, then the pid")
    func namespaceFallbackChain() {
        let full = ProcessInfoRecord(pid: 1, bundleID: "com.example.a", localizedName: "A", executableName: "a", launchTime: nil, isSelf: false)
        #expect(ItemNamespace.resolve(full) == "com.example.a")

        let noBundle = ProcessInfoRecord(pid: 2, bundleID: nil, localizedName: "B App", executableName: "b", launchTime: nil, isSelf: false)
        #expect(ItemNamespace.resolve(noBundle) == "B App")

        let onlyExecutable = ProcessInfoRecord(pid: 3, bundleID: nil, localizedName: nil, executableName: "c", launchTime: nil, isSelf: false)
        #expect(ItemNamespace.resolve(onlyExecutable) == "c")

        let none = ProcessInfoRecord(pid: 4, bundleID: nil, localizedName: nil, executableName: nil, launchTime: nil, isSelf: false)
        #expect(ItemNamespace.resolve(none) == "pid:4")
    }

    @Test("empty strings are skipped exactly like nils in the namespace fallback")
    func namespaceFallbackSkipsEmptyStrings() {
        let emptyBundle = ProcessInfoRecord(pid: 5, bundleID: "", localizedName: "D App", executableName: nil, launchTime: nil, isSelf: false)
        #expect(ItemNamespace.resolve(emptyBundle) == "D App")

        let emptyBundleAndName = ProcessInfoRecord(pid: 6, bundleID: "", localizedName: "", executableName: "d", launchTime: nil, isSelf: false)
        #expect(ItemNamespace.resolve(emptyBundleAndName) == "d")

        let allEmpty = ProcessInfoRecord(pid: 7, bundleID: "", localizedName: "", executableName: "", launchTime: nil, isSelf: false)
        #expect(ItemNamespace.resolve(allEmpty) == "pid:7")
    }
}

@Suite("ItemKey encoding, decoding, and tag titles")
struct ItemKeyTests {
    @Test("encoding and decoding round-trips an ordinary declared key")
    func encodeDecodeRoundTrips() {
        let key = ItemKey(namespace: "com.example.a", identifier: "gear", pid: 42, childIndex: nil)
        #expect(ItemKey.decode(key.encoded) == key)
    }

    @Test("encoding and decoding round-trips a positional key with a child index")
    func encodeDecodeRoundTripsWithChildIndex() {
        let key = ItemKey(namespace: "com.example.a", identifier: "", pid: 42, childIndex: 3)
        #expect(ItemKey.decode(key.encoded) == key)
    }

    @Test("identifiers containing slashes, p, digits, and colons round-trip exactly")
    func encodeDecodeRoundTripsAwkwardIdentifiers() {
        let identifiers = ["a/p1", "p123", "12:34", "::", "/", "p", "a/pb/pc", "x/p12", "c3"]
        for identifier in identifiers {
            let declared = ItemKey(namespace: "com.example.a", identifier: identifier, pid: 77, childIndex: nil)
            #expect(ItemKey.decode(declared.encoded) == declared)

            let positional = ItemKey(namespace: "com.example.b", identifier: identifier, pid: 88, childIndex: 2)
            #expect(ItemKey.decode(positional.encoded) == positional)
        }
    }

    @Test("namespaces with awkward characters round-trip too")
    func encodeDecodeRoundTripsAwkwardNamespaces() {
        let namespaces = ["pid:12", "a/p1", "5:x", ""]
        for namespace in namespaces {
            let key = ItemKey(namespace: namespace, identifier: "gear", pid: 9, childIndex: nil)
            #expect(ItemKey.decode(key.encoded) == key)
        }
    }

    @Test("decode rejects malformed input rather than crashing")
    func decodeRejectsMalformedInput() {
        #expect(ItemKey.decode("") == nil)
        #expect(ItemKey.decode("not a key") == nil)
        #expect(ItemKey.decode("999:short/p1") == nil) // declared length longer than what remains
        #expect(ItemKey.decode("3:abc3:xyz/pNaN") == nil) // pid is not digits
        #expect(ItemKey.decode("3:abc3:xyz/p12cNaN") == nil) // child index is not digits
        #expect(ItemKey.decode("3:abc3:xyz/p12trailing") == nil) // garbage after the pid
        #expect(ItemKey.decode("3:abc1:x/p1") != nil) // sanity: the well-formed sibling of the cases above decodes
    }

    @Test("an identifier that looks like another item's full tag does not become it")
    func identifierLookingLikeATagDoesNotCollide() {
        // "x/p12" is exactly what `tagTitle` would produce for identifier "x"
        // at pid 12 -- the length-prefixed encoding must still tell the two
        // apart, both in their tag titles and in their encoded keys.
        let looksLikeATag = ItemKey(namespace: "com.example.a", identifier: "x/p12", pid: 34, childIndex: nil)
        let real = ItemKey(namespace: "com.example.a", identifier: "x", pid: 12, childIndex: nil)

        #expect(looksLikeATag.tagTitle(isSelf: false) != real.tagTitle(isSelf: false))
        #expect(looksLikeATag.encoded != real.encoded)
        #expect(ItemKey.decode(looksLikeATag.encoded) == looksLikeATag)
        #expect(ItemKey.decode(real.encoded) == real)
    }

    @Test("the reading process's own tag title is its identifier alone")
    func ownProcessTagTitleIsIdentifierAlone() {
        let key = ItemKey(namespace: "IceApp", identifier: "gear", pid: 999, childIndex: 4)
        #expect(key.tagTitle(isSelf: true) == "gear")
        #expect(key.tagTitle(isSelf: false) == "gear/p999c4")
    }

    @Test("a tag title always names the pid, and the child index only when it has one")
    func tagTitleFormat() {
        let noChild = ItemKey(namespace: "n", identifier: "gear", pid: 12, childIndex: nil)
        #expect(noChild.tagTitle(isSelf: false) == "gear/p12")

        let withChild = ItemKey(namespace: "n", identifier: "gear", pid: 12, childIndex: 0)
        #expect(withChild.tagTitle(isSelf: false) == "gear/p12c0")
    }
}

@Suite("ItemKeying: assigning keys within one process")
struct ItemKeyingTests {
    @Test("a unique, non-empty identifier is declared")
    func uniqueIdentifierIsDeclared() {
        let keyed = ItemKeying.assign(process: process42(), records: [record(childIndex: 0, identifier: "gear")])
        #expect(keyed[0].basis == .declared)
        #expect(keyed[0].key.identifier == "gear")
        #expect(keyed[0].key.childIndex == nil)
    }

    @Test("a unique empty identifier is unnamed, not positional")
    func uniqueEmptyIdentifierIsUnnamed() {
        let records = [record(childIndex: 0, identifier: ""), record(childIndex: 1, identifier: "named")]
        let keyed = ItemKeying.assign(process: process42(), records: records)
        #expect(keyed[0].basis == .unnamed)
        #expect(keyed[0].key.identifier == "")
        #expect(keyed[0].key.childIndex == nil)
        #expect(keyed[1].basis == .declared)
    }

    @Test("equal identifiers in one process are positional, keyed by child index")
    func equalIdentifiersArePositional() {
        let records = [
            record(childIndex: 0, identifier: "shared"),
            record(childIndex: 1, identifier: "shared"),
            record(childIndex: 2, identifier: "unique"),
        ]
        let keyed = ItemKeying.assign(process: process42(), records: records)

        #expect(keyed[0].basis == .positional)
        #expect(keyed[0].key.childIndex == 0)
        #expect(keyed[1].basis == .positional)
        #expect(keyed[1].key.childIndex == 1)
        #expect(keyed[2].basis == .declared)
        #expect(keyed[2].key.childIndex == nil)
    }

    @Test("two empty identifiers in one process are positional too")
    func twoEmptyIdentifiersArePositional() {
        let records = [record(childIndex: 0, identifier: ""), record(childIndex: 5, identifier: "")]
        let keyed = ItemKeying.assign(process: process42(), records: records)
        #expect(keyed[0].basis == .positional && keyed[0].key.childIndex == 0)
        #expect(keyed[1].basis == .positional && keyed[1].key.childIndex == 5)
    }

    @Test("an identifier read with surrounding whitespace is trimmed before keying")
    func identifierIsTrimmedBeforeKeying() {
        let keyed = ItemKeying.assign(process: process42(), records: [record(childIndex: 0, identifier: "  x  ")])
        #expect(keyed[0].key.identifier == "x")
        #expect(keyed[0].basis == .declared)
    }

    @Test("a missing identifier value is treated as empty, not crashing")
    func missingIdentifierValueIsEmpty() {
        let missing = AttributeRead<String>(value: nil, error: "noValue")
        let rec = ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: missing, title: ok(), description: ok(), help: ok(), frame: okFrame())
        let keyed = ItemKeying.assign(process: process42(), records: [rec])
        #expect(keyed[0].key.identifier == "")
        #expect(keyed[0].basis == .unnamed)
    }

    @Test("every assigned key carries the process's own pid and namespace")
    func assignedKeysCarryTheOwningProcess() {
        let process = ProcessInfoRecord(pid: 500, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: nil, isSelf: false)
        let keyed = ItemKeying.assign(process: process, records: [record(childIndex: 0, identifier: "gear")])
        #expect(keyed[0].key.pid == 500)
        #expect(keyed[0].key.namespace == "com.example.a")
    }

    @Test("a survivor's key is byte-identical across three unrelated events elsewhere")
    func survivorKeyIsStableAcrossOtherProcessEvents() {
        // `assign` takes exactly one process and its own records -- nothing
        // about a sibling process (quitting, launching, or failing to read)
        // is ever in scope, so the survivor's key cannot move.
        let survivor = ProcessInfoRecord(pid: 200, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 10, isSelf: false)
        let survivorRecords = [record(childIndex: 0, identifier: "gear")]

        let baseline = ItemKeying.assign(process: survivor, records: survivorRecords)
        let afterSiblingQuit = ItemKeying.assign(process: survivor, records: survivorRecords)
        let afterThirdLaunchedAndSiblingReadFailed = ItemKeying.assign(process: survivor, records: survivorRecords)

        #expect(baseline == afterSiblingQuit)
        #expect(afterSiblingQuit == afterThirdLaunchedAndSiblingReadFailed)
        #expect(baseline.map(\.key.encoded) == afterThirdLaunchedAndSiblingReadFailed.map(\.key.encoded))
    }
}

@Suite("TagCollision: dropping items that share a tag")
struct TagCollisionTests {
    @Test("a forced residual collision on (namespace, tag title) drops every colliding item")
    func forcedResidualCollisionDropsAll() {
        let keyA = ItemKey(namespace: "com.example.a", identifier: "gear", pid: 500, childIndex: nil)
        let keyB = ItemKey(namespace: "com.example.a", identifier: "gear", pid: 500, childIndex: nil)
        let survivorKey = ItemKey(namespace: "com.example.b", identifier: "x", pid: 501, childIndex: nil)

        let recordA = KeyedRecord(record: goodRecord(childIndex: 0), key: keyA, basis: .declared)
        let recordB = KeyedRecord(record: goodRecord(childIndex: 1), key: keyB, basis: .declared)
        let survivor = KeyedRecord(record: goodRecord(childIndex: 2), key: survivorKey, basis: .declared)

        let (kept, collided) = TagCollision.split([recordA, recordB, survivor], isSelf: { _ in false })

        #expect(kept.map(\.record.childIndex) == [2])
        #expect(Set(collided.map(\.record.childIndex)) == Set([0, 1]))
    }

    @Test("no collision means everything is kept")
    func noCollisionKeepsEverything() {
        let items = [
            KeyedRecord(record: goodRecord(childIndex: 0), key: ItemKey(namespace: "a", identifier: "x", pid: 1, childIndex: nil), basis: .declared),
            KeyedRecord(record: goodRecord(childIndex: 1), key: ItemKey(namespace: "b", identifier: "x", pid: 2, childIndex: nil), basis: .declared),
        ]
        let (kept, collided) = TagCollision.split(items, isSelf: { _ in false })
        #expect(kept.count == 2)
        #expect(collided.isEmpty)
    }

    @Test("the isSelf closure decides which tag title is used for grouping")
    func isSelfClosureAffectsGrouping() {
        // Ice's own item (isSelf) tags as "gear"; a third-party item whose
        // identifier happens to be "gear" at pid 12 tags as "gear/p12" -- they
        // must not collide.
        let ownKey = ItemKey(namespace: "IceApp", identifier: "gear", pid: 900, childIndex: nil)
        let otherKey = ItemKey(namespace: "IceApp", identifier: "gear", pid: 12, childIndex: nil)
        let own = KeyedRecord(record: goodRecord(childIndex: 0), key: ownKey, basis: .declared)
        let other = KeyedRecord(record: goodRecord(childIndex: 1), key: otherKey, basis: .declared)

        let (kept, collided) = TagCollision.split([own, other], isSelf: { $0 == 900 })
        #expect(kept.count == 2)
        #expect(collided.isEmpty)
    }
}

// MARK: - Fixtures

private func process42() -> ProcessInfoRecord {
    ProcessInfoRecord(pid: 42, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: nil, isSelf: false)
}

private func ok(_ value: String = "") -> AttributeRead<String> {
    AttributeRead(value: value, error: "success")
}

private func okFrame(_ value: BarRect = BarRect(minX: 0, minY: 0, width: 10, height: 10)) -> AttributeRead<BarRect> {
    AttributeRead(value: value, error: "success")
}

private func record(childIndex: Int, identifier: String) -> ExtrasRecord {
    ExtrasRecord(childIndex: childIndex, role: ok("AXMenuBarItem"), identifier: ok(identifier), title: ok(), description: ok(), help: ok(), frame: okFrame())
}

private func goodRecord(childIndex: Int) -> ExtrasRecord {
    record(childIndex: childIndex, identifier: "x")
}
