import Foundation

/// One line of a parsed poem. `order` is global within the poem, 0-based.
public struct ParsedLine: Codable, Hashable, Sendable {
    public var order: Int
    public var stanzaIndex: Int
    /// Exact text including leading whitespace; trailing whitespace trimmed.
    public var text: String
    /// True when the source line was prefixed with `@`. The `@` is not in `text`.
    public var isContext: Bool

    public init(order: Int, stanzaIndex: Int, text: String, isContext: Bool) {
        self.order = order
        self.stanzaIndex = stanzaIndex
        self.text = text
        self.isContext = isContext
    }
}

public struct ParsedStanza: Codable, Hashable, Sendable {
    public var order: Int
    public var lines: [ParsedLine]

    public init(order: Int, lines: [ParsedLine]) {
        self.order = order
        self.lines = lines
    }
}

/// The structural result of parsing pasted text. Pure value; no storage.
public struct ParsedPoem: Codable, Hashable, Sendable {
    public var stanzas: [ParsedStanza]

    public init(stanzas: [ParsedStanza]) {
        self.stanzas = stanzas
    }

    /// All lines in order.
    public var lines: [ParsedLine] { stanzas.flatMap(\.lines) }

    /// Lines that are asked (not context).
    public var askedLines: [ParsedLine] { lines.filter { !$0.isContext } }

    /// The first non-empty line, offered as a title when the user left it blank.
    public var suggestedTitle: String? {
        lines.first.map { $0.text.trimmingCharacters(in: .whitespaces) }
    }
}
