import Foundation
import Testing
@testable import IceCore

/// Owner-facing text as data (plan 2026-11-13-zh-hant, D3): a template the app
/// looks up, and arguments IceCore substitutes; English is the identity lookup.
@Suite("OwnerMessage")
struct OwnerMessageTests {
    /// A lookup that marks every template it was asked for.
    static func bracketed(_ template: String) -> String {
        "[\(template)]"
    }

    @Test("a template without placeholders renders as looked up")
    func plain() {
        let message = OwnerMessage("Hello.")
        #expect(message.rendered() == "Hello.")
        #expect(message.rendered(with: Self.bracketed) == "[Hello.]")
    }

    @Test("placeholders take the arguments in order, after the lookup")
    func substitutesInOrder() {
        let message = OwnerMessage("%@ then %@", .verbatim("a"), .verbatim("b"))
        #expect(message.rendered() == "a then b")
        #expect(message.rendered(with: { _ in "%@ 然後 %@" }) == "a 然後 b")
    }

    @Test("a nested message is looked up too; a verbatim argument never is")
    func nested() {
        let message = OwnerMessage("Why: %@ (%@)", .message(OwnerMessage("inner")), .verbatim("name"))
        #expect(message.rendered(with: Self.bracketed) == "[Why: [inner] (name)]")
    }

    @Test("a list is joined with the looked-up separator")
    func list() {
        let message = OwnerMessage("Items: %@", .list([.verbatim("A"), .message(OwnerMessage("an item")), .verbatim("C")]))
        #expect(message.rendered() == "Items: A, an item, C")
        let chinese: (String) -> String = { template in
            switch template {
            case ", ": "、"
            case "Items: %@": "項目：%@"
            case "an item": "某個項目"
            default: template
            }
        }
        #expect(message.rendered(with: chinese) == "項目：A、某個項目、C")
    }

    @Test("a literal %% is a percent sign, and does not take an argument")
    func percent() {
        let message = OwnerMessage("100%% of %@", .verbatim("x"))
        #expect(message.rendered() == "100% of x")
    }

    @Test("too few arguments leave the placeholder; too many are dropped; neither crashes")
    func mismatchedArguments() {
        #expect(OwnerMessage("%@ and %@", .verbatim("a")).rendered() == "a and %@")
        #expect(OwnerMessage("only %@", .verbatim("a"), .verbatim("b")).rendered() == "only a")
        #expect(OwnerMessage("ends with %").rendered() == "ends with %")
        #expect(OwnerMessage("%x stays").rendered() == "%x stays")
    }

    @Test("an argument containing a placeholder is not expanded again")
    func noReexpansion() {
        #expect(OwnerMessage("name: %@", .verbatim("%@")).rendered() == "name: %@")
    }

    @Test("messages compare as data, not as rendered text")
    func equality() {
        #expect(OwnerMessage("a %@", .verbatim("x")) == OwnerMessage("a %@", .verbatim("x")))
        #expect(OwnerMessage("a %@", .verbatim("x")) != OwnerMessage("a %@", .message(OwnerMessage("x"))))
    }

    /// Writes every template, one JSON array, to `$ICE_DUMP_TEMPLATES` when set
    /// (the zh-Hant completeness check, plan 2026-11-13-zh-hant D6); a no-op otherwise.
    @Test("allTemplates can be dumped for the completeness check")
    func dumpTemplates() throws {
        let templates = OwnerMessage.allTemplates.sorted()
        #expect(!templates.isEmpty)
        guard let path = ProcessInfo.processInfo.environment["ICE_DUMP_TEMPLATES"] else { return }
        let data = try JSONSerialization.data(withJSONObject: templates, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }
}
