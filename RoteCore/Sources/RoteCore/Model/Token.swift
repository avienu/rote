import Foundation

/// A tokenized piece of a line. Value type, stored as an array on `Line`.
///
/// `surface` is the exact substring (punctuation included); `normalized` is the
/// comparison form used by alignment. Normalization never touches the poem text.
public struct Token: Codable, Hashable, Sendable {
    /// Exact substring of the line, including punctuation.
    public var surface: String
    /// Lowercased, punctuation-stripped comparison form. Empty for non-words.
    public var normalized: String
    /// False for tokens that are pure punctuation or symbols.
    public var isWord: Bool
    /// UTF-16 offsets into the owning line's `text`.
    public var range: Range<Int>

    public init(surface: String, normalized: String, isWord: Bool, range: Range<Int>) {
        self.surface = surface
        self.normalized = normalized
        self.isWord = isWord
        self.range = range
    }
}
