import Foundation

/// Why a propagated grade ended up where it did; shown in the run summary.
public struct PropagatedGrade: Hashable, Sendable {
    public enum Reason: String, Hashable, Sendable {
        case accuracy, skipped, afterSkipped, hesitation
    }

    public var lineOrder: Int
    public var accuracy: Double
    public var grade: Grade
    public var reasons: Set<Reason>

    public init(lineOrder: Int, accuracy: Double, grade: Grade, reasons: Set<Reason>) {
        self.lineOrder = lineOrder
        self.accuracy = accuracy
        self.grade = grade
        self.reasons = reasons
    }
}

/// Result of applying one recitation to a poem's items.
public struct PropagationReport: Hashable, Sendable {
    public var grades: [PropagatedGrade]
    /// Lines whose due date was held back by the guardrail.
    public var cappedLines: Set<Int>
    public var overallAccuracy: Double

    public init(grades: [PropagatedGrade], cappedLines: Set<Int>, overallAccuracy: Double) {
        self.grades = grades
        self.cappedLines = cappedLines
        self.overallAccuracy = overallAccuracy
    }
}

/// Grade propagation (§7): one aligned multi-line recitation updates every
/// asked line's schedule and the word heat map.
public enum Propagation {
    public static let guardrailMultiplier = 2.0

    /// Pure mapping from per-line alignment to grades (§7.1–7.3, 7.7).
    /// `hesitated(order)` says whether a long pause preceded that line.
    public static func grades(for lines: [LineAlignment], hesitated: (Int) -> Bool = { _ in false }) -> [PropagatedGrade] {
        var result: [PropagatedGrade] = []
        var previousSkipped = false
        for line in lines {
            var reasons: Set<PropagatedGrade.Reason> = []
            var grade = GradeProposal.forPropagation(accuracy: line.accuracy)
            if line.isSkipped {
                grade = .again
                reasons.insert(.skipped)
            } else {
                reasons.insert(.accuracy)
                if previousSkipped {
                    grade = Grade.min(grade, .hard)
                    reasons.insert(.afterSkipped)
                }
                if hesitated(line.lineOrder) {
                    grade = Grade.min(grade, .hard)
                    reasons.insert(.hesitation)
                }
            }
            result.append(PropagatedGrade(lineOrder: line.lineOrder, accuracy: line.accuracy, grade: grade, reasons: reasons))
            previousSkipped = line.isSkipped
        }
        return result
    }

    /// Guardrail (§7.5): never later than now + 2 × the previous interval.
    /// Items that never had an interval are not capped.
    public static func maxDue(for item: TransitionItem, now: Date) -> Date? {
        guard item.previousIntervalDays > 0 else { return nil }
        return now.addingTimeInterval(item.previousIntervalDays * guardrailMultiplier * 86_400)
    }

    /// Applies an attempt to the poem: reviews each asked line's item through
    /// the scheduler with the guardrail, logs it, and updates `WordStat`s.
    @discardableResult
    public static func apply<S: Scheduler>(attempt: SpeechAttempt, to poem: Poem, engine: ReviewEngine<S>, source: ReviewSource,
                                           mode: InputMode, now: Date = Date()) -> PropagationReport {
        let perLine = attempt.perLine()
        let grades = grades(for: perLine) { attempt.hesitated(before: $0) }
        var capped: Set<Int> = []

        for g in grades {
            guard let item = poem.item(forLine: g.lineOrder), let line = perLine.first(where: { $0.lineOrder == g.lineOrder }) else { continue }
            let cap = maxDue(for: item, now: now)
            let proposed = engine.scheduler.review(engine.state(of: item, now: now), grade: g.grade, now: now).due
            if let cap, proposed > cap { capped.insert(g.lineOrder) }
            engine.apply(grade: g.grade, to: item, now: now, source: source, mode: mode,
                         wordErrors: line.errors, wordCount: line.wordCount, asrCorrections: attempt.corrections.count, maxDue: cap)
        }
        updateWordStats(poem: poem, perLine: perLine, now: now)
        return PropagationReport(grades: grades, cappedLines: capped, overallAccuracy: attempt.accuracy)
    }

    /// §7.6: every expected token in the span gets an attempt; errors count.
    public static func updateWordStats(poem: Poem, perLine: [LineAlignment], now: Date) {
        var stats = poem.wordStats ?? []
        for line in perLine {
            for op in line.tokenOps {
                let stat: WordStat
                if let existing = stats.first(where: { $0.lineOrder == line.lineOrder && $0.tokenIndex == op.tokenIndex }) {
                    stat = existing
                } else {
                    stat = WordStat(lineOrder: line.lineOrder, tokenIndex: op.tokenIndex)
                    stat.poem = poem
                    stats.append(stat)
                }
                stat.record(error: op.op.isError, at: now)
            }
        }
        poem.wordStats = stats
    }
}
