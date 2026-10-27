import Foundation

/// Tiny per-locale table of forms that speech recognition conflates with
/// archaic contractions. Equivalent words count as correct but are flagged.
public enum Equivalence {
    /// Classes of mutually equivalent normalized forms, keyed by language code.
    public static let classes: [String: [Set<String>]] = [
        "en": [
            ["o'er", "over"],
            ["e'er", "ever"],
            ["ne'er", "never"],
            ["tis", "'tis"],
            ["twas", "'twas"],
        ]
    ]

    public static func areEquivalent(_ a: String, _ b: String, locale: String = "en-US") -> Bool {
        guard a != b else { return true }
        let language = String(locale.lowercased().prefix(2))
        guard let table = classes[language] else { return false }
        return table.contains { $0.contains(a) && $0.contains(b) }
    }
}
