import Foundation

/// Progressive reveal on a transition card: next letter → next word → whole line.
public struct HintState: Hashable, Sendable {
    public private(set) var level: HintLevel = .none
    /// Words fully revealed, from the start of the line.
    public private(set) var revealedWords = 0
    /// Whether the word after `revealedWords` shows its first letter.
    public private(set) var partialLetter = false
    public private(set) var hintsUsed = 0

    public init() {}

    public var maxGrade: Grade { level.maxGrade }

    /// Applies the next hint in the sequence. `wordCount` is the target's word count.
    public mutating func next(wordCount: Int) {
        hintsUsed += 1
        switch level {
        case .none:
            level = .nextLetter
            partialLetter = revealedWords < wordCount
        case .nextLetter:
            level = .nextWord
            partialLetter = false
            revealedWords = min(wordCount, revealedWords + 1)
        case .nextWord, .wholeLine:
            level = .wholeLine
            revealedWords = wordCount
            partialLetter = false
        }
    }

    public func reveal(wordIndex: Int) -> WordReveal {
        if wordIndex < revealedWords { return .full }
        if wordIndex == revealedWords, partialLetter { return .firstLetter }
        return .hidden
    }

    /// Opens the card at `.firstLetters` for the lapse rule (§6.5) without
    /// counting as a hint; the grade cap for that case is applied separately.
    public static func firstLettersOpening() -> HintState {
        var h = HintState()
        h.level = .none
        h.opensFirstLetters = true
        return h
    }

    public private(set) var opensFirstLetters = false

    public func render(_ line: CardLine) -> String {
        if opensFirstLetters, level == .none {
            return LineMask.render(text: line.text, tokens: line.tokens, style: .lettersOnly) { _ in .firstLetter }
        }
        return LineMask.render(text: line.text, tokens: line.tokens, style: .underscores) { reveal(wordIndex: $0) }
    }
}
