import Foundation

/// One line as shown on a card.
public struct CardLine: Hashable, Sendable {
    public var order: Int
    public var stanzaIndex: Int
    public var text: String
    public var isContext: Bool
    public var tokens: [Token]

    public init(order: Int, stanzaIndex: Int, text: String, isContext: Bool, tokens: [Token]) {
        self.order = order
        self.stanzaIndex = stanzaIndex
        self.text = text
        self.isContext = isContext
        self.tokens = tokens
    }
}

/// Content of a transition card (§6.2): the previous `contextLines` lines in
/// full, then the target line. The title stands in for context on the first line.
public struct TransitionCard: Hashable, Sendable {
    public var poemTitle: String
    public var context: [CardLine]
    public var target: CardLine

    public init(poemTitle: String, context: [CardLine], target: CardLine) {
        self.poemTitle = poemTitle
        self.context = context
        self.target = target
    }

    /// True when the title should be shown because no earlier line exists.
    public var showsTitleAsContext: Bool { context.isEmpty }

    /// Stanza breaks fall between consecutive shown lines of different stanzas.
    public func hasStanzaBreak(before line: CardLine) -> Bool {
        let shown = context + [target]
        guard let idx = shown.firstIndex(of: line), idx > 0 else { return false }
        return shown[idx - 1].stanzaIndex != line.stanzaIndex
    }

    public var contextOrders: [Int] { context.map(\.order) }

    public static func make(poem: Poem, targetOrder: Int, contextLines: Int? = nil) -> TransitionCard? {
        let lines = poem.orderedLines
        guard let targetIndex = lines.firstIndex(where: { $0.order == targetOrder }) else { return nil }
        let count = contextLines ?? poem.settings.contextLines
        let start = max(0, targetIndex - count)
        let context = lines[start..<targetIndex].map(Self.cardLine)
        return TransitionCard(poemTitle: poem.title, context: context, target: cardLine(lines[targetIndex]))
    }

    static func cardLine(_ line: Line) -> CardLine {
        CardLine(order: line.order, stanzaIndex: line.stanza?.order ?? 0, text: line.text,
                 isContext: line.isContext, tokens: line.tokens)
    }
}
