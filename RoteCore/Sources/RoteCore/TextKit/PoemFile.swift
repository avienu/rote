import Foundation

/// A poem text file with an optional two-line header:
///
///     Title
///     Author
///
///     first line of the poem…
///
/// The header is recognised only when the third line is blank and the first
/// two lines look like a title and a name rather than verse: no indentation,
/// no `@`, no terminal punctuation, and a short author line. The body is
/// returned exactly as written; the editor shows the result for confirmation
/// (SPEC §4.1), so a false positive is visible and a keystroke away from fixed.
public struct PoemFile: Hashable, Sendable {
    public var title: String?
    public var author: String?
    /// Everything after the header, or the whole text when there is none.
    public var body: String

    public init(title: String? = nil, author: String? = nil, body: String) {
        self.title = title
        self.author = author
        self.body = body
    }

    public static func parse(_ contents: String) -> PoemFile {
        let text = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 4,
              looksLikeHeaderLine(lines[0]), looksLikeHeaderLine(lines[1]),
              lines[2].allSatisfy(\.isWhitespace),
              !lines[3].allSatisfy(\.isWhitespace),
              lines[1].split(whereSeparator: \.isWhitespace).count <= maxAuthorWords
        else { return PoemFile(body: text) }
        return PoemFile(
            title: PoemParser.trimTrailingWhitespace(lines[0]),
            author: PoemParser.trimTrailingWhitespace(lines[1]),
            body: lines[3...].joined(separator: "\n")
        )
    }

    static let maxAuthorWords = 8
    static let terminalPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?"]

    static func looksLikeHeaderLine(_ line: String) -> Bool {
        guard let first = line.first, !first.isWhitespace, first != PoemParser.contextMarker,
              let last = PoemParser.trimTrailingWhitespace(line).last
        else { return false }
        return !terminalPunctuation.contains(last)
    }
}
