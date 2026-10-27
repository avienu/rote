import Foundation

/// Produces the comparison form of a word. Applied identically to poem tokens
/// and to speech transcripts. Never applied to displayed text.
public enum Normalizer {
    /// NFKC → lowercase → fold curly quotes and dashes → strip punctuation except
    /// internal apostrophes → fold diacritics for English locales.
    public static func normalize(_ surface: String, locale: String = "en-US") -> String {
        var s = surface.precomposedStringWithCompatibilityMapping.lowercased()
        s = foldQuotesAndDashes(s)
        s = String(s.filter { !($0.isPunctuation || $0.isSymbol) || $0 == "'" })
        while s.first == "'" { s.removeFirst() }
        while s.last == "'" { s.removeLast() }
        if isEnglish(locale) {
            s = s.folding(options: .diacriticInsensitive, locale: nil)
        }
        return s
    }

    public static func isEnglish(_ locale: String) -> Bool {
        locale.lowercased().hasPrefix("en")
    }

    static func foldQuotesAndDashes(_ s: String) -> String {
        String(s.map { c -> Character in
            switch c {
            case "\u{2019}", "\u{2018}", "\u{201B}", "\u{2032}", "`", "\u{00B4}": return "'"
            case "\u{201C}", "\u{201D}", "\u{201E}", "\u{2033}": return "\""
            case "\u{2013}", "\u{2014}", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2015}": return "-"
            case "\u{2026}": return "."
            default: return c
            }
        })
    }
}
