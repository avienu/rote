import Foundation

/// Renders a line at a ladder rung (§5.3). Deterministic: the same line at the
/// same rung always shows the same cue. Context lines always render `.full`.
public enum CueRenderer {
    public static func render(text: String, tokens: [Token], rung: LadderRung, isContext: Bool = false) -> String {
        if isContext { return text }
        switch rung {
        case .full:
            return text
        case .faded:
            // Even-indexed words in full; odd ones keep their first letter and
            // a length cue.
            return LineMask.render(text: text, tokens: tokens, style: .underscores) { $0.isMultiple(of: 2) ? .full : .firstLetter }
        case .firstLetters:
            return LineMask.render(text: text, tokens: tokens, style: .lettersOnly) { _ in .firstLetter }
        case .firstWord:
            return LineMask.render(text: text, tokens: tokens, style: .underscores) { $0 == 0 ? .full : .hidden }
        case .blank:
            return ""
        }
    }

    public static func render(_ line: CardLine, rung: LadderRung) -> String {
        render(text: line.text, tokens: line.tokens, rung: rung, isContext: line.isContext)
    }
}
