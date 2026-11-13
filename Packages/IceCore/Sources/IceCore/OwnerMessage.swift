/// Owner-facing text as data (plan 2026-11-13-zh-hant, D3). IceCore imports
/// nothing, so it cannot look up a translation: it says which English template
/// it means and what goes in it, and the app looks the template up in its own
/// catalog. Equality is of the data, so two call sites never disagree on
/// whether two lines are the same because they rendered them differently.
public struct OwnerMessage: Equatable, Sendable {
    /// One value for a `%@` of the template.
    public indirect enum Argument: Equatable, Sendable {
        /// Shown as is: another app's item name.
        case verbatim(String)
        /// Looked up and rendered in its turn.
        case message(OwnerMessage)
        /// Joined with the looked-up separator `", "`.
        case list([Argument])
    }

    /// Today's English sentence, `%@` where an argument goes, `%%` for a
    /// percent sign: the catalog's key.
    public let template: String
    public let arguments: [Argument]

    public init(_ template: String, _ arguments: Argument...) {
        self.template = template
        self.arguments = arguments
    }

    public init(_ template: String, arguments: [Argument]) {
        self.template = template
        self.arguments = arguments
    }

    /// The text, `localize` giving each template's translation (identity:
    /// English). Too few arguments leave a `%@`; extra ones are dropped; an
    /// argument's own text is never expanded again.
    public func rendered(with localize: (String) -> String = { $0 }) -> String {
        let values = arguments.map { Self.render($0, localize) }
        return Self.substitute(localize(template), values)
    }

    private static func render(_ argument: Argument, _ localize: (String) -> String) -> String {
        switch argument {
        case .verbatim(let text): text
        case .message(let message): message.rendered(with: localize)
        case .list(let items): items.map { render($0, localize) }.joined(separator: localize(listSeparator))
        }
    }

    private static func substitute(_ template: String, _ values: [String]) -> String {
        var result = ""
        var next = values.makeIterator()
        var characters = template.makeIterator()
        while let character = characters.next() {
            guard character == "%" else {
                result.append(character)
                continue
            }
            switch characters.next() {
            case "@":
                result += next.next() ?? "%@"
            case "%":
                result.append("%")
            case let other?:
                result.append("%")
                result.append(other)
            case nil:
                result.append("%")
            }
        }
        return result
    }

    static let listSeparator = ", "

    /// Every template IceCore can ask the app for: the catalog must translate
    /// each (plan D6).
    public static var allTemplates: Set<String> {
        Set([listSeparator, IceBarHidingStatus.joinTemplate, IceBarHidingStatus.limits, IcePlacementNotice.template])
            .union(IceBarHidingStatus.templates)
    }
}
