import Foundation

/// Applies grades to `TransitionItem`s through a `Scheduler`, keeping the
/// item's mirrored fields and `ReviewLog` in step. All scheduling rules that
/// touch stored items live here, never in UI code.
public struct ReviewEngine<S: Scheduler> {
    public var scheduler: S

    public init(scheduler: S) {
        self.scheduler = scheduler
    }

    /// Decodes the item's opaque state, or starts fresh.
    public func state(of item: TransitionItem, now: Date) -> S.State {
        item.schedulerState.flatMap { try? JSONDecoder().decode(S.State.self, from: $0) } ?? scheduler.newState(now: now)
    }

    public func retrievability(of item: TransitionItem, now: Date) -> Double {
        scheduler.retrievability(state(of: item, now: now), now: now)
    }

    /// Reviews `item` with `grade`. `maxDue` caps the proposed due date (used
    /// by propagation's guardrail). Returns the log, already attached to the item.
    @discardableResult
    public func apply(grade: Grade, to item: TransitionItem, now: Date, source: ReviewSource, mode: InputMode,
                      wordErrors: Int? = nil, wordCount: Int? = nil, elapsedMs: Int? = nil,
                      hintsUsed: Int = 0, asrCorrections: Int = 0, maxDue: Date? = nil) -> ReviewLog {
        let outcome = scheduler.review(state(of: item, now: now), grade: grade, now: now)
        var due = outcome.due
        if let maxDue, due > maxDue { due = max(maxDue, now) }

        item.schedulerState = try? JSONEncoder().encode(outcome.state)
        item.due = due
        item.stability = outcome.stability
        item.difficulty = outcome.difficulty
        item.lapses = outcome.lapses
        item.reps = outcome.reps
        item.lastReviewedAt = now
        item.previousIntervalDays = max(0, due.timeIntervalSince(now) / 86_400)
        item.consecutiveLapses = grade == .again ? item.consecutiveLapses + 1 : 0

        let log = ReviewLog(reviewedAt: now, grade: grade, source: source, mode: mode)
        log.wordErrors = wordErrors
        log.wordCount = wordCount
        log.elapsedMs = elapsedMs
        log.hintsUsed = hintsUsed
        log.asrCorrections = asrCorrections
        log.elapsedDays = outcome.elapsedDays
        log.scheduledDays = item.previousIntervalDays
        log.item = item
        item.logs = (item.logs ?? []) + [log]
        return log
    }
}

extension TransitionItem {
    /// §6.5: after two lapses in a row the next card opens at `.firstLetters`
    /// and the maximum grade is `.good`. Clears after one clean pass.
    public var opensWithFirstLetters: Bool { consecutiveLapses >= 2 }
}
