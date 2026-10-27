import Foundation

/// Splits a line into tokens. Whitespace separates chunks; leading and trailing
/// punctuation of a chunk become their own non-word tokens; internal apostrophes
/// and hyphens stay inside the word (`o'er`, `well-nigh`).
public enum Tokenizer {
    public static func tokenize(_ text: String, locale: String = "en-US") -> [Token] {
        var tokens: [Token] = []
        var offset = 0          // UTF-16 offset of `index`
        var index = text.startIndex

        while index < text.endIndex {
            let c = text[index]
            if c.isWhitespace {
                offset += c.utf16.count
                index = text.index(after: index)
                continue
            }
            // Collect a chunk of non-whitespace characters.
            var chars: [(Character, Int)] = []   // (character, utf16 offset)
            var j = index
            var jOffset = offset
            while j < text.endIndex, !text[j].isWhitespace {
                chars.append((text[j], jOffset))
                jOffset += text[j].utf16.count
                j = text.index(after: j)
            }
            tokens.append(contentsOf: split(chunk: chars, end: jOffset, locale: locale))
            index = j
            offset = jOffset
        }
        return tokens
    }

    /// Only the word tokens' normalized forms, in order.
    public static func words(_ text: String, locale: String = "en-US") -> [String] {
        tokenize(text, locale: locale).filter(\.isWord).map(\.normalized)
    }

    static func isPunctuation(_ c: Character) -> Bool {
        c.isPunctuation || c.isSymbol
    }

    private static func split(chunk: [(Character, Int)], end: Int, locale: String) -> [Token] {
        guard let firstWord = chunk.firstIndex(where: { !isPunctuation($0.0) }) else {
            // Entire chunk is punctuation.
            let surface = String(chunk.map(\.0))
            return [Token(surface: surface, normalized: "", isWord: false, range: chunk[0].1..<end)]
        }
        let lastWord = chunk.lastIndex(where: { !isPunctuation($0.0) })!
        var result: [Token] = []

        if firstWord > 0 {
            let lead = Array(chunk[0..<firstWord])
            result.append(Token(surface: String(lead.map(\.0)), normalized: "", isWord: false,
                                range: lead[0].1..<chunk[firstWord].1))
        }
        let core = Array(chunk[firstWord...lastWord])
        let coreEnd = lastWord + 1 < chunk.count ? chunk[lastWord + 1].1 : end
        let surface = String(core.map(\.0))
        result.append(Token(surface: surface, normalized: Normalizer.normalize(surface, locale: locale),
                            isWord: true, range: core[0].1..<coreEnd))
        if lastWord + 1 < chunk.count {
            let trail = Array(chunk[(lastWord + 1)...])
            result.append(Token(surface: String(trail.map(\.0)), normalized: "", isWord: false,
                                range: trail[0].1..<end))
        }
        return result
    }
}
