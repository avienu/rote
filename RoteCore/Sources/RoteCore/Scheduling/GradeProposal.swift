import Foundation

/// Hints on a transition card, each capping the maximum grade (§6.2).
public enum HintLevel: Int, Codable, Hashable, Sendable, Comparable, CaseIterable {
    case none = 0, nextLetter, nextWord, wholeLine

    public static func < (a: HintLevel, b: HintLevel) -> Bool { a.rawValue < b.rawValue }

    public var maxGrade: Grade {
        switch self {
        case .none: .easy
        case .nextLetter: .good
        case .nextWord: .hard
        case .wholeLine: .again
        }
    }
}

public enum GradeProposal {
    /// Transition card: ≥95% → `.good` (user may bump to `.easy`), 80–95% →
    /// `.hard`, <80% → `.again`; capped by the hint level and by the lapse rule.
    public static func forCard(accuracy: Double, hint: HintLevel = .none, capAtGood: Bool = false) -> Grade {
        let raw: Grade = accuracy >= 0.95 ? .good : (accuracy >= 0.80 ? .hard : .again)
        return Grade.min(raw, maxGrade(hint: hint, capAtGood: capAtGood))
    }

    /// Highest grade the user may pick on this card.
    public static func maxGrade(hint: HintLevel, capAtGood: Bool) -> Grade {
        capAtGood ? Grade.min(hint.maxGrade, .good) : hint.maxGrade
    }

    /// Propagated grade from a multi-line recitation (§7.2). Never `.easy`.
    public static func forPropagation(accuracy: Double) -> Grade {
        accuracy >= 0.95 ? .good : (accuracy >= 0.80 ? .hard : .again)
    }

    /// Hand-off seed grade from consolidation accuracy (§5.5).
    public static func forHandoff(accuracy: Double) -> Grade {
        accuracy >= 0.95 ? .easy : (accuracy >= 0.85 ? .good : (accuracy >= 0.70 ? .hard : .again))
    }
}
