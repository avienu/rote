import Foundation

/// First-letter typing (§6.2): the user types the first letter of each word in
/// order. A wrong letter reveals the word and counts one error.
public struct FirstLetterSession: Hashable, Sendable {
    public let words: [Token]
    public private(set) var position = 0
    public private(set) var errors = 0
    /// Word indices revealed because of a wrong letter.
    public private(set) var revealed: Set<Int> = []

    public init(tokens: [Token]) {
        words = tokens.filter(\.isWord)
    }

    public var wordCount: Int { words.count }
    public var isComplete: Bool { position >= words.count }
    public var accuracy: Double { wordCount == 0 ? 1 : 1 - Double(errors) / Double(wordCount) }

    /// Handles one typed character. Whitespace is ignored. Returns whether it
    /// matched. Returns nil when the session is already complete or the input
    /// was ignored.
    @discardableResult
    public mutating func type(_ character: Character) -> Bool? {
        guard !isComplete, !character.isWhitespace else { return nil }
        let expected = words[position].normalized.first.map { String($0) } ?? ""
        let typed = Normalizer.normalize(String(character))
        let ok = !expected.isEmpty && typed == expected
        if !ok {
            errors += 1
            revealed.insert(position)
        }
        position += 1
        return ok
    }

    /// What to show for each word while typing: typed words in full, the rest hidden.
    public func reveal(wordIndex: Int) -> WordReveal {
        wordIndex < position ? .full : .hidden
    }
}
