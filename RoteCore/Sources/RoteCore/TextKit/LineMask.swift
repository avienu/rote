import Foundation

public enum WordReveal: Hashable, Sendable {
    case full
    case firstLetter
    case hidden
}

/// Renders a line with some words hidden. Whitespace, indentation and
/// punctuation come straight from the original text; only word tokens change.
public enum LineMask {
    public enum Style: Hashable, Sendable {
        /// Hidden words become `▁` runs of the word's length; a first-letter
        /// reveal shows the letter followed by `▁` for the rest.
        case underscores
        /// Hidden words vanish; a first-letter reveal is just the letter.
        case lettersOnly
    }

    public static let blank: Character = "\u{2581}"

    /// `reveal` receives the word index (counting word tokens only).
    public static func render(text: String, tokens: [Token], style: Style, reveal: (Int) -> WordReveal) -> String {
        var out = ""
        var cursor = 0          // UTF-16 offset
        var wordIndex = 0
        let utf16 = text.utf16

        func slice(_ range: Range<Int>) -> String {
            let s = utf16.index(utf16.startIndex, offsetBy: range.lowerBound)
            let e = utf16.index(utf16.startIndex, offsetBy: range.upperBound)
            return String(utf16[s..<e]) ?? ""
        }

        for token in tokens {
            if token.range.lowerBound > cursor { out += slice(cursor..<token.range.lowerBound) }
            if token.isWord {
                out += render(word: token.surface, reveal: reveal(wordIndex), style: style)
                wordIndex += 1
            } else {
                out += token.surface
            }
            cursor = token.range.upperBound
        }
        if cursor < utf16.count { out += slice(cursor..<utf16.count) }
        return out
    }

    public static func render(word: String, reveal: WordReveal, style: Style) -> String {
        let length = word.count
        switch (reveal, style) {
        case (.full, _): return word
        case (.hidden, .underscores): return String(repeating: blank, count: max(1, length))
        case (.hidden, .lettersOnly): return ""
        case (.firstLetter, .underscores): return String(word.prefix(1)) + String(repeating: blank, count: max(0, length - 1))
        case (.firstLetter, .lettersOnly): return String(word.prefix(1))
        }
    }
}
