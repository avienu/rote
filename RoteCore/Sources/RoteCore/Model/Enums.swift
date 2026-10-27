import Foundation

/// Review grade. Propagated grades never produce `.easy`.
public enum Grade: String, Codable, Hashable, Sendable, CaseIterable {
    case again, hard, good, easy

    /// Anki-style 1…4, used for keyboard shortcuts.
    public var number: Int {
        switch self {
        case .again: 1
        case .hard: 2
        case .good: 3
        case .easy: 4
        }
    }

    public static func min(_ a: Grade, _ b: Grade) -> Grade { a.number <= b.number ? a : b }
}

public enum PoemStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case draft, acquiring, reviewing, retired
}

/// Cue level during acquisition, from most to least help.
public enum LadderRung: Int, Codable, Hashable, Sendable, CaseIterable, Comparable {
    case full = 0, faded, firstLetters, firstWord, blank

    public static func < (a: LadderRung, b: LadderRung) -> Bool { a.rawValue < b.rawValue }

    /// One rung less help (toward `.blank`).
    public var lessHelp: LadderRung { LadderRung(rawValue: rawValue + 1) ?? .blank }
    /// One rung more help (toward `.full`).
    public var moreHelp: LadderRung { LadderRung(rawValue: rawValue - 1) ?? .full }
}

public enum ReviewSource: String, Codable, Hashable, Sendable {
    case transitionCard, fullRecitation, stanzaRun, acquisition
}

public enum InputMode: String, Codable, Hashable, Sendable, CaseIterable {
    case speech, firstLetterTyping, selfGrade
}

public enum RunScope: Hashable, Codable, Sendable {
    case wholePoem
    case stanza(Int)
}

public enum AcquisitionPhase: String, Codable, Hashable, Sendable {
    case reading, windowing, sleepGate, consolidating, handedOff
}
